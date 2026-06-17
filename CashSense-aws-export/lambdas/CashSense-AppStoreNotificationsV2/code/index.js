zip -r CashSense-AppStoreNotificationsV2.zip .
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, QueryCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

const USERS_TABLE = process.env.USERS_TABLE;
const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID;

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

function getAppleEnv() {
  const e = (process.env.APPLE_ENVIRONMENT || "Production").toLowerCase();
  return e.includes("sandbox") ? Environment.SANDBOX : Environment.PRODUCTION;
}

function getVerifier(environment) {
  return new SignedDataVerifier(APPLE_BUNDLE_ID, environment);
}

export const handler = async (event) => {
  try {
    const body = event.body ? JSON.parse(event.body) : {};
    const signedPayload = body.signedPayload;
    if (!signedPayload) return json(400, { ok: false, message: "signedPayload missing" });

    const environment = getAppleEnv();
    const verifier = getVerifier(environment);

    // Verify + decode the notification payload (JWS) :contentReference[oaicite:6]{index=6}
    const notification = await verifier.verifyAndDecodeNotification(signedPayload);

    // Notification has data including signedTransactionInfo (JWS) in many events
    const data = notification.data || {};
    const signedTx = data.signedTransactionInfo;

    if (!signedTx) {
      // Some notification types may not include it; acknowledge anyway.
      return json(200, { ok: true });
    }

    const tx = await verifier.verifyAndDecodeTransaction(signedTx);

    const originalTransactionId = tx.originalTransactionId;
    const expiresMs = tx.expiresDate ? Number(tx.expiresDate) : null;
    const isActive = !!expiresMs && expiresMs > Date.now();
    const premiumExpiresAt = expiresMs ? new Date(expiresMs).toISOString() : null;

    // Find user by originalTransactionId.
    // IMPORTANT: this requires you to store originalTransactionId on user items.
    // Best: add a GSI on CashSense-Users where GSI1PK = originalTransactionId
    // If you don't want a GSI, you can store a separate mapping table. GSI is easiest.

    // If you add GSI:
    // GSI name: originalTransactionId-index
    // partition key: originalTransactionId (String)
    const q = await ddb.send(new QueryCommand({
      TableName: USERS_TABLE,
      IndexName: "originalTransactionId-index",
      KeyConditionExpression: "originalTransactionId = :otid",
      ExpressionAttributeValues: { ":otid": originalTransactionId }
    }));

    const user = q.Items?.[0];
    if (!user?.userId) return json(200, { ok: true }); // No matching user; still acknowledge.

    await ddb.send(new UpdateCommand({
      TableName: USERS_TABLE,
      Key: { userId: user.userId },
      UpdateExpression: "SET isPremium = :p, premiumExpiresAt = :e, updatedAt = :u",
      ExpressionAttributeValues: {
        ":p": isActive,
        ":e": premiumExpiresAt,
        ":u": new Date().toISOString()
      }
    }));

    return json(200, { ok: true });
  } catch (err) {
    console.error(err);
    // Always return 200 for Apple notifications after logging unless you want retries.
    return json(200, { ok: true });
  }
};

