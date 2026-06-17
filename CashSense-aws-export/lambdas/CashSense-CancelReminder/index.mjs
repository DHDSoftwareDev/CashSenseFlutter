import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  DeleteCommand
} from "@aws-sdk/lib-dynamodb";
import {
  EventBridgeClient,
  RemoveTargetsCommand,
  DeleteRuleCommand
} from "@aws-sdk/client-eventbridge";
import { LambdaClient, RemovePermissionCommand } from "@aws-sdk/client-lambda";

const NOTIFICATION_SCHEDULES_TABLE =
  process.env.NOTIFICATION_SCHEDULES_TABLE ?? "CashSense-NotificationSchedules";

const ddbClient = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(ddbClient, {
  marshallOptions: { removeUndefinedValues: true }
});

const eb = new EventBridgeClient({});
const lambda = new LambdaClient({});

export const handler = async (event) => {
  try {
    const path = normalizePath(event);

    const scheduleId =
      event?.scheduleId ||
      event?.pathParameters?.scheduleId ||
      extractIdFromPath(path, "schedules") ||
      extractIdFromPath(path, "cancel-reminder") ||
      event?.queryStringParameters?.scheduleId ||
      safeJson(event?.body)?.scheduleId;

    if (!scheduleId) {
      return json(400, { message: "scheduleId is required" });
    }

    const userId = getUserId(event);
    const isApiCall = Boolean(event?.requestContext);

    const scheduleRes = await ddb.send(
      new GetCommand({
        TableName: NOTIFICATION_SCHEDULES_TABLE,
        Key: { scheduleId }
      })
    );

    if (!scheduleRes.Item) {
      return json(404, { message: "Schedule not found", scheduleId });
    }

    if (isApiCall) {
      if (!userId) return json(401, { message: "Unauthorized" });
      if (scheduleRes.Item.userId !== userId)
        return json(403, { message: "Forbidden" });
    }

    await ddb.send(
      new DeleteCommand({
        TableName: NOTIFICATION_SCHEDULES_TABLE,
        Key: { scheduleId }
      })
    );

    await cleanupEventBridge(scheduleId);

    const dispatchLambdaArn = event?.dispatchLambdaArn || process.env.DISPATCH_LAMBDA_ARN;
    if (dispatchLambdaArn) {
      await removeInvokePermissionBestEffort(scheduleId, dispatchLambdaArn);
    } else {
      console.log("No dispatchLambdaArn provided; skipping RemovePermission.");
    }

    return json(200, { message: "Reminder canceled", scheduleId });
  } catch (err) {
    console.error("CashSense-CancelReminder error:", err);
    return json(500, { message: "Internal server error" });
  }
};

// --------------------
// EventBridge cleanup
// --------------------

function ruleNameFor(scheduleId) {
  const trimmed = scheduleId.length > 50 ? scheduleId.slice(0, 50) : scheduleId;
  return {
    notificationSchedulesRule: `CashSenseSchedule-${scheduleId}`,
    billReminderRule: `CashSenseBill-${trimmed}`
  };
}

function targetIdFor(scheduleId) {
  return `Target-${scheduleId}`;
}

async function cleanupEventBridge(scheduleId) {
  const { notificationSchedulesRule, billReminderRule } = ruleNameFor(scheduleId);
  const targetId = targetIdFor(scheduleId);

  await removeTargetAndDeleteRuleBestEffort(notificationSchedulesRule, targetId);
  await removeTargetAndDeleteRuleBestEffort(billReminderRule, targetId);
}

async function removeTargetAndDeleteRuleBestEffort(ruleName, targetId) {
  try {
    await eb.send(new RemoveTargetsCommand({ Rule: ruleName, Ids: [targetId] }));
  } catch (e) {
    console.log(`RemoveTargets ignored for rule ${ruleName}:`, e?.name || e);
  }

  try {
    await eb.send(new DeleteRuleCommand({ Name: ruleName }));
  } catch (e) {
    console.log(`DeleteRule ignored for rule ${ruleName}:`, e?.name || e);
  }
}

async function removeInvokePermissionBestEffort(scheduleId, dispatchLambdaArn) {
  const statementId = `AllowEventBridgeInvoke-${scheduleId}`;
  try {
    await lambda.send(
      new RemovePermissionCommand({
        FunctionName: dispatchLambdaArn,
        StatementId: statementId
      })
    );
  } catch (e) {
    console.log("RemovePermission ignored:", e?.name || e);
  }
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

function getUserId(event) {
  const claims =
    event?.requestContext?.authorizer?.jwt?.claims ||
    event?.requestContext?.authorizer?.claims;

  if (claims?.sub) return String(claims.sub);

  const headerUser =
    event?.headers?.["x-user-id"] || event?.headers?.["X-User-Id"];
  if (headerUser) return String(headerUser);

  return null;
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

function extractIdFromPath(path, resource) {
  const parts = String(path).split("/").filter(Boolean);
  if (parts[0] !== resource) return null;
  return parts[1] ?? null;
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  };
}
