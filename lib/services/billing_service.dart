import 'database_service.dart';
import 'package:intl/intl.dart';

/// Lightweight billing shim that provides localized price strings and a
/// simple promo/trial mechanism for the demo app.
///
/// The real platform integration (StoreKit / Play Billing) should be
/// implemented behind this class so callers (UI) remain unchanged.
class BillingService {
  static bool _initialized = false;

  // Internal cache for price data (localized strings). Keys: planId.
  static final Map<String, String> _priceCache = {
    'Monthly': '\$4.99',
    'Annual': '\$29.99',
    'Lifetime': '\$49.99',
  };

  // Simple metadata for plans (durationDays null == lifetime)
  static final Map<String, int?> planDurationDays = {
    'Monthly': 30,
    'Annual': 365,
    'Lifetime': null,
  };

  static Future<void> init() async {
    // Placeholder for platform initialization. In a real implementation
    // we'd query available products and populate _priceCache with
    // localized price strings from the store.
    _initialized = true;
  }

  /// Returns a localized price string suitable for UI (e.g. "$4.99").
  /// Falls back to cached values if platform data isn't available.
  static Future<String?> getPrice(String planId, {String? locale}) async {
    if (!_initialized) await init();

    // If we already have a cached localized string, return it.
    final cached = _priceCache[planId];
    if (cached != null && cached.isNotEmpty) return cached;

    // Fallback: generate a formatted price using NumberFormat for the
    // current locale. We'll use a simple mapping of base amounts here.
    final baseAmounts = <String, double>{'Monthly': 4.99, 'Annual': 29.99, 'Lifetime': 49.99};
    final amount = baseAmounts[planId];
    if (amount == null) return null;

    try {
      final fmt = NumberFormat.simpleCurrency(locale: locale);
      return fmt.format(amount);
    } catch (_) {
      // If locale formatting fails, fall back to en_US style
      return NumberFormat.simpleCurrency(locale: 'en_US').format(amount);
    }
  }

  /// Initiate a purchase for [planId]. This demo implementation simply
  /// persists the plan and a lastPurchase timestamp. Returns true on
  /// success.
  static Future<bool> buy(String planId) async {
  // Persist the selected plan and a simple receipt placeholder.
  await DatabaseService.setSubscriptionPlan(planId);
  await DatabaseService.setSetting('lastPurchase', '$planId|${DateTime.now().toIso8601String()}');

    // Clear any active trial that may have been tied to this promo
    await DatabaseService.setSetting('activeTrialExpiresAt', null);
    await DatabaseService.setSetting('appliedPromoCode', null);

    return true;
  }

  /// Restore a purchase from persisted data (demo only). Returns true if
  /// a plan was restored.
  static Future<bool> restore() async {
    final last = DatabaseService.getSetting<String>('lastPurchase');
    if (last != null && last.isNotEmpty) {
      final parts = last.split('|');
      if (parts.isNotEmpty) {
        await DatabaseService.setSubscriptionPlan(parts[0]);
        return true;
      }
    }
    return false;
  }

  // Promo / Trial handling

  /// Apply a promo code. For demo purposes we support:
  /// - TRIAL30 => 30-day trial for Annual plan
  /// - TRIAL7 => 7-day trial for Monthly plan
  /// Returns a map with result info: {applied: bool, message: String}
  static Future<Map<String, dynamic>> applyPromoCode(String code) async {
    final normalized = code.trim().toUpperCase();

    if (normalized == 'TRIAL30') {
      final expires = DateTime.now().add(const Duration(days: 30));
      await DatabaseService.setSetting('activeTrialExpiresAt', expires.toIso8601String());
      await DatabaseService.setSetting('appliedPromoCode', normalized);
      // Grant trial plan (we'll represent trial as 'Annual' for feature unlocking)
      await DatabaseService.setSubscriptionPlan('Annual');
      return {'applied': true, 'message': '30-day Annual trial applied'};
    }

    if (normalized == 'TRIAL7') {
      final expires = DateTime.now().add(const Duration(days: 7));
      await DatabaseService.setSetting('activeTrialExpiresAt', expires.toIso8601String());
      await DatabaseService.setSetting('appliedPromoCode', normalized);
      await DatabaseService.setSubscriptionPlan('Monthly');
      return {'applied': true, 'message': '7-day Monthly trial applied'};
    }

    // Unknown code: persist it but don't grant trial
    await DatabaseService.setSetting('appliedPromoCode', normalized);
    return {'applied': false, 'message': 'Promo code saved'};
  }

  /// Returns true if a trial is currently active (not expired).
  static bool isTrialActive() {
    final iso = DatabaseService.getSetting<String>('activeTrialExpiresAt');
    if (iso == null || iso.isEmpty) return false;
    try {
      final dt = DateTime.parse(iso);
      return DateTime.now().isBefore(dt);
    } catch (_) {
      return false;
    }
  }

  /// If a trial is active, returns its expiry DateTime, otherwise null.
  static DateTime? trialExpiry() {
    final iso = DatabaseService.getSetting<String>('activeTrialExpiresAt');
    if (iso == null || iso.isEmpty) return null;
    try {
      return DateTime.parse(iso);
    } catch (_) {
      return null;
    }
  }
}
