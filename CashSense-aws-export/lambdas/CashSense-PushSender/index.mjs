// CashSense-PushSender
// Sends APNs notifications to iOS endpoints registered in DeviceRegistry.
//
// ✅ Updated:
// - Builds richer title/body from event.data when caller doesn't provide them
// - Supports billName + amount + dueDate + optional note
// - Keeps caller-provided title/body if present

import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  QueryCommand,
} from "@aws-sdk/lib-dynamodb";
import {
  SNSClient,
  PublishCommand /*, GetEndpointAttributesCommand */,
} from "@aws-sdk/client-sns";

const DEVICE_REGISTRY_TABLE =
  process.env.DEVICE_REGISTRY_TABLE ?? "CashSense-DeviceRegistry";
const BILLS_TABLE = process.env.BILLS_TABLE ?? "CashSense-Bills";

// Must exactly match your iOS bundle id (APNs topic)
const IOS_BUNDLE_ID = process.env.IOS_BUNDLE_ID ?? "";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});
const sns = new SNSClient({});

export const handler = async (event) => {
  console.log("PushSender invoked", {
    scheduleId: event?.scheduleId,
    userId: event?.userId,
    timeZone: event?.timeZone,
    runAt: event?.runAt,
    environment: event?.environment,
    mode: event?.mode ?? "alert",
    hasTitle: Boolean(event?.title),
    hasBody: Boolean(event?.body),
    dataKeys: event?.data && typeof event.data === "object" ? Object.keys(event.data) : [],
  });

  if (!IOS_BUNDLE_ID) {
    console.error("Missing IOS_BUNDLE_ID env var (APNs topic).");
    return { ok: false, message: "Missing IOS_BUNDLE_ID env var (APNs topic)" };
  }

  const userId = String(event?.userId ?? "").trim();
  if (!userId) return { ok: false, message: "Missing userId" };

  const data =
    event?.data && typeof event.data === "object" ? event.data : {};

  const reminderGuard = await shouldSendBillReminder(userId, data);
  if (!reminderGuard.ok) {
    console.log("Skipping bill reminder", reminderGuard);
    return reminderGuard;
  }

  // Load devices for user
  const res = await ddb.send(
    new QueryCommand({
      TableName: DEVICE_REGISTRY_TABLE,
      KeyConditionExpression: "userId = :uid",
      ExpressionAttributeValues: { ":uid": userId },
    })
  );

  const devices = res.Items ?? [];
  const requestedEnvironment = normalizeNonEmptyString(
    event?.environment || event?.data?.environment
  ).toLowerCase();

  const enabled = devices.filter((d) => {
    const notificationsEnabled =
      d?.notificationsEnabled === undefined ? true : Boolean(d.notificationsEnabled);
    const platform = String(d?.platform ?? "").toLowerCase();
    const environment = String(d?.environment ?? "production").toLowerCase();
    const endpointArn = String(d?.snsEndpointArn ?? "");

    const isIos = platform === "ios";
    const isSupportedEnvironment =
      environment === "production" || environment === "sandbox";
    const hasCashSenseApnsEndpoint =
      endpointArn.includes(":endpoint/APNS/") ||
      endpointArn.includes(":endpoint/APNS_SANDBOX/");

    return (
      notificationsEnabled &&
      isIos &&
      isSupportedEnvironment &&
      hasCashSenseApnsEndpoint
    );
  });

  const matchingEnvironment =
    requestedEnvironment === "production" || requestedEnvironment === "sandbox"
      ? enabled.filter(
          (d) =>
            String(d?.environment ?? "production").toLowerCase() ===
            requestedEnvironment
        )
      : [];
  const deliveryTargets = matchingEnvironment.length ? matchingEnvironment : enabled;

  console.log(
    "Devices",
    {
      total: devices.length,
      enabledWithEndpoint: enabled.length,
      requestedEnvironment: requestedEnvironment || null,
      deliveryTargets: deliveryTargets.length,
      enabledEndpoints: enabled.map((d) => ({
        environment: d?.environment ?? "production",
        endpointArn: d?.snsEndpointArn ?? null,
      })),
    }
  );

  if (deliveryTargets.length === 0) {
    return { ok: false, message: "No enabled endpoints for user" };
  }

  // alert = banner/lock-screen
  // background = silent
  const mode = String(event?.mode ?? "alert"); // "background" | "alert"

  // ---- Title/body (caller overrides; otherwise build from data) ----
  const callerTitle = normalizeNonEmptyString(event?.title);
  const callerBody = normalizeNonEmptyString(event?.body);
  const built = buildTitleBodyFromData(data);

  const title = callerTitle || built.title || "CashSense";
  const body = callerBody || built.body || "Reminder";

  // Badge:
  const badge =
    Number.isFinite(Number(data?.badge)) ? Number(data.badge) : 1;

  const results = [];

  for (const d of deliveryTargets) {
    const endpointArn = String(d.snsEndpointArn);
    const platform = String(d?.platform ?? "unknown").toLowerCase();

    if (platform !== "ios") continue;

    const apnsPayload =
      mode === "alert"
        ? {
            aps: {
              alert: { title, body },
              sound: "default",
              badge,
              "interruption-level": "active",
            },
            ...data,
          }
        : {
            aps: { "content-available": 1 },
            ...data,
          };

    const message = {
      default: body,
      APNS: JSON.stringify(apnsPayload),
      APNS_SANDBOX: JSON.stringify(apnsPayload),
    };

    const msgAttrs =
      mode === "alert"
        ? {
            "AWS.SNS.MOBILE.APNS.PUSH_TYPE": { DataType: "String", StringValue: "alert" },
            "AWS.SNS.MOBILE.APNS.PRIORITY": { DataType: "String", StringValue: "10" },
            "AWS.SNS.MOBILE.APNS.TOPIC": { DataType: "String", StringValue: IOS_BUNDLE_ID },
          }
        : {
            "AWS.SNS.MOBILE.APNS.PUSH_TYPE": { DataType: "String", StringValue: "background" },
            "AWS.SNS.MOBILE.APNS.PRIORITY": { DataType: "String", StringValue: "5" },
            "AWS.SNS.MOBILE.APNS.TOPIC": { DataType: "String", StringValue: IOS_BUNDLE_ID },
          };

    console.log("Publishing", {
      endpointArn,
      mode,
      topic: IOS_BUNDLE_ID,
      title,
      body,
      dataKeys: Object.keys(data || {}),
    });

    try {
      const out = await sns.send(
        new PublishCommand({
          TargetArn: endpointArn,
          MessageStructure: "json",
          Message: JSON.stringify(message),
          MessageAttributes: msgAttrs,
        })
      );

      console.log("Publish succeeded", {
        endpointArn,
        mode,
        messageId: out.MessageId,
      });
      results.push({ ok: true, endpointArn, messageId: out.MessageId, mode });
    } catch (e) {
      console.error("Publish FAILED", {
        endpointArn,
        mode,
        name: e?.name,
        message: e?.message,
        $metadata: e?.$metadata,
      });
      results.push({ ok: false, endpointArn, mode, error: e?.message });
    }
  }

  return { ok: true, results };
};

// --------------------
// Helpers
// --------------------
function normalizeNonEmptyString(v) {
  if (v === undefined || v === null) return "";
  const s = String(v).trim();
  return s.length ? s : "";
}

function formatMoney(amount) {
  const n = Number(amount);
  if (!Number.isFinite(n)) return "";
  return n.toFixed(2);
}

async function shouldSendBillReminder(userId, data) {
  const type = String(data?.type ?? "").toLowerCase();
  if (type !== "bill_reminder") return { ok: true };

  const billId = normalizeNonEmptyString(data?.billId);
  if (!billId) {
    return {
      ok: false,
      skipped: true,
      reason: "missing_bill_id",
      message: "Bill reminder payload is missing billId",
    };
  }

  const result = await ddb.send(
    new GetCommand({
      TableName: BILLS_TABLE,
      Key: { userId, billId },
    })
  );

  const bill = result.Item;
  if (!bill) {
    return {
      ok: false,
      skipped: true,
      reason: "bill_deleted",
      userId,
      billId,
      message: "Bill no longer exists",
    };
  }

  const status = String(bill?.status ?? "").trim().toLowerCase();
  const paymentStatus = String(bill?.paymentStatus ?? "").trim().toLowerCase();
  const isPaid = Boolean(bill?.isPaid) || paymentStatus === "paid";
  const remindersDisabled = bill?.remindersEnabled === false;

  if (status === "deleted" || status === "archived" || status === "inactive") {
    return {
      ok: false,
      skipped: true,
      reason: "bill_inactive",
      userId,
      billId,
      status,
      message: "Bill is no longer active",
    };
  }

  if (isPaid) {
    return {
      ok: false,
      skipped: true,
      reason: "bill_paid",
      userId,
      billId,
      message: "Bill is already paid",
    };
  }

  if (remindersDisabled) {
    return {
      ok: false,
      skipped: true,
      reason: "bill_reminders_disabled",
      userId,
      billId,
      message: "Bill reminders are disabled",
    };
  }

  return { ok: true };
}

function buildTitleBodyFromData(data) {
  try {
    const type = String(data?.type ?? "").toLowerCase();

    const billName = normalizeNonEmptyString(data?.billName || data?.name);
    const dueDate = normalizeNonEmptyString(data?.dueDate || data?.dueOn || data?.date);
    const note = normalizeNonEmptyString(data?.note || data?.notes);

    const amountStr = (() => {
      const formatted = formatMoney(data?.amount);
      if (formatted) return `$${formatted}`;
      const s = normalizeNonEmptyString(data?.amount);
      return s ? (s.startsWith("$") ? s : `$${s}`) : "";
    })();

    // Treat anything that looks like a bill reminder as bill formatting
    if (type === "bill_reminder" || billName || dueDate || amountStr || note) {
      const title = billName
        ? `💸 ${billName}${dueDate ? ` due ${dueDate}` : ""}`
        : "Bill Due";

      const parts = [
        amountStr || null,
        dueDate ? `Due: ${dueDate}` : null,
        note || null,
      ].filter(Boolean);

      const body = parts.join(" • ");
      return { title, body };
    }

    return { title: "", body: "" };
  } catch {
    return { title: "", body: "" };
  }
}
