class CloudSyncPolicy {
  static bool isPremiumPlan(String plan) {
    return plan.trim().toLowerCase() != 'free';
  }

  /// User-created finance data stays local on-device.
  /// AWS is only used for auth/billing/push and premium backup/restore.
  static bool get syncUserFinanceDataToAws => false;
}
