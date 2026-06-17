import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";

const USERS_TABLE = process.env.USERS_TABLE ?? "CashSense-Users";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type,Authorization",
      "Access-Control-Allow-Methods": "GET,OPTIONS",
      "Cache-Control": "no-store",
    },
    body: JSON.stringify(body),
  };
}

function getNowIso() {
  return new Date().toISOString();
}

function getNowUnix() {
  return Math.floor(Date.now() / 1000);
}

function normalizeEmail(email) {
  return String(email ?? "").trim().toLowerCase();
}

function normalizeString(value, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

function normalizeBool(value) {
  return value === true;
}

function normalizeNumber(value, fallback = 0) {
  const num = Number(value);
  return Number.isFinite(num) ? num : fallback;
}

function getClaim(event, key) {
  return (
    event?.requestContext?.authorizer?.jwt?.claims?.[key] ??
    event?.requestContext?.authorizer?.claims?.[key] ??
    null
  );
}

function getUserIdFromEvent(event) {
  return getClaim(event, "sub") || null;
}

function getEmailFromEvent(event) {
  return getClaim(event, "email") || null;
}

function getNameFromEvent(event) {
  return (
    getClaim(event, "name") ||
    getClaim(event, "given_name") ||
    null
  );
}

function resolveEntitlements(user) {
  const nowUnix = getNowUnix();
  const premiumSource = normalizeString(user?.premiumSource, "").toLowerCase();
  const premiumUntil = normalizeNumber(user?.premiumUntil, 0);
  const trialEndsAt = normalizeNumber(user?.trialEndsAt, 0);
  const tier = normalizeString(user?.tier, "free").toLowerCase();

  const resolved = {
    ...user,
    isPremium: false,
    tier: "free",
    premiumStatus: "inactive",
    premiumSource: user?.premiumSource ?? null,
  };

  if (user?.devOverride === true) {
    resolved.isPremium = true;
    resolved.tier = "premium";
    resolved.premiumStatus = "active";
    resolved.premiumSource = "dev";
    return resolved;
  }

  if (user?.testerOverride === true) {
    resolved.isPremium = true;
    resolved.tier = "premium";
    resolved.premiumStatus = "active";
    resolved.premiumSource = "tester";
    return resolved;
  }

  if (premiumUntil > nowUnix && ["apple", "google"].includes(premiumSource)) {
    resolved.isPremium = true;
    resolved.tier = "premium";
    resolved.premiumStatus = "active";
    return resolved;
  }

  if (trialEndsAt > nowUnix) {
    resolved.isPremium = true;
    resolved.tier = "premium";
    resolved.premiumStatus = "trialing";
    resolved.premiumSource = "trial";
    return resolved;
  }

  if (tier === "premium") {
    resolved.isPremium = true;
    resolved.tier = "premium";
    resolved.premiumStatus = "active";
    return resolved;
  }

  return resolved;
}

function buildUserResponse(user) {
  return {
    userId: normalizeString(user?.userId),
    email: normalizeString(user?.email),
    name: normalizeString(user?.name),
    tier: normalizeString(user?.tier, "free"),
    isPremium: normalizeBool(user?.isPremium),
    premiumStatus: normalizeString(user?.premiumStatus, "inactive"),
    premiumSource: user?.premiumSource ?? null,
    premiumUntil: normalizeNumber(user?.premiumUntil, 0),
    trialEndsAt: normalizeNumber(user?.trialEndsAt, 0),
    devOverride: normalizeBool(user?.devOverride),
    testerOverride: normalizeBool(user?.testerOverride),
    createdAt: user?.createdAt ?? null,
    updatedAt: user?.updatedAt ?? null,
  };
}

export const handler = async (event) => {
  console.log("CashSense-Users invoked", {
    method: event?.requestContext?.http?.method ?? event?.httpMethod,
    rawPath: event?.rawPath,
    hasAuthorizer: !!event?.requestContext?.authorizer,
    hasHeaders: !!event?.headers,
  });

  try {
    const method =
      event?.requestContext?.http?.method ?? event?.httpMethod ?? "GET";

    if (method === "OPTIONS") {
      return jsonResponse(200, { ok: true });
    }

    if (method !== "GET") {
      return jsonResponse(405, {
        error: "Method not allowed",
      });
    }

    const userId = getUserIdFromEvent(event);
    const emailFromEvent = normalizeEmail(getEmailFromEvent(event));
    const nameFromEvent = normalizeString(getNameFromEvent(event));

    if (!userId) {
      return jsonResponse(401, {
        error: "Unauthorized: missing userId",
      });
    }

    const existingResult = await ddb.send(
      new GetCommand({
        TableName: USERS_TABLE,
        Key: { userId },
      })
    );

    let user = existingResult.Item;
    const nowIso = getNowIso();

    if (!user) {
      user = {
        userId,
        email: emailFromEvent,
        name: nameFromEvent,
        tier: "free",
        isPremium: false,
        premiumStatus: "inactive",
        premiumSource: null,
        premiumUntil: 0,
        trialEndsAt: 0,
        devOverride: false,
        testerOverride: false,
        createdAt: nowIso,
        updatedAt: nowIso,
      };

      await ddb.send(
        new PutCommand({
          TableName: USERS_TABLE,
          Item: user,
          ConditionExpression: "attribute_not_exists(userId)",
        })
      );
    } else {
      const updates = [];
      const values = {
        ":updatedAt": nowIso,
      };
      const names = {};

      let shouldUpdateIdentityFields = false;

      if (emailFromEvent && normalizeEmail(user.email) !== emailFromEvent) {
        updates.push("email = :email");
        values[":email"] = emailFromEvent;
        user.email = emailFromEvent;
        shouldUpdateIdentityFields = true;
      }

      if (nameFromEvent && normalizeString(user.name) !== nameFromEvent) {
        updates.push("#name = :name");
        values[":name"] = nameFromEvent;
        names["#name"] = "name";
        user.name = nameFromEvent;
        shouldUpdateIdentityFields = true;
      }

      if (shouldUpdateIdentityFields) {
        updates.push("updatedAt = :updatedAt");

        const updateParams = {
          TableName: USERS_TABLE,
          Key: { userId },
          UpdateExpression: `SET ${updates.join(", ")}`,
          ExpressionAttributeValues: values,
        };

        if (Object.keys(names).length > 0) {
          updateParams.ExpressionAttributeNames = names;
        }

        await ddb.send(new UpdateCommand(updateParams));
        user.updatedAt = nowIso;
      }
    }

    const resolvedUser = resolveEntitlements(user);

    const premiumFieldsChanged =
      normalizeBool(resolvedUser.isPremium) !== normalizeBool(user.isPremium) ||
      normalizeString(resolvedUser.tier, "free") !==
        normalizeString(user.tier, "free") ||
      normalizeString(resolvedUser.premiumStatus, "inactive") !==
        normalizeString(user.premiumStatus, "inactive") ||
      (resolvedUser.premiumSource ?? null) !== (user.premiumSource ?? null);

    if (premiumFieldsChanged) {
      const entitlementUpdatedAt = getNowIso();

      await ddb.send(
        new UpdateCommand({
          TableName: USERS_TABLE,
          Key: { userId },
          UpdateExpression: `
            SET isPremium = :isPremium,
                tier = :tier,
                premiumStatus = :premiumStatus,
                premiumSource = :premiumSource,
                updatedAt = :updatedAt
          `,
          ExpressionAttributeValues: {
            ":isPremium": normalizeBool(resolvedUser.isPremium),
            ":tier": normalizeString(resolvedUser.tier, "free"),
            ":premiumStatus": normalizeString(
              resolvedUser.premiumStatus,
              "inactive"
            ),
            ":premiumSource": resolvedUser.premiumSource ?? null,
            ":updatedAt": entitlementUpdatedAt,
          },
        })
      );

      resolvedUser.updatedAt = entitlementUpdatedAt;
    }

    return jsonResponse(200, {
      ok: true,
      user: buildUserResponse(resolvedUser),
    });
  } catch (error) {
    console.error("CashSense-Users error", error);

    return jsonResponse(500, {
      error: "Internal server error",
      message: error instanceof Error ? error.message : String(error),
    });
  }
};
