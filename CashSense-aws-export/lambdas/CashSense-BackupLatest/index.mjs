// CashSense-BackupLatest (or RestoreLatest)
// Returns a presigned S3 GET URL for the latest READY backup
// Runtime: Node.js 24.x (ESM)

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  QueryCommand,
} from "@aws-sdk/lib-dynamodb";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});
const s3 = new S3Client({});

const USERS_TABLE = process.env.USERS_TABLE ?? "CashSense-Users";
const BACKUPS_TABLE = process.env.BACKUPS_TABLE ?? "CashSense-Backups";
const BACKUPS_BUCKET = process.env.BACKUPS_BUCKET; // REQUIRED

export const handler = async (event) => {
  try {
    const method = (
      event?.requestContext?.http?.method ||
      event?.httpMethod ||
      ""
    ).toUpperCase();

    console.log("CashSense-BackupLatest invoked", {
      method,
      rawPath: event?.rawPath || event?.path,
      hasAuthorizer: !!event?.requestContext?.authorizer,
      headersPresent: !!event?.headers,
    });

    if (!BACKUPS_BUCKET) {
      return json(500, { ok: false, message: "Missing BACKUPS_BUCKET env var" });
    }

    // Most setups use GET, but allow empty for Lambda console tests
    if (method && method !== "GET") {
      return json(405, { ok: false, message: "Method Not Allowed" });
    }

    const claims = getClaims(event);
    const userId = getUserIdFromClaimsOrHeaders(claims, event);
    if (!userId) return json(401, { ok: false, message: "Unauthorized" });

    // Premium check using your current CashSense-Users fields
    const userRow = await getUserRow(userId);
    const premium = isPremiumUser(userRow);

    console.log("BackupLatest premium check", {
      userId,
      premium,
      devOverride: !!userRow?.devOverride,
      tier: userRow?.tier,
      premiumUntil: userRow?.premiumUntil,
    });

    if (!premium) return json(403, { ok: false, message: "Premium required" });

    // Query most recent backups first
    const q = await ddb.send(
      new QueryCommand({
        TableName: BACKUPS_TABLE,
        KeyConditionExpression: "userId = :u",
        ExpressionAttributeValues: { ":u": userId },
        ScanIndexForward: false,
        Limit: 10,
      })
    );

    const items = q.Items ?? [];

    // Prefer READY, but support COMPLETED if you ever rename statuses
    const latest =
      items.find((x) => String(x.status ?? "") === "READY") ||
      items.find((x) => String(x.status ?? "") === "COMPLETED") ||
      null;

    if (!latest) return json(404, { ok: false, message: "No backups found" });
    if (!latest.s3Key) return json(500, { ok: false, message: "Backup record missing s3Key" });

    const getCmd = new GetObjectCommand({
      Bucket: BACKUPS_BUCKET,
      Key: latest.s3Key,
    });

    const downloadUrl = await getSignedUrl(s3, getCmd, { expiresIn: 900 });

    return json(200, {
      ok: true,
      backupId: latest.backupId,
      createdAt: latest.createdAt,
      updatedAt: latest.updatedAt,
      sha256: latest.sha256 ?? null,
      size: latest.size ?? null,
      schemaVersion: latest.schemaVersion ?? 1,
      appVersion: latest.appVersion ?? null,
      deviceId: latest.deviceId ?? null,
      isAuto: latest.isAuto ?? false,
      status: latest.status ?? "READY",
      downloadUrl,
    });
  } catch (e) {
    console.error("CashSense-BackupLatest error", e);
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

  // ✅ new schema
  if (u.devOverride === true) return true;

  const premiumUntil = Number(u.premiumUntil ?? 0);
  if (Number.isFinite(premiumUntil) && premiumUntil > Date.now()) return true;

  if (String(u.tier ?? "").toLowerCase() === "premium") return true;

  // ✅ old schema compatibility
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
