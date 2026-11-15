import { resolve } from './premium-policy.mjs';
// CashSense-BackupInit
// Creates a backup record + returns a presigned S3 PUT URL
// Runtime: Node.js 24.x (ESM)
//
// Tables:
// - CashSense-Users     PK: userId (S)
// - CashSense-Backups   PK: userId (S)  SK: backupId (S)   (recommended)
//
// Env vars:
// - USERS_TABLE=CashSense-Users (optional; defaults)
// - BACKUPS_TABLE=CashSense-Backups (optional; defaults)
// - BACKUPS_BUCKET=... (REQUIRED)

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
} from "@aws-sdk/lib-dynamodb";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import crypto from "crypto";

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

    console.log("CashSense-BackupInit invoked", {
      method,
      rawPath: event?.rawPath || event?.path,
      hasAuthorizer: !!event?.requestContext?.authorizer,
      headersPresent: !!event?.headers,
    });

    // Allow POST only (or empty for Lambda console tests)
    if (method && method !== "POST") {
      return json(405, { ok: false, message: "Method Not Allowed" });
    }

    if (!BACKUPS_BUCKET) {
      return json(500, { ok: false, message: "Missing env var BACKUPS_BUCKET" });
    }

    const claims = getClaims(event);
    const userId = getUserIdFromClaimsOrHeaders(claims, event);
    if (!userId) return json(401, { ok: false, message: "Unauthorized" });

    // Premium check
    const userRow = await getUserRow(userId);

    // Optional but helpful log
    console.log("Backup premium check", {
      userId,
      userRowFound: !!userRow,
      devOverride: !!userRow?.devOverride,
      tier: userRow?.tier,
      premiumUntil: userRow?.premiumUntil,
      isPremium: userRow?.isPremium,
      premiumExpiresAt: userRow?.premiumExpiresAt,
    });

    const premium = isPremiumUser(userRow);
    if (!premium) {
      return json(403, {
        ok: false,
        message: "Premium required",
        reason: !userRow ? "user_missing" : "not_premium",
      });
    }

    const body = safeJson(event?.body);
    const schemaVersion = toInt(body?.schemaVersion, 1);

    const nowIso = new Date().toISOString();
    const backupId = `${nowIso}#${crypto.randomUUID()}`;
    const s3Key = `backups/${userId}/${backupId}.gz`;

    // Presigned PUT URL
    const putCmd = new PutObjectCommand({
      Bucket: BACKUPS_BUCKET,
      Key: s3Key,
      ContentType: "application/gzip",
      Metadata: {
        schemaVersion: String(schemaVersion),
        userId: String(userId),
      },
    });

    const uploadUrl = await getSignedUrl(s3, putCmd, { expiresIn: 900 }); // 15 min

    // Create "PENDING" record (client uploads, then you mark complete in BackupComplete lambda)
    await ddb.send(
      new PutCommand({
        TableName: BACKUPS_TABLE,
        Item: {
          userId,
          backupId,
          createdAt: nowIso,
          updatedAt: nowIso,
          s3Key,
          status: "PENDING",
          schemaVersion,
        },
        // Optional safety if SK exists:
        // ConditionExpression: "attribute_not_exists(userId) AND attribute_not_exists(backupId)"
      })
    );

    return json(200, { ok: true, backupId, s3Key, uploadUrl });
  } catch (e) {
    console.error("CashSense-BackupInit error", e);
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
      Key: { userId }, ConsistentRead: true,
    })
  );
  return r?.Item ?? null;
}


function isPremiumUser(user) { return resolve(user || {}).isPremium; }

// --------------------
// Auth helpers
// --------------------

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

function toInt(v, fallback) {
  const n = Number.parseInt(String(v ?? ""), 10);
  return Number.isFinite(n) ? n : fallback;
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
