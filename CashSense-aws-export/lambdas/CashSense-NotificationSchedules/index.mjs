// CashSense-NotificationSchedules
// Creates/lists/deletes EventBridge Scheduler schedules that invoke CashSense-PushSender.
// Runtime: Node.js 24.x ESM

import crypto from "crypto";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  GetCommand,
  DeleteCommand,
  QueryCommand,
} from "@aws-sdk/lib-dynamodb";
import {
  SchedulerClient,
  CreateScheduleCommand,
  DeleteScheduleCommand,
  UpdateScheduleCommand,
} from "@aws-sdk/client-scheduler";

const NOTIFICATION_SCHEDULES_TABLE =
  process.env.NOTIFICATION_SCHEDULES_TABLE ?? "CashSense-NotificationSchedules";

const SCHEDULER_ROLE_ARN = process.env.SCHEDULER_ROLE_ARN;
const PUSH_SENDER_LAMBDA_ARN = process.env.PUSH_SENDER_LAMBDA_ARN;
const SCHEDULE_NAME_PREFIX = process.env.SCHEDULE_NAME_PREFIX ?? "CashSense";

const USER_GSI_NAME =
  process.env.NOTIFICATION_SCHEDULES_USER_GSI ?? "NotificationSchedule";

const DEDUPE_GSI_NAME =
  process.env.NOTIFICATION_SCHEDULES_DEDUPE_GSI ?? "DedupeIndex";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

const scheduler = new SchedulerClient({});

// --------------------
// Handler
// --------------------
export const handler = async (event) => {
  console.log("CashSense-NotificationSchedules invoked", {
    method: event?.requestContext?.http?.method || event?.httpMethod,
    rawPath: event?.rawPath || event?.path,
    stage: event?.requestContext?.stage,
    hasBody: Boolean(event?.body),
    hasJwt: Boolean(
      event?.requestContext?.authorizer?.jwt?.claims ||
        event?.requestContext?.authorizer?.claims
    ),
    sub:
      event?.requestContext?.authorizer?.jwt?.claims?.sub ||
      event?.requestContext?.authorizer?.claims?.sub,
  });

  try {
    const userId = getUserId(event);
    if (!userId) return json(401, { ok: false, message: "Unauthorized" });

    const method = (
      event?.requestContext?.http?.method ||
      event?.httpMethod ||
      ""
    ).toUpperCase();

    const path = normalizePath(event);
    const params = event?.pathParameters || {};

    if (!path.startsWith("/notification-schedules")) {
      return json(404, { ok: false, message: "Not Found" });
    }

    const byBillId =
      params.billId ||
      extractByBillIdFromPath(path);

    if (method === "DELETE" && byBillId) {
      console.log("Deleting schedules by bill", {
        userId,
        billId: byBillId,
      });

      return await deleteSchedulesByBill(userId, byBillId);
    }

    const scheduleId =
      params.scheduleId || extractIdFromPath(path, "notification-schedules");

    if (method === "GET" && !scheduleId) {
      const qs = event?.queryStringParameters || {};
      return await listSchedules(userId, qs);
    }

    if (method === "DELETE" && !scheduleId) {
      const qs = event?.queryStringParameters || {};
      if (String(qs?.all ?? "").toLowerCase() === "true") {
        console.log("Deleting all schedules for user", { userId });
        return await deleteAllSchedulesForUser(userId);
      }
    }

    if (method === "POST") {
      const body = safeJson(event?.body);

      console.log("Creating schedule request", {
        userId,
        keys: Object.keys(body || {}),
        runAt: body?.runAt,
        runAtLocal: body?.runAtLocal,
        timeZone: body?.timeZone,
        mode: body?.mode,
        dedupeKey: body?.dedupeKey,
        overwriteIfChanged: Boolean(body?.overwriteIfChanged),
      });

      return await createSchedule(userId, body);
    }

    if (method === "DELETE" && scheduleId) {
      console.log("Deleting schedule", { userId, scheduleId });
      return await deleteSchedule(userId, scheduleId);
    }

    return json(400, { ok: false, message: "Unsupported route or method" });
  } catch (err) {
    console.error("CashSense-NotificationSchedules error:", err);
    return json(500, {
      ok: false,
      message: "Internal server error",
      error: err?.message,
    });
  }
};

// --------------------
// Create schedule
// --------------------
async function createSchedule(userId, body) {
  if (!SCHEDULER_ROLE_ARN) {
    return json(500, {
      ok: false,
      message: "Missing SCHEDULER_ROLE_ARN env var.",
    });
  }

  if (!PUSH_SENDER_LAMBDA_ARN) {
    return json(500, {
      ok: false,
      message: "Missing PUSH_SENDER_LAMBDA_ARN env var.",
    });
  }

  const runAt = normalizeNonEmptyString(body?.runAt);
  const runAtLocal = normalizeNonEmptyString(body?.runAtLocal);

  if (!runAt && !runAtLocal) {
    return json(400, {
      ok: false,
      message: "runAt or runAtLocal is required",
    });
  }

  const requestedTimeZone = String(body?.timeZone || "UTC").trim() || "UTC";

  const atValue = runAtLocal
    ? normalizeLocalAt(runAtLocal)
    : toAtExpressionFromIso(runAt);

  const scheduleTimeZone = runAtLocal ? requestedTimeZone : "UTC";

  if (runAt) {
    const when = new Date(runAt);

    if (Number.isNaN(when.getTime())) {
      return json(400, {
        ok: false,
        message: "runAt must be a valid ISO date string",
      });
    }

    if (when.getTime() < Date.now() - 30_000) {
      return json(400, {
        ok: false,
        message: "runAt must be in the future",
      });
    }
  } else if (!isLocalAtFormat(atValue)) {
    return json(400, {
      ok: false,
      message: "runAtLocal must be YYYY-MM-DDTHH:MM:SS",
    });
  }

  const dedupeKey = normalizeNonEmptyString(body?.dedupeKey);
  const billId = normalizeNonEmptyString(body?.data?.billId);
  const storedRunAt = runAt || runAtLocal;

  const effectiveDedupeKey =
    dedupeKey || (billId ? `${billId}#${storedRunAt}` : undefined);

  const overwriteIfChanged = Boolean(body?.overwriteIfChanged);

  const desiredContent = {
    title: body?.title ?? "CashSense Reminder",
    body: body?.body ?? "Reminder",
    data: body?.data ?? {},
    mode: body?.mode ?? "alert",
    runAt: storedRunAt,
    timeZone: requestedTimeZone,
    environment: normalizeNonEmptyString(body?.environment),
  };

  const desiredHash = contentHash(desiredContent);

  if (effectiveDedupeKey) {
    const existing = await findByDedupeKey(userId, effectiveDedupeKey);

    if (existing) {
      const existingHash =
        normalizeNonEmptyString(existing?.contentHash) ||
        contentHash({
          title: existing?.title,
          body: existing?.body,
          data: existing?.data ?? {},
          mode: existing?.mode ?? "alert",
          runAt: existing?.runAt,
          timeZone: existing?.timeZone,
          environment: existing?.environment,
        });

      if (existingHash === desiredHash) {
        return json(200, {
          ok: true,
          deduped: true,
          changed: false,
          ...existing,
        });
      }

      if (!overwriteIfChanged) {
        return json(200, {
          ok: true,
          deduped: true,
          changed: true,
          ...existing,
        });
      }

      const overwriteResult = await overwriteExistingSchedule({
        userId,
        existing,
        atValue,
        scheduleTimeZone,
        requestedTimeZone,
        storedRunAt,
        desiredContent,
        desiredHash,
      });

      if (overwriteResult?.ok) {
        return json(200, overwriteResult);
      }

      console.warn("Overwrite failed; creating new schedule", overwriteResult);
    }
  }

  const nowIso = new Date().toISOString();
  const scheduleId = crypto.randomUUID();
  const scheduleName = buildScheduleName(scheduleId);

  const invokePayload = {
    userId,
    title: desiredContent.title,
    body: desiredContent.body,
    data: desiredContent.data,
    mode: desiredContent.mode,
    scheduleId,
    runAt: storedRunAt,
    timeZone: requestedTimeZone,
    environment: desiredContent.environment,
  };

  await scheduler.send(
    new CreateScheduleCommand({
      Name: scheduleName,
      GroupName: "default",
      ScheduleExpression: `at(${atValue})`,
      ScheduleExpressionTimezone: scheduleTimeZone,
      FlexibleTimeWindow: { Mode: "OFF" },
      Target: {
        Arn: PUSH_SENDER_LAMBDA_ARN,
        RoleArn: SCHEDULER_ROLE_ARN,
        Input: JSON.stringify(invokePayload),
      },
      ActionAfterCompletion: "DELETE",
      Description: `CashSense schedule ${scheduleId} for user ${userId}`,
    })
  );

  const item = {
    scheduleId,
    userId,
    scheduleName,
    runAt: storedRunAt,
    timeZone: requestedTimeZone,
    scheduleTimeZone,
    title: invokePayload.title,
    body: invokePayload.body,
    data: invokePayload.data,
    mode: invokePayload.mode,
    environment: invokePayload.environment,
    contentHash: desiredHash,
    ...(effectiveDedupeKey ? { dedupeKey: effectiveDedupeKey } : {}),
    status: "scheduled",
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  await ddb.send(
    new PutCommand({
      TableName: NOTIFICATION_SCHEDULES_TABLE,
      Item: item,
    })
  );

  return json(201, {
    ok: true,
    deduped: false,
    ...item,
  });
}

// --------------------
// Overwrite existing schedule
// --------------------
async function overwriteExistingSchedule({
  userId,
  existing,
  atValue,
  scheduleTimeZone,
  requestedTimeZone,
  storedRunAt,
  desiredContent,
  desiredHash,
}) {
  const scheduleId = existing?.scheduleId;
  const scheduleName = existing?.scheduleName;

  if (!scheduleId || !scheduleName) {
    return {
      ok: false,
      message: "Existing schedule missing scheduleId/scheduleName",
    };
  }

  const invokePayload = {
    userId,
    title: desiredContent.title,
    body: desiredContent.body,
    data: desiredContent.data,
    mode: desiredContent.mode,
    scheduleId,
    runAt: storedRunAt,
    timeZone: requestedTimeZone,
    environment: desiredContent.environment,
  };

  try {
    await scheduler.send(
      new UpdateScheduleCommand({
        Name: scheduleName,
        GroupName: "default",
        ScheduleExpression: `at(${atValue})`,
        ScheduleExpressionTimezone: scheduleTimeZone,
        FlexibleTimeWindow: { Mode: "OFF" },
        Target: {
          Arn: PUSH_SENDER_LAMBDA_ARN,
          RoleArn: SCHEDULER_ROLE_ARN,
          Input: JSON.stringify(invokePayload),
        },
        ActionAfterCompletion: "DELETE",
        Description: `CashSense schedule ${scheduleId} for user ${userId}`,
      })
    );
  } catch (e) {
    return {
      ok: false,
      message: "UpdateSchedule failed",
      error: safeErr(e),
    };
  }

  const nowIso = new Date().toISOString();

  const updatedItem = {
    ...existing,
    runAt: storedRunAt,
    timeZone: requestedTimeZone,
    scheduleTimeZone,
    title: invokePayload.title,
    body: invokePayload.body,
    data: invokePayload.data,
    mode: invokePayload.mode,
    environment: invokePayload.environment,
    contentHash: desiredHash,
    status: "scheduled",
    updatedAt: nowIso,
  };

  await ddb.send(
    new PutCommand({
      TableName: NOTIFICATION_SCHEDULES_TABLE,
      Item: updatedItem,
    })
  );

  return {
    ok: true,
    deduped: true,
    changed: true,
    overwritten: true,
    ...updatedItem,
  };
}

// --------------------
// Find by dedupe key
// --------------------
async function findByDedupeKey(userId, dedupeKey) {
  const dk = normalizeNonEmptyString(dedupeKey);
  if (!dk) return null;

  const res = await ddb.send(
    new QueryCommand({
      TableName: NOTIFICATION_SCHEDULES_TABLE,
      IndexName: DEDUPE_GSI_NAME,
      KeyConditionExpression: "userId = :uid AND dedupeKey = :dk",
      ExpressionAttributeValues: {
        ":uid": userId,
        ":dk": dk,
      },
      Limit: 1,
    })
  );

  return (res.Items ?? [])[0] ?? null;
}

// --------------------
// List schedules
// --------------------
async function listSchedules(userId, qs = {}) {
  const limit = clampInt(qs?.limit, 1, 100, 50);
  const status = qs?.status ? String(qs.status) : undefined;

  const exclusiveStartKey = qs?.nextToken
    ? decodeNextToken(qs.nextToken)
    : undefined;

  const result = await ddb.send(
    new QueryCommand({
      TableName: NOTIFICATION_SCHEDULES_TABLE,
      IndexName: USER_GSI_NAME,
      KeyConditionExpression: "userId = :uid",
      ExpressionAttributeValues: {
        ":uid": userId,
      },
      ScanIndexForward: true,
      Limit: limit,
      ExclusiveStartKey: exclusiveStartKey,
    })
  );

  let items = result.Items ?? [];

  if (status) {
    items = items.filter((item) => item?.status === status);
  }

  return json(200, {
    ok: true,
    items,
    nextToken: result.LastEvaluatedKey
      ? encodeNextToken(result.LastEvaluatedKey)
      : null,
  });
}

// --------------------
// Delete one schedule
// --------------------
async function deleteSchedule(userId, scheduleId) {
  const existing = await ddb.send(
    new GetCommand({
      TableName: NOTIFICATION_SCHEDULES_TABLE,
      Key: {
        scheduleId,
      },
    })
  );

  if (!existing.Item) {
    return json(404, {
      ok: false,
      message: "Schedule not found",
    });
  }

  if (existing.Item.userId !== userId) {
    return json(403, {
      ok: false,
      message: "Forbidden",
    });
  }

  await deleteSchedulerAndDbItem(existing.Item);

  return json(200, {
    ok: true,
    message: "Deleted",
    scheduleId,
  });
}

// --------------------
// Delete all schedules for one bill
// --------------------
async function deleteSchedulesByBill(userId, billId) {
  let deleted = 0;
  let scanned = 0;
  let ExclusiveStartKey = undefined;

  do {
    const result = await ddb.send(
      new QueryCommand({
        TableName: NOTIFICATION_SCHEDULES_TABLE,
        IndexName: USER_GSI_NAME,
        KeyConditionExpression: "userId = :uid",
        ExpressionAttributeValues: {
          ":uid": userId,
        },
        ExclusiveStartKey,
      })
    );

    const items = result.Items ?? [];
    scanned += items.length;
    ExclusiveStartKey = result.LastEvaluatedKey;

    const matching = items.filter(
      (item) =>
        item?.userId === userId &&
        item?.data?.billId === billId &&
        item?.status === "scheduled"
    );

    for (const item of matching) {
      await deleteSchedulerAndDbItem(item);
      deleted++;
    }
  } while (ExclusiveStartKey);

  return json(200, {
    ok: true,
    message: "Deleted bill schedules",
    billId,
    scanned,
    deleted,
  });
}

// --------------------
// Delete all schedules for one user
// --------------------
async function deleteAllSchedulesForUser(userId) {
  let deleted = 0;
  let scanned = 0;
  let ExclusiveStartKey = undefined;

  do {
    const result = await ddb.send(
      new QueryCommand({
        TableName: NOTIFICATION_SCHEDULES_TABLE,
        IndexName: USER_GSI_NAME,
        KeyConditionExpression: "userId = :uid",
        ExpressionAttributeValues: {
          ":uid": userId,
        },
        ExclusiveStartKey,
      })
    );

    const items = result.Items ?? [];
    scanned += items.length;
    ExclusiveStartKey = result.LastEvaluatedKey;

    for (const item of items) {
      if (item?.userId !== userId || item?.status !== "scheduled") continue;
      await deleteSchedulerAndDbItem(item);
      deleted++;
    }
  } while (ExclusiveStartKey);

  return json(200, {
    ok: true,
    message: "Deleted user schedules",
    scanned,
    deleted,
  });
}

async function deleteSchedulerAndDbItem(item) {
  if (item?.scheduleName) {
    try {
      await scheduler.send(
        new DeleteScheduleCommand({
          Name: item.scheduleName,
          GroupName: "default",
        })
      );
    } catch (e) {
      console.warn("DeleteSchedule warning:", safeErr(e));
    }
  }

  await ddb.send(
    new DeleteCommand({
      TableName: NOTIFICATION_SCHEDULES_TABLE,
      Key: {
        scheduleId: item.scheduleId,
      },
    })
  );
}

// --------------------
// Helpers
// --------------------
function getUserId(event) {
  const claims =
    event?.requestContext?.authorizer?.jwt?.claims ||
    event?.requestContext?.authorizer?.claims;

  return claims?.sub ? String(claims.sub) : null;
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
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  };
}

function buildScheduleName(scheduleId) {
  return `${SCHEDULE_NAME_PREFIX}-${scheduleId}`
    .replace(/[^a-zA-Z0-9-_]/g, "")
    .slice(0, 64);
}

function normalizeNonEmptyString(value) {
  if (value === undefined || value === null) return undefined;

  const s = String(value).trim();

  return s.length ? s : undefined;
}

function normalizePath(event) {
  const stage = event?.requestContext?.stage;
  const raw = event?.rawPath || event?.path || "/";

  if (stage && raw.startsWith(`/${stage}/`)) {
    return raw.slice(stage.length + 1);
  }

  if (stage && raw === `/${stage}`) {
    return "/";
  }

  return raw;
}

function extractIdFromPath(path, resource) {
  const parts = String(path).split("/").filter(Boolean);

  if (parts[0] !== resource) return null;

  // Prevent treating /notification-schedules/by-bill/{billId}
  // as scheduleId = "by-bill"
  if (parts[1] === "by-bill") return null;

  return parts[1] ?? null;
}

function extractByBillIdFromPath(path) {
  const parts = String(path).split("/").filter(Boolean);

  if (
    parts[0] === "notification-schedules" &&
    parts[1] === "by-bill" &&
    parts[2]
  ) {
    return decodeURIComponent(parts[2]);
  }

  return null;
}

function toAtExpressionFromIso(iso) {
  const d = new Date(iso);

  if (Number.isNaN(d.getTime())) {
    throw new Error("Invalid ISO date");
  }

  const yyyy = d.getUTCFullYear();
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mi = String(d.getUTCMinutes()).padStart(2, "0");
  const ss = String(d.getUTCSeconds()).padStart(2, "0");

  return `${yyyy}-${mm}-${dd}T${hh}:${mi}:${ss}`;
}

function normalizeLocalAt(value) {
  const v = String(value).trim();

  return v.endsWith("Z") ? v.slice(0, -1) : v;
}

function isLocalAtFormat(value) {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(String(value));
}

function clampInt(value, min, max, fallback) {
  const n = Number(value);

  if (!Number.isFinite(n)) return fallback;

  const i = Math.floor(n);

  return Math.min(max, Math.max(min, i));
}

function encodeNextToken(lastEvaluatedKey) {
  return Buffer.from(JSON.stringify(lastEvaluatedKey), "utf8").toString(
    "base64"
  );
}

function decodeNextToken(token) {
  try {
    return JSON.parse(Buffer.from(String(token), "base64").toString("utf8"));
  } catch {
    return undefined;
  }
}

function safeErr(e) {
  return {
    name: e?.name,
    message: e?.message,
    code: e?.code,
    $metadata: e?.$metadata,
  };
}

function stableStringify(obj) {
  const seen = new WeakSet();

  const sorter = (value) => {
    if (!value || typeof value !== "object") return value;

    if (seen.has(value)) return value;

    seen.add(value);

    if (Array.isArray(value)) {
      return value.map(sorter);
    }

    const out = {};

    for (const key of Object.keys(value).sort()) {
      out[key] = sorter(value[key]);
    }

    return out;
  };

  return JSON.stringify(sorter(obj));
}

function contentHash(payload) {
  return crypto
    .createHash("sha256")
    .update(stableStringify(payload))
    .digest("hex");
}
