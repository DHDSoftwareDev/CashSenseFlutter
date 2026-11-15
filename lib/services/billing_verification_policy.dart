/// Validates the authenticated AWS verification response, never local settings.
/// JWT signature verification and purchase verification remain server duties.
class BillingVerificationPolicy {
  static String verifiedPlan(dynamic response, {required int nowSeconds}) {
    if (response is! Map || response['verified'] != true) {
      throw StateError('Purchase was not verified by AWS.');
    }
    final plan = response['plan'];
    if (plan != 'Monthly' && plan != 'Annual' && plan != 'Lifetime') {
      throw StateError('AWS returned an unsupported purchase plan.');
    }
    final expiry = response['premiumUntil'];
    if (expiry is! int || expiry <= nowSeconds) {
      throw StateError('The verified purchase is no longer active.');
    }
    return plan as String;
  }
}
