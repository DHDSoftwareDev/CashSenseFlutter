import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/account.dart';
import '../models/bill.dart';
import '../models/cashsense_user.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import 'aws_api_service.dart';
import 'cognito_service.dart';
import 'database_service.dart';
import 'amplify_service.dart';
import 'cloud_restore_policy.dart';
import 'cloud_sync_policy.dart';
import 'user_api_service.dart';
import 'user_auth_service.dart';

class RemoteSyncService {
  static bool _isSyncing = false;

  static Future<void> syncUserDataOnLogin() async {
    if (_isSyncing) return;
    if (!AwsApiService.isConfigured) return;

    _isSyncing = true;
    try {
      final signedIn = await CognitoService.isSignedIn();
      if (!signedIn) return;

      await _refreshSubscriptionFromApiUser();

      final plan = DatabaseService.subscriptionVersion.value;
      if (plan == 'Free') {
        debugPrint('Remote sync skipped: premium subscription required');
        return;
      }
      debugPrint(
        'Premium user detected ($plan); cloud backup actions are available',
      );
    } catch (e) {
      debugPrint('Remote sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  static Future<void> _refreshSubscriptionFromApiUser() async {
    try {
      final localMode = DatabaseService.getSubscriptionModeOverride();
      if (localMode != null) {
        if (DatabaseService.subscriptionVersion.value != localMode) {
          await DatabaseService.setSubscriptionPlan(localMode);
        }
        debugPrint(
          'Subscription API refresh skipped for local mode: $localMode',
        );
        return;
      }

      final user = await UserApiService.fetchCurrentUser();
      final resolvedPlan = _resolvePlanFromUser(user);

      final currentPlan = DatabaseService.subscriptionVersion.value;
      if (resolvedPlan != currentPlan) {
        await DatabaseService.setSubscriptionPlan(resolvedPlan);
        debugPrint('Subscription synced from /users/me: $resolvedPlan');
      }
    } catch (e) {
      debugPrint('Failed to refresh subscription from /users/me: $e');
    }
  }

  static Future<bool> restoreLatestCloudBackup({
    required bool forceOverwrite,
  }) async {
    final plan = DatabaseService.subscriptionVersion.value;
    if (!CloudSyncPolicy.isPremiumPlan(plan)) {
      debugPrint('Cloud restore skipped: premium subscription required');
      return false;
    }

    if (!forceOverwrite && !_isLocalSnapshotEmpty()) {
      debugPrint('Skipping cloud restore; local data already exists on device');
      return false;
    }

    final cloudSnapshot = await _fetchCloudBackupSnapshot();
    if (cloudSnapshot == null) {
      debugPrint('No cloud backup snapshot available for restore');
      return false;
    }

    if (forceOverwrite) {
      await DatabaseService.clearAllData();
      await DatabaseService.setSubscriptionPlan(plan);
    }

    await DatabaseService.hydrateFromRemoteSnapshot(
      accounts: cloudSnapshot.accounts,
      bills: cloudSnapshot.bills,
      transactions: cloudSnapshot.transactions,
      categories: cloudSnapshot.categories,
      payees: cloudSnapshot.payees,
      payers: cloudSnapshot.payers,
      payments: cloudSnapshot.payments,
    );

    if (cloudSnapshot.billOccurrenceStatuses.isNotEmpty) {
      await DatabaseService.importBillOccurrenceStatuses(
        cloudSnapshot.billOccurrenceStatuses,
      );
    }

    debugPrint(
      'Restored latest premium cloud backup to empty local device: '
      'accounts=${cloudSnapshot.accounts.length}, '
      'bills=${cloudSnapshot.bills.length}, '
      'transactions=${cloudSnapshot.transactions.length}',
    );
    return true;
  }

  static bool _isLocalSnapshotEmpty() {
    return CloudRestorePolicy.isAutomaticRestoreTarget(
      accounts: DatabaseService.getAllAccounts(),
      hasBills: DatabaseService.getAllBills().isNotEmpty,
      hasTransactions: DatabaseService.getAllTransactions().isNotEmpty,
      hasPayees: DatabaseService.getAllPayees().isNotEmpty,
      hasCustomCategories: DatabaseService.getAllCategories().any(
        (category) => !category.isDefault,
      ),
    );
  }

  static String _resolvePlanFromUser(CashSenseUser user) {
    final tier = user.tier.trim().toLowerCase();

    if (user.devOverride) return 'Lifetime';
    if (user.testerOverride) return 'Annual';

    if (!user.isPremium) return 'Free';

    if (tier == 'monthly' || tier == 'month') return 'Monthly';
    if (tier == 'annual' || tier == 'yearly' || tier == 'year') return 'Annual';
    if (tier == 'lifetime' || tier == 'premium' || tier == 'pro') {
      return 'Lifetime';
    }
    if (tier == 'free') return 'Free';

    return 'Lifetime';
  }

  static Future<_CloudBackupSnapshot?> _fetchCloudBackupSnapshot() async {
    try {
      final signedIn = await CognitoService.isSignedIn();
      if (!signedIn) return null;

      final userId = await UserAuthService.getCurrentUserId();
      if (userId.isEmpty) return null;

      final key = 'backups/$userId/auto/latest.json';
      final tmpDir = Directory(
        '${Directory.systemTemp.path}/cashsense_cloud_restore',
      );
      await tmpDir.create(recursive: true);
      final tmpPath =
          '${tmpDir.path}/latest_${DateTime.now().millisecondsSinceEpoch}.json';

      final downloaded = await AmplifyService.downloadFile(key, tmpPath);
      if (!downloaded) return null;

      final file = File(tmpPath);
      if (!await file.exists()) return null;

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final accounts = _parseModelList<Account>(
        decoded['accounts'],
        Account.fromJson,
      );
      final bills = _parseModelList<Bill>(decoded['bills'], Bill.fromJson);
      final transactions = _parseModelList<Transaction>(
        decoded['transactions'],
        Transaction.fromJson,
      );
      final categories = _parseModelList<Category>(
        decoded['categories'],
        Category.fromJson,
      );
      final payees = _parseMapList(decoded['payees']);
      final payers = _parseMapList(decoded['payers']);

      final paymentsRaw = decoded['payments_history'];
      final payments = paymentsRaw is List
          ? _parseMapList(paymentsRaw)
          : <Map<String, dynamic>>[];

      final statusRaw =
          decoded['bill_occurrence_status'] ??
          (paymentsRaw is Map<String, dynamic> ? paymentsRaw : null);
      final billOccurrenceStatuses = statusRaw is Map<String, dynamic>
          ? statusRaw
          : <String, dynamic>{};

      try {
        await file.delete();
      } catch (_) {}

      return _CloudBackupSnapshot(
        accounts: accounts,
        bills: bills,
        transactions: transactions,
        categories: categories,
        payees: payees,
        payers: payers,
        payments: payments,
        billOccurrenceStatuses: billOccurrenceStatuses,
      );
    } catch (e) {
      debugPrint('Cloud backup restore on login failed: $e');
      return null;
    }
  }

  static List<T> _parseModelList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! List) return <T>[];
    final out = <T>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          out.add(fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {}
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> _parseMapList(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }
}

class _CloudBackupSnapshot {
  const _CloudBackupSnapshot({
    required this.accounts,
    required this.bills,
    required this.transactions,
    required this.categories,
    required this.payees,
    required this.payers,
    required this.payments,
    required this.billOccurrenceStatuses,
  });

  final List<Account> accounts;
  final List<Bill> bills;
  final List<Transaction> transactions;
  final List<Category> categories;
  final List<Map<String, dynamic>> payees;
  final List<Map<String, dynamic>> payers;
  final List<Map<String, dynamic>> payments;
  final Map<String, dynamic> billOccurrenceStatuses;
}
