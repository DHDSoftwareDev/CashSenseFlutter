// CashSense-BackupComplete
// Marks an existing backup record as READY after client uploads to S3
// Runtime: Node.js 24.x (ESM)

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

const USERS_TABLE = process.env.USERS_TABLE ?? "CashSense-Users";
const BACKUPS_TABLE = process.env.BACKUPS_TABLE ?? "CashSense-Backups";

export const handler = async (event) => {
  try {
    const method = (
      event?.requestContext?.http?.method ||
      event?.httpMethod ||
      ""
    ).toUpperCase();

    console.log("CashSense-BackupComplete invoked", {
      method,
      rawPath: event?.rawPath || event?.path,
      hasAuthorizer: !!event?.requestContext?.authorizer,
      headersPresent: !!event?.headers,
    });

    if (method && method !== "POST") {
      return json(405, { ok: false, message: "Method Not Allowed" });
    }

    const claims = getClaims(event);
    const userId = getUserIdFromClaimsOrHeaders(claims, event);
    if (!userId) return json(401, { ok: false, message: "Unauthorized" });

    const userRow = await getUserRow(userId);
    const premium = isPremiumUser(userRow);

    console.log("BackupComplete premium check", {
      userId,
      premium,
      devOverride: !!userRow?.devOverride,
      tier: userRow?.tier,
      premiumUntil: userRow?.premiumUntil,
    });

    if (!premium) {
      return json(403, { ok: false, message: "Premium required" });
    }

    const body = safeJson(event?.body);
    const {
      backupId,
      sha256,
      size,
      appVersion,
      deviceId,
      isAuto,
      schemaVersion,
    } = body;

    if (!backupId) {
      return json(400, { ok: false, message: "backupId is required" });
    }

    const nowIso = new Date().toISOString();

    // Update the existing backup row created by BackupInit
    await ddb.send(
      new UpdateCommand({
        TableName: BACKUPS_TABLE,
        Key: { userId, backupId },
        ConditionExpression: "attribute_exists(userId) AND attribute_exists(backupId)",
        UpdateExpression:
          "SET #s = :s, sha256 = :h, #sz = :z, appVersion = :av, deviceId = :d, isAuto = :a, schemaVersion = :sv, updatedAt = :u",
        ExpressionAttributeNames: {
          "#s": "status",
          "#sz": "size",
        },
        ExpressionAttributeValues: {
          ":s": "READY",
          ":h": sha256 ?? null,
          ":z": size ?? null,
          ":av": appVersion ?? null,
          ":d": deviceId ?? null,
          ":a": !!isAuto,
          ":sv": Number(schemaVersion ?? 1),
          ":u": nowIso,
        },
      })
    );

    return json(200, { ok: true, backupId });
  } catch (e) {
    console.error("CashSense-BackupComplete error", e);

    // nicer message if backup record wasn't found
    if (e?.name === "ConditionalCheckFailedException") {
      return json(404, {
        ok: false,
        message: "Backup record not found. Did you call BackupInit first?",
      });
    }

    return json(500, { ok: false, message: "Server error", detail: safeErr(e) });
  }
};

// --------------------
// Premium + Users helpers
// --------------------

async function getUserRow(userId) {
  const r = await ddb.send(
    new GetCommand({
      TableName: USERS_TABLE,
      Key: { userId },
    })
  );
  return r?.Item ?? null;
}

function isPremiumUser(u) {
  if (!u) return false;

  // ✅ new format
  if (u.devOverride === true) return true;

  const premiumUntil = Number(u.premiumUntil ?? 0);
  if (Number.isFinite(premiumUntil) && premiumUntil > Date.now()) return true;

  if (String(u.tier ?? "").toLowerCase() === "premium") return true;

  // ✅ old format compatibility
  const isPremium = !!u.isPremium;
  const expiresAt = u.premiumExpiresAt ? Date.parse(u.premiumExpiresAt) : null;
  if (isPremium && (!expiresAt || Date.now() <= expiresAt)) return true;

  return false;
}

function getClaims(event) {
  return (
    event?.requestContext?.authorizer?.jwt?.claims ||
    event?.requestContext?.authorizer?.claims ||
    null
  );
}

function getUserIdFromClaimsOrHeaders(claims, event) {
  if (claims?.sub) return String(claims.sub);
  return null;
}

// --------------------
// Misc helpers
// --------------------

function safeJson(body) {
  if (!body) return {};
  if (typeof body === "object") return body;
  try {
    return JSON.parse(body);
  } catch {
    return {};
  }
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

function safeErr(e) {
  return {
    name: e?.name,
    message: e?.message,
    code: e?.code,
    $metadata: e?.$metadata,
  };
}
