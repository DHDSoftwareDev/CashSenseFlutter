const json = (statusCode, body) => ({
  statusCode,
  headers: {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "OPTIONS,POST",
  },
  body: JSON.stringify(body),
});

export const handler = async (event = {}) => {
  const method =
    event?.requestContext?.http?.method ||
    event?.httpMethod ||
    "POST";

  if (String(method).toUpperCase() === "OPTIONS") {
    return json(200, { ok: true });
  }

  return json(410, {
    ok: false,
    code: "LOCAL_FIRST_ONLY",
    message:
      "Legacy server-side reminder refresh is disabled. Clients must manage schedules through /notification-schedules.",
  });
};
