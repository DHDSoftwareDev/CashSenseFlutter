// ignore_for_file: avoid_relative_lib_imports, avoid_print
// Standalone: dart checks/billing_verification_policy_check.dart
import '../lib/services/billing_verification_policy.dart';

void main() {
  var passed = 0;
  const now = 1000;
  String resolve(dynamic response) => BillingVerificationPolicy.verifiedPlan(
    response, nowSeconds: now,
  );
  void reject(dynamic response) {
    try {
      resolve(response);
    } on StateError {
      passed++;
      return;
    }
    throw StateError('An invalid verification response was accepted.');
  }
  for (final plan in ['Monthly', 'Annual', 'Lifetime']) {
    final result = resolve({
      'verified': true, 'plan': plan, 'premiumUntil': 2000,
    });
    if (result != plan) throw StateError('Wrong plan');
    passed++;
  }
  for (final value in [null, [], 'Premium', {},
    {'tier': 'premium', 'isPremium': true},
    {'verified': 'true', 'plan': 'Monthly', 'premiumUntil': 2000},
    {'verified': false, 'plan': 'Monthly', 'premiumUntil': 2000},
    {'verified': true, 'plan': 'Premium', 'premiumUntil': 2000},
    {'verified': true, 'plan': 'Monthly', 'premiumUntil': 1000},
    {'verified': true, 'plan': 'Monthly', 'premiumUntil': 999},
    {'verified': true, 'plan': 'Monthly', 'premiumUntil': '2000'},
    {'verified': true, 'plan': 'Monthly'},
  ]) {
    reject(value);
  }
  print('PASS $passed server-verification response checks');
}
