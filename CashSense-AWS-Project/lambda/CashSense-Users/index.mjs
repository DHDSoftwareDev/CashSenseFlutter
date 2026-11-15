import { resolve as resolveEntitlements } from './entitlements.mjs';
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
        Key: { userId }, ConsistentRead:true,
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

      try { await ddb.send(
        new PutCommand({
          TableName: USERS_TABLE,
          Item: user,
          ConditionExpression: "attribute_not_exists(userId)",
        })
      ); } catch(e) { if(e.name!=="ConditionalCheckFailedException") throw e; user=(await ddb.send(new GetCommand({TableName:USERS_TABLE,Key:{userId},ConsistentRead:true}))).Item; }
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
