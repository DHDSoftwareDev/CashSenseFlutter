import 'database_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'aws_api_service.dart';

/// Lightweight billing shim that provides localized price strings and a
/// simple promo/trial mechanism for the demo app.
///
/// The real platform integration (StoreKit / Play Billing) should be
/// implemented behind this class so callers (UI) remain unchanged.
class BillingService {
  static bool _initialized = false;
  static final InAppPurchase _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  static final Map<String, ProductDetails> _productDetailsByPlan = {};
  static Completer<bool>? _restoreCompleter;

  // IMPORTANT: These must match the product IDs in App Store Connect / Play Console.
  static const String _monthlyProductId = 'cashsense.app.premium.monthly';
  static const String _annualProductId = 'cashsense.app.premium.annual';
  static const String _lifetimeProductId = 'cashsense.app.premium.lifetime';

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

  static String? _planForProductId(String productId) {
    if (productId == _monthlyProductId) return 'Monthly';
    if (productId == _annualProductId) return 'Annual';
    if (productId == _lifetimeProductId) return 'Lifetime';
    return null;
  }

  static Future<void> _grantPlan(String planId, {String? purchaseId}) async {
    await DatabaseService.setSubscriptionPlan(planId);
    await DatabaseService.setSetting(
      'lastPurchase',
      '$planId|${DateTime.now().toIso8601String()}|${purchaseId ?? ''}',
    );
    await DatabaseService.setSetting('activeTrialExpiresAt', null);
    await DatabaseService.setSetting('appliedPromoCode', null);
  }

  static Future<void> _processPurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    bool restoredAny = false;

    for (final purchase in purchases) {
      try {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          final localPlan = _planForProductId(purchase.productID);
          String? resolvedPlan = localPlan;

          // Optional server-side verification hook for Android purchases.
          if (Platform.isAndroid) {
            final token = purchase.verificationData.serverVerificationData;
            if (token.isNotEmpty) {
              await DatabaseService.setSetting('lastGooglePlayToken', token);
              await DatabaseService.setSetting(
                'lastGooglePlayProductId',
                purchase.productID,
              );
              final backendPlan = await AwsApiService.verifyAndroidPurchase(
                productId: purchase.productID,
                purchaseToken: token,
                purchaseId: purchase.purchaseID,
                source: purchase.verificationData.source,
              );
              if (backendPlan != null && backendPlan.isNotEmpty) {
                resolvedPlan = backendPlan;
              }
            }
          }

          if (resolvedPlan != null) {
            await _grantPlan(resolvedPlan, purchaseId: purchase.purchaseID);
            restoredAny = true;
          }
        }

        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      } catch (e) {
        debugPrint('Billing purchase processing failed: $e');
      }
    }

    if (_restoreCompleter != null && !_restoreCompleter!.isCompleted) {
      _restoreCompleter!.complete(restoredAny);
    }
  }

  static Future<void> _queryStoreProducts() async {
    final ids = <String>{
      _monthlyProductId,
      _annualProductId,
      _lifetimeProductId,
    };
    final response = await _iap.queryProductDetails(ids);

    if (response.error != null) {
      debugPrint('Billing product query error: ${response.error}');
    }

    for (final product in response.productDetails) {
      final plan = _planForProductId(product.id);
      if (plan != null) {
        _productDetailsByPlan[plan] = product;
        _priceCache[plan] = product.price;
      }
    }
  }

  static Future<void> init() async {
    if (_initialized) return;

    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('Billing unavailable; using fallback prices');
      _initialized = true;
      return;
    }

    _purchaseSub ??= _iap.purchaseStream.listen(
      _processPurchaseUpdates,
      onDone: () => _purchaseSub = null,
      onError: (Object e) => debugPrint('Billing purchase stream error: $e'),
    );

    if (Platform.isAndroid || Platform.isIOS) {
      await _queryStoreProducts();
    }

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
    final baseAmounts = <String, double>{
      'Monthly': 4.99,
      'Annual': 29.99,
      'Lifetime': 49.99,
    };
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
    if (!_initialized) await init();

    final available = await _iap.isAvailable();
    final product = _productDetailsByPlan[planId];

    // Paid plans must come from a real store product.
    if (!available || product == null) {
      return false;
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    // Subscriptions are purchased through buyNonConsumable in this plugin API.
    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Restore a purchase from persisted data (demo only). Returns true if
  /// a plan was restored.
  static Future<bool> restore() async {
    if (!_initialized) await init();

    final available = await _iap.isAvailable();
    if (available) {
      _restoreCompleter = Completer<bool>();
      await _iap.restorePurchases();

      // Wait briefly for purchase stream callbacks.
      try {
        final restored = await _restoreCompleter!.future.timeout(
          const Duration(seconds: 8),
        );
        if (restored) return true;
      } catch (_) {
        // Fall back to last persisted entitlement below.
      }
    }

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
      await DatabaseService.setSetting(
        'activeTrialExpiresAt',
        expires.toIso8601String(),
      );
      await DatabaseService.setSetting('appliedPromoCode', normalized);
      // Grant trial plan (we'll represent trial as 'Annual' for feature unlocking)
      await DatabaseService.setSubscriptionPlan('Annual');
      return {'applied': true, 'message': '30-day Annual trial applied'};
    }

    if (normalized == 'TRIAL7') {
      final expires = DateTime.now().add(const Duration(days: 7));
      await DatabaseService.setSetting(
        'activeTrialExpiresAt',
        expires.toIso8601String(),
      );
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
