const MESSAGE =
  "CashSense now stores finance data locally on device. Cloud lookup sync is disabled.";

function json(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type,Authorization",
      "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
      "Cache-Control": "no-store",
    },
    body: JSON.stringify(body),
  };
}

export const handler = async (event) => {
  const method =
    (event?.requestContext?.http?.method || event?.httpMethod || "").toUpperCase();

  if (method === "OPTIONS") {
    return json(200, { ok: true });
  }

  return json(410, {
    ok: false,
    code: "LOCAL_FIRST_ONLY",
    message: MESSAGE,
  });
};
