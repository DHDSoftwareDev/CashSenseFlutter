import 'account_operations.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;

import '../models/account.dart';
import '../models/bill.dart';
import '../models/cashsense_user.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import 'aws_api_service.dart';
import 'cognito_service.dart';
import 'database_service.dart';
import 'amplify_service.dart';
import 'backup_access_service.dart';
import 'backup_payload_policy.dart';
import 'cloud_restore_policy.dart';
import 'user_api_service.dart';

class RemoteSyncService {
  static bool _isSyncing = false;

  static Future<void> syncUserDataOnLogin() {
    return AccountOperations.run(() async {
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
      });
  }

  static Future<void> _refreshSubscriptionFromApiUser() {
    return AccountOperations.run(() async {
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
      });
  }

  static Future<bool> restoreLatestCloudBackup({
    required bool forceOverwrite,
  }) {
    return AccountOperations.run(() async {
    final owner = await BackupAccessService.requireCloudAccess();

    if (!forceOverwrite && !_isLocalSnapshotEmpty()) {
      debugPrint('Skipping cloud restore; local data already exists on device');
      return false;
    }

    // Download and parse the cloud backup before changing local data.
    final cloudSnapshot = await _fetchCloudBackupSnapshot();

    if (cloudSnapshot == null) {
      debugPrint('No cloud backup snapshot available for restore');
      return false;
    }

    await BackupAccessService.requireSameAccount(owner);
    return _applySnapshot(cloudSnapshot);
      });
  }

  static Future<bool> restoreFromJson(String raw) {
    return AccountOperations.run(() async {
    final snapshot = _parseBackup(raw);
    return _applySnapshot(snapshot);
      });
  }

  static bool _restoreInProgress = false;

  static Future<bool> _applySnapshot(_CloudBackupSnapshot cloudSnapshot) {
    return AccountOperations.run(() async {
    if (_restoreInProgress) {
      throw StateError('Another restore is already running.');
    }
    _restoreInProgress = true;
    try {
      return await _applySnapshotWithRecovery(cloudSnapshot);
    } finally {
      _restoreInProgress = false;
    }
      });
  }

  static Future<bool> _applySnapshotWithRecovery(
    _CloudBackupSnapshot cloudSnapshot,
  ) {
    return AccountOperations.run(() async {
    // Block a new restore if an unresolved recovery file exists.
    // Also verify that current local data can be safely captured.
    try {
      await DatabaseService.ensureSafeToBeginCloudRestore();
    } catch (e, stackTrace) {
      debugPrint('Cloud restore blocked by recovery safety check: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }

    // Save the original local data to persistent storage
    // before any financial Hive records are replaced.
    try {
      await DatabaseService.writeLocalRestoreRecoveryFile();
    } catch (e, stackTrace) {
      debugPrint(
        'Cloud restore cancelled: persistent recovery '
        'file could not be created: $e',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }

    // At this point, the original data has been saved
    // and verified in the persistent recovery file.
    try {
      await DatabaseService.replaceLocalDataFromCloudBackup(
        accounts: cloudSnapshot.accounts,
        bills: cloudSnapshot.bills,
        transactions: cloudSnapshot.transactions,
        categories: cloudSnapshot.categories,
        payees: cloudSnapshot.payees,
        payers: cloudSnapshot.payers,
        billOccurrenceStatuses: cloudSnapshot.billOccurrenceStatuses,
        settings: cloudSnapshot.settings,
      );

      // The replacement method verifies restored financial
      // records, settings, contacts, and bill statuses.
      //
      // Remove the recovery file only after those checks pass.
      await DatabaseService.finalizeLocalRestoreRecovery(restoreVerified: true);

      debugPrint(
        'Manual cloud restore completed successfully: '
        'accounts=${cloudSnapshot.accounts.length}, '
        'bills=${cloudSnapshot.bills.length}, '
        'transactions=${cloudSnapshot.transactions.length}',
      );

      return true;
    } catch (e, stackTrace) {
      debugPrint('Manual cloud restore failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      // Recover the original local financial data.
      try {
        await DatabaseService.recoverOriginalLocalDataFromRecoveryFile();
        await DatabaseService.finalizeLocalRestoreRecovery(restoreVerified: true);

        debugPrint('Original local data recovered successfully.');

        // Recovery was verified before removing its durable snapshot.
      } catch (rollbackError, rollbackStackTrace) {
        debugPrint('CRITICAL: Local data recovery failed: $rollbackError');
        debugPrintStack(stackTrace: rollbackStackTrace);
      }

      rethrow;
    }
      });
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

  static Future<_CloudBackupSnapshot?> _fetchCloudBackupSnapshot() {
    return AccountOperations.run(() async {
    File? downloadedFile;
    try {
      final signedIn = await CognitoService.isSignedIn();
      if (!signedIn) return null;

      final userId = await BackupAccessService.requireCloudAccess();
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
      downloadedFile = file;
      if (!await file.exists()) return null;

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;

      return _parseBackup(raw);
    } catch (e) {
      debugPrint('Cloud backup download or validation failed: $e');
      rethrow;
    } finally {
      if (downloadedFile != null) {
        try {
          if (await downloadedFile.exists()) await downloadedFile.delete();
        } catch (_) {}
      }
    }
      });
  }

  static _CloudBackupSnapshot _parseBackup(String raw) {
      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Cloud backup is not a valid JSON object.');
      }

      BackupPayloadPolicy.validate(decoded);

      const requiredSections = [
        'accounts',
        'bills',
        'transactions',
        'categories',
      ];

      for (final section in requiredSections) {
        if (decoded[section] is! List) {
          throw FormatException(
            'Cloud backup is missing a valid $section section.',
          );
        }
      }

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

      final settingsRaw = decoded['settings'];

      if (settingsRaw != null && settingsRaw is! Map) {
        throw const FormatException(
          'Cloud backup contains an invalid settings section.',
        );
      }

      final backupSettings = settingsRaw == null
          ? <String, dynamic>{}
          : BackupPayloadPolicy.financialSettings(Map<String, dynamic>.from(settingsRaw));

      final paymentsRaw = decoded['payments_history'];
      final payments = paymentsRaw is List
          ? _parseMapList(paymentsRaw)
          : <Map<String, dynamic>>[];

      final statusRaw =
          decoded['bill_occurrence_status'] ??
          (paymentsRaw is Map<String, dynamic> ? paymentsRaw : null);
      if (statusRaw != null && statusRaw is! Map<String, dynamic>) {
        throw const FormatException('Invalid bill occurrence status section.');
      }
      final billOccurrenceStatuses = statusRaw is Map<String, dynamic>
          ? statusRaw
          : <String, dynamic>{};

      return _CloudBackupSnapshot(
        accounts: accounts,
        bills: bills,
        transactions: transactions,
        categories: categories,
        payees: payees,
        payers: payers,
        payments: payments,
        billOccurrenceStatuses: billOccurrenceStatuses,
        settings: backupSettings,
      );
  }

  static List<T> _parseModelList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! List) {
      throw const FormatException(
        'Cloud backup contains a missing or invalid data list.',
      );
    }

    final out = <T>[];

    for (var index = 0; index < raw.length; index++) {
      final item = raw[index];

      if (item is! Map) {
        throw FormatException(
          'Cloud backup contains an invalid record at index $index.',
        );
      }

      try {
        final record = Map<String, dynamic>.from(item);
        out.add(fromJson(record));
      } catch (e) {
        throw FormatException(
          'Cloud backup record at index $index could not be restored: $e',
        );
      }
    }

    return out;
  }

  static List<Map<String, dynamic>> _parseMapList(dynamic raw) {
    if (raw is! List) {
      throw const FormatException(
        'Cloud backup contains a missing or invalid lookup list.',
      );
    }

    final out = <Map<String, dynamic>>[];

    for (var index = 0; index < raw.length; index++) {
      final item = raw[index];

      if (item is! Map) {
        throw FormatException(
          'Cloud backup contains an invalid lookup at index $index.',
        );
      }

      out.add(Map<String, dynamic>.from(item));
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
    required this.settings,
  });

  final List<Account> accounts;
  final List<Bill> bills;
  final List<Transaction> transactions;
  final List<Category> categories;
  final List<Map<String, dynamic>> payees;
  final List<Map<String, dynamic>> payers;
  final List<Map<String, dynamic>> payments;
  final Map<String, dynamic> billOccurrenceStatuses;
  final Map<String, dynamic> settings;
}
