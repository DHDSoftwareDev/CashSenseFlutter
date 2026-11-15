import { resolve } from './premium-policy.mjs';
// CashSense-RegisterDevice (Device Registry + SNS endpoint management + Users upsert + Premium status)
// Runtime: Node.js 24.x (ESM)
//
// Tables:
// - CashSense-DeviceRegistry   PK: userId (S)  SK: deviceToken (S)
// - CashSense-Users            PK: userId (S)
//
// Required env vars:
// - DEVICE_REGISTRY_TABLE=CashSense-DeviceRegistry
// - USERS_TABLE=CashSense-Users
// - SNS_PLATFORM_APPLICATION_ARN_IOS=...                  (production APNs - TestFlight/AppStore)
// - SNS_PLATFORM_APPLICATION_ARN_IOS_SANDBOX=...          (optional - debug builds only)
// - SNS_PLATFORM_APPLICATION_ARN_ANDROID=...              (optional)

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
  DeleteCommand,
  QueryCommand,
} from "@aws-sdk/lib-dynamodb";
import {
  SNSClient,
  CreatePlatformEndpointCommand,
  SetEndpointAttributesCommand,
  GetEndpointAttributesCommand,
  DeleteEndpointCommand,
} from "@aws-sdk/client-sns";

const DEVICE_REGISTRY_TABLE =
  process.env.DEVICE_REGISTRY_TABLE ?? "CashSense-DeviceRegistry";

const USERS_TABLE = process.env.USERS_TABLE ?? "CashSense-Users";

const SNS_PLATFORM_APPLICATION_ARN_IOS =
  process.env.SNS_PLATFORM_APPLICATION_ARN_IOS ?? "";
const SNS_PLATFORM_APPLICATION_ARN_IOS_SANDBOX =
  process.env.SNS_PLATFORM_APPLICATION_ARN_IOS_SANDBOX ?? "";
const SNS_PLATFORM_APPLICATION_ARN_ANDROID =
  process.env.SNS_PLATFORM_APPLICATION_ARN_ANDROID ?? "";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});
const sns = new SNSClient({});

// --------------------
// Handler
// --------------------
export const handler = async (event) => {
  try {
    const claims = getClaims(event);
    const userId = getUserIdFromClaims(claims);

    console.log("CashSense-RegisterDevice invoked", {
      method: (event?.requestContext?.http?.method || event?.httpMethod || "").toUpperCase(),
      rawPath: event?.rawPath || event?.path,
      hasAuthorizer: !!event?.requestContext?.authorizer,
      hasSub: !!claims?.sub,
    });

    if (!userId) return json(401, { message: "Unauthorized" });

    // 1) Ensure user row exists
    const userRow = await ensureUserExists(userId, claims);

    // 2) Compute premium
    const premium = computePremiumFromUser(userRow);

    const method = (event?.requestContext?.http?.method || event?.httpMethod || "").toUpperCase();
    const path = normalizePath(event);
    const params = event?.pathParameters || {};

    const deviceTokenFromPath =
      params.deviceToken || extractIdFromPath(path, "devices");

    if (!path.startsWith("/devices")) {
      return json(404, { message: "Not Found" });
    }

    if (method === "GET" && !deviceTokenFromPath) {
      const res = await listDevices(userId);
      return attachUserToResponse(res, userRow, premium);
    }

    if (method === "GET" && deviceTokenFromPath) {
      const res = await getDevice(userId, deviceTokenFromPath);
      return attachUserToResponse(res, userRow, premium);
    }

    if (method === "POST") {
      const body = safeJson(event?.body);

      // ✅ Default iOS environment to production (TestFlight-safe)
      if (String(body?.platform ?? "ios").toLowerCase() === "ios") {
        body.environment = String(body?.environment ?? "production").toLowerCase();
      }

      const res = await registerDevice(userId, body);
      return attachUserToResponse(res, userRow, premium);
    }

    if (method === "PUT" && deviceTokenFromPath) {
      const body = safeJson(event?.body);
      const res = await updateDevice(userId, deviceTokenFromPath, body);
      return attachUserToResponse(res, userRow, premium);
    }

    if (method === "DELETE" && deviceTokenFromPath) {
      const res = await deleteDevice(userId, deviceTokenFromPath);
      return attachUserToResponse(res, userRow, premium);
    }

    return json(400, { message: "Unsupported route or method" });
  } catch (err) {
    console.error("CashSense-RegisterDevice error:", err);
    return json(500, { message: "Internal server error", detail: safeErr(err) });
  }
};

// --------------------
// Premium helper
// --------------------
function computePremiumFromUser(user) { return resolve(user || {}); }

function attachUserToResponse(lambdaResponse, userRow, premium) {
  let parsed = {};
  try {
    parsed = JSON.parse(lambdaResponse?.body || "{}");
  } catch {
    parsed = {};
  }

  parsed.user = {
    userId: userRow?.userId,
    email: userRow?.email ?? null,
    tier: premium.tier,
    isPremium: premium.isPremium,
    premiumUntil: premium.premiumUntil,
    premiumSource: premium.premiumSource,
    devOverride: premium.devOverride,
  };

  return { ...lambdaResponse, body: JSON.stringify(parsed) };
}

// --------------------
// Users helpers
// --------------------
function getClaims(event) {
  return (
    event?.requestContext?.authorizer?.jwt?.claims ||
    event?.requestContext?.authorizer?.claims ||
    null
  );
}

// ✅ JWT sub only (prevents userId drift)
function getUserIdFromClaims(claims) {
  return claims?.sub ? String(claims.sub) : null;
}

function normalizeEmail(raw) {
  if (raw === undefined || raw === null) return null;
  const s = String(raw).trim().toLowerCase();
  return s.includes("@") ? s : null;
}

async function ensureUserExists(userId, claims) {
  const email =
    normalizeEmail(claims?.email) ||
    normalizeEmail(claims?.["cognito:email"]) ||
    normalizeEmail(claims?.["custom:email"]);

  console.log("ensureUserExists()", {
    table: USERS_TABLE,
    userId,
    emailPresent: !!email,
  });

  const existing = await ddb.send(
    new GetCommand({
      TableName: USERS_TABLE,
      Key: { userId }, ConsistentRead: true,
    })
  );

  if (existing.Item) {
    const needsEmailBackfill = !existing.Item.email && !!email;

    const needsDefaults =
      existing.Item.tier === undefined ||
      existing.Item.premiumUntil === undefined ||
      existing.Item.premiumSource === undefined ||
      existing.Item.devOverride === undefined;

    if (needsEmailBackfill || needsDefaults) {
      const exprNames = { "#updatedAt": "updatedAt" };
      const exprValues = { ":updatedAt": new Date().toISOString() };
      const sets = ["#updatedAt = :updatedAt"];

      if (needsEmailBackfill) {
        exprNames["#email"] = "email";
        exprValues[":email"] = email;
        sets.push("#email = :email");
      }

      if (existing.Item.tier === undefined) {
        exprNames["#tier"] = "tier";
        exprValues[":tier"] = "free";
        sets.push("#tier = :tier");
      }

      if (existing.Item.premiumUntil === undefined) {
        exprNames["#premiumUntil"] = "premiumUntil";
        exprValues[":premiumUntil"] = 0;
        sets.push("#premiumUntil = :premiumUntil");
      }

      if (existing.Item.premiumSource === undefined) {
        exprNames["#premiumSource"] = "premiumSource";
        exprValues[":premiumSource"] = "none";
        sets.push("#premiumSource = :premiumSource");
      }

      if (existing.Item.devOverride === undefined) {
        exprNames["#devOverride"] = "devOverride";
        exprValues[":devOverride"] = false;
        sets.push("#devOverride = :devOverride");
      }

      const updated = await ddb.send(
        new UpdateCommand({
          TableName: USERS_TABLE,
          Key: { userId },
          UpdateExpression: `SET ${sets.join(", ")}`,
          ExpressionAttributeNames: exprNames,
          ExpressionAttributeValues: exprValues,
          ReturnValues: "ALL_NEW",
        })
      );

      return updated.Attributes ?? existing.Item;
    }

    return existing.Item;
  }

  const nowIso = new Date().toISOString();
  const item = {
    userId,
    email: email || undefined,
    tier: "free",
    premiumUntil: 0,
    premiumSource: "none",
    devOverride: false,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  await ddb.send(
    new PutCommand({
      TableName: USERS_TABLE,
      Item: item,
      ConditionExpression: "attribute_not_exists(userId)",
    })
  );

  console.log("Created user row in CashSense-Users", { userId });
  return item;
}

// --------------------
// DynamoDB operations (DeviceRegistry)
// --------------------
async function listDevices(userId) {
  const result = await ddb.send(
    new QueryCommand({
      TableName: DEVICE_REGISTRY_TABLE,
      KeyConditionExpression: "userId = :uid",
      ExpressionAttributeValues: { ":uid": userId },
    })
  );
  return json(200, { items: result.Items ?? [] });
}

async function getDevice(userId, deviceToken) {
  const result = await ddb.send(
    new GetCommand({
      TableName: DEVICE_REGISTRY_TABLE,
      Key: { userId, deviceToken },
    })
  );
  if (!result.Item) return json(404, { message: "Device not found" });
  return json(200, result.Item);
}

async function registerDevice(userId, body) {
  if (!body?.deviceToken) {
    return json(400, { message: "deviceToken is required" });
  }

  const now = new Date().toISOString();

  const platform = String(body?.platform ?? "unknown").toLowerCase();

  // ✅ default iOS environment to production
  const environment =
    platform === "ios"
      ? String(body?.environment ?? "production").toLowerCase()
      : String(body?.environment ?? "").toLowerCase();

  const notificationsEnabled =
    body?.notificationsEnabled === undefined ? true : !!body.notificationsEnabled;

  const deviceId = body?.deviceId ? String(body.deviceId) : null;

  const tokenValidation = validateDeviceToken({
    platform,
    deviceToken: body.deviceToken,
  });
  if (!tokenValidation.ok) return json(400, { message: tokenValidation.message });

  const existing = await ddb.send(
    new GetCommand({
      TableName: DEVICE_REGISTRY_TABLE,
      Key: { userId, deviceToken: body.deviceToken },
    })
  );

  if (deviceId) {
    await cleanupOldDeviceTokensForSameDeviceId({
      userId,
      deviceId,
      keepDeviceToken: body.deviceToken,
    });
  }

  let snsEndpointArn = existing?.Item?.snsEndpointArn ?? null;

  if (platform === "ios" || platform === "android") {
    const platformAppArn = resolvePlatformAppArn(platform, environment);
    if (!platformAppArn) {
      return json(500, {
        message:
          platform === "ios"
            ? "Missing SNS platform application ARN for iOS. Set SNS_PLATFORM_APPLICATION_ARN_IOS (and optionally SNS_PLATFORM_APPLICATION_ARN_IOS_SANDBOX)."
            : "Missing SNS platform application ARN for Android. Set SNS_PLATFORM_APPLICATION_ARN_ANDROID.",
      });
    }

    try {
      snsEndpointArn = await ensureSnsEndpoint({
        platformApplicationArn: platformAppArn,
        deviceToken: body.deviceToken,
        existingEndpointArn: snsEndpointArn,
        userId,
        notificationsEnabled,
      });
    } catch (e) {
      console.error("SNS endpoint ensure failed:", safeErr(e));
      return json(502, {
        message: "Failed to create/validate SNS endpoint",
        detail: safeErr(e),
      });
    }
  }

  const item = {
    userId,
    deviceToken: body.deviceToken,
    deviceId,
    platform,
    environment: platform === "ios" ? environment : undefined,
    appVersion: body?.appVersion ?? undefined,
    osVersion: body?.osVersion ?? undefined,
    snsEndpointArn,
    notificationsEnabled,
    badgeCount: 0,
    timeZone: body?.timeZone ?? undefined,
    lastSeenAt: now,
    createdAt: existing?.Item?.createdAt ?? now,
    updatedAt: now,
  };

  await ddb.send(new PutCommand({ TableName: DEVICE_REGISTRY_TABLE, Item: item }));

  return json(201, item);
}

async function updateDevice(userId, deviceToken, body) {
  const allowed = [
    "platform",
    "environment",
    "appVersion",
    "osVersion",
    "notificationsEnabled",
    "timeZone",
    "lastSeenAt",
    "deviceId",
    "badgeCount",
  ];

  const updates = Object.fromEntries(
    Object.entries(body ?? {}).filter(([k]) => allowed.includes(k))
  );

  if (updates.badgeCount !== undefined) {
    const badgeCount = Number(updates.badgeCount);
    if (!Number.isInteger(badgeCount) || badgeCount < 0) {
      return json(400, { message: "badgeCount must be a non-negative integer" });
    }
    updates.badgeCount = badgeCount;
  }

  if (Object.keys(updates).length === 0) {
    return json(400, { message: "No valid fields to update" });
  }

  const existing = await ddb.send(
    new GetCommand({
      TableName: DEVICE_REGISTRY_TABLE,
      Key: { userId, deviceToken },
    })
  );
  if (!existing.Item) return json(404, { message: "Device not found" });

  const platform = String(
    updates.platform ?? existing.Item.platform ?? "unknown"
  ).toLowerCase();

  const environment =
    platform === "ios"
      ? String(updates.environment ?? existing.Item.environment ?? "production").toLowerCase()
      : String(updates.environment ?? existing.Item.environment ?? "").toLowerCase();

  const notificationsEnabled =
    updates.notificationsEnabled === undefined
      ? existing.Item.notificationsEnabled ?? true
      : !!updates.notificationsEnabled;

  const deviceId = updates.deviceId
    ? String(updates.deviceId)
    : existing.Item.deviceId ?? null;

  const tokenValidation = validateDeviceToken({ platform, deviceToken });
  if (!tokenValidation.ok) return json(400, { message: tokenValidation.message });

  let snsEndpointArn = existing.Item.snsEndpointArn ?? null;

  if (platform === "ios" || platform === "android") {
    const platformAppArn = resolvePlatformAppArn(platform, environment);
    if (!platformAppArn) {
      return json(500, {
        message:
          platform === "ios"
            ? "Missing SNS platform application ARN for iOS. Set SNS_PLATFORM_APPLICATION_ARN_IOS (and optionally SNS_PLATFORM_APPLICATION_ARN_IOS_SANDBOX)."
            : "Missing SNS platform application ARN for Android. Set SNS_PLATFORM_APPLICATION_ARN_ANDROID.",
      });
    }

    try {
      snsEndpointArn = await ensureSnsEndpoint({
        platformApplicationArn: platformAppArn,
        deviceToken,
        existingEndpointArn: snsEndpointArn,
        userId,
        notificationsEnabled,
      });
    } catch (e) {
      console.error("SNS endpoint ensure/set attributes failed:", safeErr(e));
      return json(502, {
        message: "Failed to update SNS endpoint attributes",
        detail: safeErr(e),
      });
    }
  }

  const names = {};
  const values = {};
  const sets = [];

  const merged = {
    ...updates,
    deviceId,
    platform,
    environment: platform === "ios" ? environment : undefined,
    notificationsEnabled,
    snsEndpointArn,
    lastSeenAt: updates.lastSeenAt ?? new Date().toISOString(),
  };

  for (const [k, v] of Object.entries(merged)) {
    names[`#${k}`] = k;
    values[`:${k}`] = v;
    sets.push(`#${k} = :${k}`);
  }

  names["#updatedAt"] = "updatedAt";
  values[":updatedAt"] = new Date().toISOString();
  sets.push("#updatedAt = :updatedAt");

  const result = await ddb.send(
    new UpdateCommand({
      TableName: DEVICE_REGISTRY_TABLE,
      Key: { userId, deviceToken },
      UpdateExpression: `SET ${sets.join(", ")}`,
      ExpressionAttributeNames: names,
      ExpressionAttributeValues: values,
      ReturnValues: "ALL_NEW",
    })
  );

  return json(200, result.Attributes);
}

async function deleteDevice(userId, deviceToken) {
  const existing = await ddb.send(
    new GetCommand({
      TableName: DEVICE_REGISTRY_TABLE,
      Key: { userId, deviceToken },
    })
  );

  const endpointArn = existing?.Item?.snsEndpointArn ?? null;

  await ddb.send(
    new DeleteCommand({
      TableName: DEVICE_REGISTRY_TABLE,
      Key: { userId, deviceToken },
    })
  );

  if (endpointArn) await bestEffortDisableAndDeleteEndpoint(endpointArn);

  return json(200, { message: "Device removed", userId, deviceToken });
}

// --------------------
// SNS helpers
// --------------------
function resolvePlatformAppArn(platform, environment) {
  if (platform === "ios") {
    if (environment === "sandbox") return SNS_PLATFORM_APPLICATION_ARN_IOS_SANDBOX || "";
    return SNS_PLATFORM_APPLICATION_ARN_IOS || "";
  }
  if (platform === "android") return SNS_PLATFORM_APPLICATION_ARN_ANDROID || "";
  return "";
}

async function ensureSnsEndpoint({
  platformApplicationArn,
  deviceToken,
  existingEndpointArn,
  userId,
  notificationsEnabled = true,
}) {
  if (!platformApplicationArn) {
    throw new Error("Missing platformApplicationArn");
  }

  if (existingEndpointArn) {
    try {
      const attrs = await sns.send(
        new GetEndpointAttributesCommand({ EndpointArn: existingEndpointArn })
      );

      const currentToken = attrs?.Attributes?.Token;
      const enabled = attrs?.Attributes?.Enabled;

      if (currentToken === deviceToken) {
        const shouldBeEnabled = notificationsEnabled ? "true" : "false";
        if (enabled !== shouldBeEnabled) {
          await sns.send(
            new SetEndpointAttributesCommand({
              EndpointArn: existingEndpointArn,
              Attributes: { Token: deviceToken, Enabled: shouldBeEnabled },
            })
          );
        }
        return existingEndpointArn;
      }

      await sns.send(
        new SetEndpointAttributesCommand({
          EndpointArn: existingEndpointArn,
          Attributes: {
            Token: deviceToken,
            Enabled: notificationsEnabled ? "true" : "false",
          },
        })
      );
      return existingEndpointArn;
    } catch (e) {
      console.warn("Existing endpoint invalid, creating new one:", safeErr(e));
    }
  }

  try {
    const createRes = await sns.send(
      new CreatePlatformEndpointCommand({
        PlatformApplicationArn: platformApplicationArn,
        Token: deviceToken,
        CustomUserData: String(userId),
      })
    );

    const endpointArn = createRes.EndpointArn ?? null;

    if (endpointArn) {
      await sns.send(
        new SetEndpointAttributesCommand({
          EndpointArn: endpointArn,
          Attributes: {
            Token: deviceToken,
            Enabled: notificationsEnabled ? "true" : "false",
          },
        })
      );
    }

    return endpointArn;
  } catch (e) {
    const recoveredArn = extractEndpointArnFromErrorMessage(e?.message);
    if (!recoveredArn) throw e;

    await sns.send(
      new SetEndpointAttributesCommand({
        EndpointArn: recoveredArn,
        Attributes: {
          Token: deviceToken,
          Enabled: notificationsEnabled ? "true" : "false",
        },
      })
    );

    return recoveredArn;
  }
}

async function bestEffortDisableAndDeleteEndpoint(endpointArn) {
  try {
    await sns.send(
      new SetEndpointAttributesCommand({
        EndpointArn: endpointArn,
        Attributes: { Enabled: "false" },
      })
    );
  } catch (_) {}

  try {
    await sns.send(new DeleteEndpointCommand({ EndpointArn: endpointArn }));
  } catch (_) {}
}

// --------------------
// Cleanup old endpoints/items for same deviceId
// --------------------
async function cleanupOldDeviceTokensForSameDeviceId({
  userId,
  deviceId,
  keepDeviceToken,
}) {
  let items = [];
  try {
    const res = await ddb.send(
      new QueryCommand({
        TableName: DEVICE_REGISTRY_TABLE,
        KeyConditionExpression: "userId = :uid",
        ExpressionAttributeValues: { ":uid": userId },
      })
    );
    items = res.Items ?? [];
  } catch (e) {
    console.warn("cleanup query failed:", safeErr(e));
    return;
  }

  const stale = items.filter(
    (it) =>
      it?.deviceId &&
      String(it.deviceId) === String(deviceId) &&
      String(it.deviceToken) !== String(keepDeviceToken)
  );

  for (const oldItem of stale) {
    const oldEndpointArn = oldItem?.snsEndpointArn ?? null;
    const oldToken = oldItem?.deviceToken;

    if (oldEndpointArn) await bestEffortDisableAndDeleteEndpoint(oldEndpointArn);

    try {
      await ddb.send(
        new DeleteCommand({
          TableName: DEVICE_REGISTRY_TABLE,
          Key: { userId, deviceToken: oldToken },
        })
      );
    } catch (e) {
      console.warn("Failed to delete stale device row:", safeErr(e));
    }
  }
}

// --------------------
// Token validation
// --------------------
function validateDeviceToken({ platform, deviceToken }) {
  const token = String(deviceToken ?? "").trim();
  if (!token) return { ok: false, message: "deviceToken is required" };

  if (platform === "ios") {
    const hexOnly = /^[0-9a-fA-F]+$/.test(token);
    if (!hexOnly) {
      return {
        ok: false,
        message: "Invalid iOS token: must be hex (APNS token), not FCM.",
      };
    }
    if (token.length < 50) {
      return {
        ok: false,
        message: "Invalid iOS token: too short to be an APNS token.",
      };
    }
  }

  if (platform === "android") {
    if (token.length < 20) {
      return { ok: false, message: "Invalid Android token: too short." };
    }
  }

  return { ok: true };
}

function extractEndpointArnFromErrorMessage(msg) {
  if (!msg) return null;
  const s = String(msg);
  const m = s.match(
    /(arn:aws:sns:[a-z0-9-]+:\d{12}:endpoint\/[A-Z0-9_]+\/[^\/]+\/[a-f0-9-]+)/i
  );
  return m ? m[1] : null;
}

// --------------------
// Helpers
// --------------------
function normalizePath(event) {
  const stage = event?.requestContext?.stage;
  const raw = event?.rawPath || event?.path || "/";
  if (stage && raw.startsWith(`/${stage}/`)) return raw.slice(stage.length + 1);
  if (stage && raw === `/${stage}`) return "/";
  return raw;
}

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

function extractIdFromPath(path, resource) {
  const parts = String(path).split("/").filter(Boolean);
  if (parts[0] !== resource) return null;
  return parts[1] ?? null;
}

function safeErr(e) {
  return {
    name: e?.name,
    message: e?.message,
    code: e?.code,
    $metadata: e?.$metadata,
  };
}
