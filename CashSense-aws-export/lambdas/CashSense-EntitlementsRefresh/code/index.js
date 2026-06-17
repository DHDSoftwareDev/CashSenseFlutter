import fs from "fs";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import {
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
} from "@apple/app-store-server-library";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

const USERS_TABLE = process.env.USERS_TABLE;
const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID;
const APPLE_ISSUER_ID = process.env.APPLE_ISSUER_ID;
const APPLE_KEY_ID = process.env.APPLE_KEY_ID;
const APPLE_PRIVATE_KEY_B64 = process.env.APPLE_PRIVATE_KEY_B64;

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

function getUserId(event) {
  const claims = event?.requestContext?.authorizer?.jwt?.claims;
  return claims?.sub || null;
}

function getAppleEnv(envStr) {
  const e = (envStr || process.env.APPLE_ENVIRONMENT || "Production").toLowerCase();
  return e.includes("sandbox") ? Environment.SANDBOX : Environment.PRODUCTION;
}

function getAppleClient(environment) {
  if (!APPLE_PRIVATE_KEY_B64 || !APPLE_KEY_ID || !APPLE_ISSUER_ID || !APPLE_BUNDLE_ID) {
    throw new Error("Missing Apple env vars: APPLE_PRIVATE_KEY_B64, APPLE_KEY_ID, APPLE_ISSUER_ID, APPLE_BUNDLE_ID");
  }
  const privateKey = Buffer.from(APPLE_PRIVATE_KEY_B64, "base64").toString("utf8");
  return new AppStoreServerAPIClient(
    privateKey,
    APPLE_KEY_ID,
    APPLE_ISSUER_ID,
    APPLE_BUNDLE_ID,
    environment
  );
}

function getVerifier(environment) {
  // MUST be an array of Buffers
  const appleRootCertificates = [
    fs.readFileSync(new URL("./AppleRootCA-G2.cer", import.meta.url)),
    fs.readFileSync(new URL("./AppleRootCA-G3.cer", import.meta.url)),
    fs.readFileSync(new URL("./AppleIncRootCertificate.cer", import.meta.url)),
  ];

  console.log("certs array?", Array.isArray(appleRootCertificates), "len", appleRootCertificates.length);

  return new SignedDataVerifier(
    appleRootCertificates,
    true,
    environment,
    APPLE_BUNDLE_ID,
    undefined
  );
}

export const handler = async (event) => {
  try {
    const userId = getUserId(event);
    if (!userId) return json(401, { ok: false, message: "Unauthorized" });

    const body = event.body ? JSON.parse(event.body) : {};
    const transactionId = body.transactionId;
    if (!transactionId) return json(400, { ok: false, message: "transactionId is required" });

    const environment = getAppleEnv(body.environment);

    const client = getAppleClient(environment);
    const verifier = getVerifier(environment);

    const txInfo = await client.getTransactionInfo(transactionId);
    const signedTx = txInfo.signedTransactionInfo;

    const decodedTx = await verifier.verifyAndDecodeTransaction(signedTx);

    const productId = decodedTx.productId || null;
    const originalTransactionId = decodedTx.originalTransactionId || null;
    const expiresMs = decodedTx.expiresDate ? Number(decodedTx.expiresDate) : null;

    const isActive = !!expiresMs && expiresMs > Date.now();
    const premiumExpiresAt = expiresMs ? new Date(expiresMs).toISOString() : null;

    if (!USERS_TABLE) throw new Error("Missing USERS_TABLE env var");

    await ddb.send(
      new UpdateCommand({
        TableName: USERS_TABLE,
        Key: { userId },
        UpdateExpression:
          "SET isPremium = :p, premiumExpiresAt = :e, subscriptionSource = :s, productId = :pid, originalTransactionId = :otid, updatedAt = :u",
        ExpressionAttributeValues: {
          ":p": isActive,
          ":e": premiumExpiresAt,
          ":s": "app_store",
          ":pid": productId,
          ":otid": originalTransactionId,
          ":u": new Date().toISOString(),
        },
      })
    );

    return json(200, { ok: true, isPremium: isActive, premiumExpiresAt, productId });
  } catch (err) {
    console.error(err);
    return json(500, { ok: false, message: "Server error" });
  }
};
