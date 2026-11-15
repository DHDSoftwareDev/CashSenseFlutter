import 'account_operations.dart';
import 'database_service.dart';
import 'aws_api_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';

/// Store billing with authenticated server verification and optional staging diagnostics.
class BillingService {
  // Notifies listeners only after AWS verifies a purchase.
  static final StreamController<String> _verifiedPurchaseController =
      StreamController<String>.broadcast();

  static Stream<String> get verifiedPurchases =>
      _verifiedPurchaseController.stream;

  static final StreamController<Map<String, dynamic>> _stagingProfileController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get stagingProfiles =>
      _stagingProfileController.stream;
  static Map<String, dynamic>? _latestStagingProfile;
  static Map<String, dynamic>? get latestStagingProfile => _latestStagingProfile;
  static bool get isStaging => AwsApiService.isBillingStaging;

  static Future<Map<String, dynamic>> refreshStagingProfile() {
    return AccountOperations.run(() async {
    if (!isStaging) throw StateError('Staging billing is not enabled.');
    final accountId = await _verifiedAccountId();
    if (accountId == null) {
      throw StateError('Sign in and finish opening your account first.');
    }
    final profile = await AwsApiService.fetchBillingProfile(
      expectedUserId: accountId,
    );
    // Keep staging diagnostics in memory, separate from normal Premium state.
    _latestStagingProfile = Map<String, dynamic>.unmodifiable(profile);
    _stagingProfileController.add(_latestStagingProfile!);
    return _latestStagingProfile!;
      });
  }

  static final StreamController<String> _statusController =
      StreamController<String>.broadcast();
  static Stream<String> get purchaseStatus => _statusController.stream;
  static bool _initialized = false;
  static final InAppPurchase _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  static final Map<String, ProductDetails> _productDetailsByPlan = {};
  static Completer<bool>? _restoreCompleter;

  // Pending store events are retained only while this process is running.
  // The store/backend must support recovery after app relaunch.
  static final Map<String, PurchaseDetails> _pendingPurchases = {};
  static final Map<String, String> _pendingAccounts = {};
  static final Map<String, String> _purchaseAccountsByProduct = {};
  static final Set<String> _verifying = {};
  static final Map<String, int> _failures = {};
  static final Map<String, DateTime> _retryAfter = {};
  static Timer? _retryTimer;
  static bool _processingRecovery = false;
  static const int _maxAttempts = 5;
  static const Duration _retryDelay = Duration(seconds: 30);

  // IMPORTANT: These must match the product IDs in App Store Connect / Play Console.
  static String get _monthlyProductId => Platform.isAndroid
      ? 'cashsense_premium_monthly'
      : 'cashsense.app.premium.monthly';
  static String get _annualProductId => Platform.isAndroid
      ? 'cashsense_premium_annual'
      : 'cashsense.app.premium.annual';
  static String get _lifetimeProductId => Platform.isAndroid
      ? 'cashsense_premium_lifetime'
      : 'cashsense.app.premium.lifetime';

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

  /// A purchase must not grant a local entitlement without a backend
  /// verification bound to the authenticated Cognito account.
  static Future<String?> _verifiedAccountId() {
    return AccountOperations.run(() async {
    try {
      final userId = await AwsApiService.currentBillingUserId();
      return userId;
    } catch (e) {
      debugPrint('Billing account verification failed: $e');
      return null;
    }
      });
  }

  static String _purchaseKey(PurchaseDetails purchase) {
    if (Platform.isIOS) {
      return 'ios:${purchase.purchaseID ?? ""}:${purchase.productID}';
    }
    return 'android:${purchase.verificationData.serverVerificationData}';
  }

  static Future<void> _processPurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) {
    return AccountOperations.run(() async {
    bool restoredPurchaseVerified = false;
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.error ||
          purchase.status == PurchaseStatus.canceled) {
        _purchaseAccountsByProduct.remove(purchase.productID);
        _statusController.add('Purchase canceled or rejected by the store.');
        if (purchase.pendingCompletePurchase) {
          try {
            await _iap.completePurchase(purchase);
          } catch (e) {
            debugPrint('Store completion failed: $e');
          }
        }
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }

      final accountId = await _verifiedAccountId();
      if (accountId == null) {
        debugPrint('Store verification deferred: no active CashSense account.');
        continue;
      }

      final key = _purchaseKey(purchase);
      if (key.isEmpty ||
          (Platform.isIOS && (purchase.purchaseID?.trim().isEmpty ?? true)) ||
          (Platform.isAndroid &&
              purchase.verificationData.serverVerificationData
                  .trim()
                  .isEmpty)) {
        debugPrint('Store verification deferred: missing purchase identifier.');
        continue;
      }

      // Never move an in-flight purchase to another CashSense account.
      final originalAccount = _pendingAccounts.putIfAbsent(
        key,
        () => _purchaseAccountsByProduct[purchase.productID] ?? accountId,
      );
      if (originalAccount != accountId) {
        debugPrint('Store verification deferred: account has changed.');
        continue;
      }
      _pendingPurchases[key] = purchase;
      if ((_failures[key] ?? 0) >= _maxAttempts) continue;
      final retryAt = _retryAfter[key];
      if (retryAt != null && DateTime.now().isBefore(retryAt)) {
        _schedulePurchaseRecovery();
        continue;
      }
      if (!_verifying.add(key)) continue;

      try {
        String? verifiedPlan;
        if (Platform.isIOS) {
          verifiedPlan = await AwsApiService.verifyApplePurchase(
            productId: purchase.productID,
            transactionId: purchase.purchaseID!.trim(),
            expectedUserId: accountId,
          );
        } else if (Platform.isAndroid) {
          verifiedPlan = await AwsApiService.verifyAndroidPurchase(
            productId: purchase.productID,
            purchaseToken: purchase.verificationData.serverVerificationData,
            purchaseId: purchase.purchaseID,
            source: purchase.verificationData.source,
            expectedUserId: accountId,
          );
        } else {
          throw UnsupportedError('Unsupported billing platform.');
        }

        if (await _verifiedAccountId() != accountId) {
          throw StateError('Account changed during purchase verification.');
        }
        if (isStaging) {
          await refreshStagingProfile();
        } else {
          // Normal builds also require AWS verification. Keep explicit local
          // developer/tester/free modes, rather than overriding their selection.
          final profile = await AwsApiService.fetchBillingProfile(
            expectedUserId: accountId,
          );
          if (profile['isPremium'] != true || verifiedPlan == null) {
            throw StateError('AWS did not confirm active Premium access.');
          }
          if (await _verifiedAccountId() != accountId) {
            throw StateError('Account changed while refreshing Premium.');
          }
          if (DatabaseService.getSubscriptionModeOverride() == null) {
            await DatabaseService.setSubscriptionPlan(verifiedPlan);
          }
        }
        // Retain the pending record if store completion fails, so it can retry.
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        _statusController.add('Purchase verified by AWS.');
        _pendingPurchases.remove(key);
        _pendingAccounts.remove(key);
        _purchaseAccountsByProduct.remove(purchase.productID);
        _failures.remove(key);
        _retryAfter.remove(key);
        if (await _verifiedAccountId() == accountId) {
          if (!isStaging) _verifiedPurchaseController.add(accountId);
          if (purchase.status == PurchaseStatus.restored) {
            restoredPurchaseVerified = true;
          }
        }
      } catch (e) {
        _statusController.add('Purchase processing needs a retry. Refresh AWS membership for the current status.');
        debugPrint('Store purchase verification deferred: $e');
        final failures = (_failures[key] ?? 0) + 1;
        _failures[key] = failures;
        if (failures < _maxAttempts) {
          _retryAfter[key] = DateTime.now().add(_retryDelay);
          _schedulePurchaseRecovery();
        } else {
          debugPrint(
            'Automatic retry limit reached; restore/relaunch required.',
          );
        }
      } finally {
        _verifying.remove(key);
      }
    }

    final completer = _restoreCompleter;
    if (restoredPurchaseVerified &&
        completer != null &&
        !completer.isCompleted) {
      completer.complete(true);
    }
      });
  }

  static void _schedulePurchaseRecovery() {
    if (_retryTimer?.isActive ?? false) return;
    if (_pendingPurchases.isEmpty) return;
    _retryTimer = AccountOperations.outsideLease(() => Timer(_retryDelay, () async {
      _retryTimer = null;
      if (_processingRecovery) return;
      _processingRecovery = true;
      try {
        final accountId = await _verifiedAccountId();
        if (accountId == null) return;
        final eligible = _pendingPurchases.entries
            .where(
              (entry) =>
                  _pendingAccounts[entry.key] == accountId &&
                  (_failures[entry.key] ?? 0) < _maxAttempts,
            )
            .map((entry) => entry.value)
            .toList();
        if (eligible.isNotEmpty) {
          await _processPurchaseUpdates(eligible);
        }
      } catch (e) {
        debugPrint('Purchase retry deferred during account change: $e');
      } finally {
        _processingRecovery = false;
      }
    }));
  }

  /// Retry eligible in-memory transactions after the user signs back in.
  static void resumePendingPurchases() {
    _schedulePurchaseRecovery();
  }

  static Future<void> _queryStoreProducts() {
    return AccountOperations.run(() async {
    final ids = <String>{
      _monthlyProductId,
      _annualProductId,
      _lifetimeProductId,
    };
    final response = await _iap.queryProductDetails(ids);

    if (response.error != null) {
      debugPrint('Billing product query error: ${response.error}');
    }

    if (response.notFoundIDs.isNotEmpty) {
      _statusController.add('Store products not found: ${response.notFoundIDs.join(", ")}');
    }
    for (final product in response.productDetails) {
      final plan = _planForProductId(product.id);
      if (plan != null) {
        _productDetailsByPlan[plan] = product;
        _priceCache[plan] = product.price;
      }
    }
      });
  }

  static Future<void> pauseForAccountChange() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    final restore = _restoreCompleter;
    if (restore != null && !restore.isCompleted) { restore.complete(false); }
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    _initialized = false;
    _latestStagingProfile = null;
    // Keep pending purchases and their original account bindings for retries.
  }

  static Future<void> init() {
    return AccountOperations.run(() async {
    if (_initialized) return;

    // Listen before checking store availability to avoid missing events.
    _purchaseSub ??= AccountOperations.outsideLease(() => _iap.purchaseStream.listen(
      (purchases) {
        unawaited(_processPurchaseUpdates(purchases).catchError((Object e) {
          debugPrint('Purchase handling deferred during account change: $e');
        }));
      },
      onDone: () {
        _purchaseSub = null;
        _initialized = false;
      },
      onError: (Object e) => debugPrint('Billing purchase stream error: $e'),
    ));
    final available = await _iap.isAvailable();

    if (!available) {
      debugPrint(
        'Billing store temporarily unavailable. '
        'Initialization will be retried.',
      );
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      await _queryStoreProducts();
    }

    _initialized = true;
      });
  }

  /// Returns a localized price string suitable for UI (e.g. "$4.99").
  /// Falls back to cached values if platform data isn't available.
  static Future<String?> getPrice(String planId, {String? locale}) {
    return AccountOperations.run(() async {
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
      });
  }

  /// Initiate a store purchase. Premium is granted only by AWS.
  static Future<bool> buy(String planId) {
    return AccountOperations.run(() async {
    if (await _verifiedAccountId() == null) return false;
    if (!_initialized) await init();

    final available = await _iap.isAvailable();
    final product = _productDetailsByPlan[planId];

    // Paid plans must come from a real store product.
    if (!available || product == null) {
      return false;
    }

    final accountId = await _verifiedAccountId();
    if (accountId == null) return false;
    final owner = _purchaseAccountsByProduct[product.id];
    if (owner != null && owner != accountId) {
      throw StateError('An unfinished purchase belongs to another account.');
    }
    _purchaseAccountsByProduct[product.id] = accountId;
    final purchaseParam = PurchaseParam(
      productDetails: product,
      applicationUserName: accountId,
    );
    // Subscriptions are purchased through buyNonConsumable in this plugin API.
    try {
      final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!started) _purchaseAccountsByProduct.remove(product.id);
      return started;
    } catch (_) {
      _purchaseAccountsByProduct.remove(product.id);
      rethrow;
    }
      });
  }

  /// Ask the store to redeliver purchases for server verification.
  static Future<bool> restore() {
    return AccountOperations.run(() async {
    if (await _verifiedAccountId() == null) return false;
    if (!_initialized) await init();

    if (!await _iap.isAvailable()) return false;
    // An explicit restore gets a fresh retry budget for this account.
    final accountId = await _verifiedAccountId();
    if (accountId == null) return false;
    final existingRestore = _restoreCompleter;
    if (existingRestore != null) return existingRestore.future;
    for (final entry in _pendingAccounts.entries) {
      if (entry.value == accountId) {
        _failures.remove(entry.key);
        _retryAfter.remove(entry.key);
      }
    }
    final completer = Completer<bool>();
    _restoreCompleter = completer;
    try {
      await _iap.restorePurchases().timeout(const Duration(seconds: 20));

      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          if (!completer.isCompleted) completer.complete(false);
          debugPrint(
            'Purchase restore timed out while waiting '
            'for server verification.',
          );
          return false;
        },
      );
    } catch (e) {
      if (!completer.isCompleted) completer.complete(false);
      debugPrint('Billing restore failed: $e');
      return false;
    } finally {
      if (identical(_restoreCompleter, completer)) {
        _restoreCompleter = null;
      }
    }
      });
  }

  // Promo / Trial handling

  /// Promotions require backend eligibility validation.
  /// Returns a map with result info: {applied: bool, message: String}
  static Future<Map<String, dynamic>> applyPromoCode(String code) {
    return AccountOperations.run(() async {
    if (await _verifiedAccountId() == null) {
      return {
        'applied': false,
        'message': 'Sign in to your account before applying a promotion.',
      };
    }
    // Promo eligibility and trial activation must be validated by the
    // authenticated backend. Never grant Premium from a hard-coded code.
    return {
      'applied': false,
      'message':
          'Promo activation is unavailable until server verification '
          'is configured.',
    };
      });
  }

  /// Trial access must come from a verified store entitlement.
  static bool isTrialActive() => false;
  static DateTime? trialExpiry() => null;
}
