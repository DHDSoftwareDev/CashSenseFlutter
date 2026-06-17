export const handler = async () => ({
  ok: false,
  code: "LOCAL_FIRST_ONLY",
  message:
    "Legacy server-side bill reminder scanning is disabled. Clients must manage schedules through CashSense-NotificationSchedules.",
});
