import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/account.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import 'aws_api_service.dart';
import 'billing_service.dart';
import 'cognito_service.dart';
import 'database_service.dart';
import 'amplify_service.dart';
import 'user_auth_service.dart';

class RemoteSyncService {
  static bool _isSyncing = false;

  static Future<void> syncUserDataOnLogin() async {
    if (_isSyncing) return;
    if (!AwsApiService.isConfigured) return;
    if (!_hasSyncAccess()) {
      debugPrint('Remote sync skipped: premium/dev-test access required');
      return;
    }

    _isSyncing = true;
    try {
      final signedIn = await CognitoService.isSignedIn();
      if (!signedIn) return;

      try {
        final attrs = await CognitoService.getCurrentUserAttributes();
        await UserAuthService.saveUserInfo(
          userId: attrs['userId'] ?? '',
          email: attrs['email'] ?? '',
          displayName: attrs['name'] ?? attrs['username'] ?? '',
        );
      } catch (e) {
        debugPrint('Remote sync user context refresh failed: $e');
      }

      final results = await Future.wait<dynamic>([
        AwsApiService.fetchAccounts(),
        AwsApiService.fetchBills(),
        AwsApiService.fetchTransactions(),
        AwsApiService.fetchCategories(),
        AwsApiService.fetchPayees(),
        AwsApiService.fetchPayers(),
        AwsApiService.fetchPayments(),
      ]);

      var accounts = (results[0] as List).cast<Account>().toList();
      var bills = (results[1] as List).cast<Bill>().toList();
      var transactions = (results[2] as List).cast<Transaction>().toList();
      var remoteCategories = (results[3] as List).cast<Category>().toList();
      var remotePayees = (results[4] as List<Map<String, dynamic>>).toList();
      var remotePayers = (results[5] as List<Map<String, dynamic>>).toList();
      var payments = (results[6] as List<Map<String, dynamic>>).toList();

      final bool remoteEmpty =
          accounts.isEmpty &&
          bills.isEmpty &&
          transactions.isEmpty &&
          remoteCategories.isEmpty &&
          remotePayees.isEmpty &&
          remotePayers.isEmpty &&
          payments.isEmpty;

      if (remoteEmpty) {
        final cloudSnapshot = await _fetchCloudBackupSnapshot();
        if (cloudSnapshot != null) {
          debugPrint('Remote API empty. Restoring latest cloud backup on login.');
          accounts = cloudSnapshot.accounts;
          bills = cloudSnapshot.bills;
          transactions = cloudSnapshot.transactions;
          remoteCategories = cloudSnapshot.categories;
          remotePayees = cloudSnapshot.payees;
          remotePayers = cloudSnapshot.payers;
          payments = cloudSnapshot.payments;

          if (cloudSnapshot.billOccurrenceStatuses.isNotEmpty) {
            await DatabaseService.importBillOccurrenceStatuses(
              cloudSnapshot.billOccurrenceStatuses,
            );
          }
        }
      }

      final categories = _buildCategoryList(
        remoteCategories: remoteCategories,
        transactions: transactions,
        bills: bills,
      );

      final inferredContacts = _inferContactsFromTransactions(
        transactions,
      );

      await DatabaseService.hydrateFromRemoteSnapshot(
        accounts: accounts,
        bills: bills,
        transactions: transactions,
        categories: categories,
        payees: [...remotePayees, ...inferredContacts['payees']!],
        payers: [...remotePayers, ...inferredContacts['payers']!],
        payments: payments,
      );

      debugPrint(
        'Remote sync complete: accounts=${accounts.length}, bills=${bills.length}, '
        'transactions=${transactions.length}, categories=${categories.length}, '
        'payees=${remotePayees.length}, payers=${remotePayers.length}, payments=${payments.length}',
      );
    } catch (e) {
      debugPrint('Remote sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  static bool _hasSyncAccess() {
    if (_hasPremiumAccess()) return true;

    if (kDebugMode) {
      debugPrint('Remote sync enabled for debug build');
      return true;
    }

    final envFlag = (dotenv.env['ALLOW_TEST_ACCOUNT_SYNC'] ?? '')
        .trim()
        .toLowerCase();
    if (envFlag == '1' || envFlag == 'true' || envFlag == 'yes') {
      debugPrint('Remote sync enabled via ALLOW_TEST_ACCOUNT_SYNC');
      return true;
    }

    return false;
  }

  static bool _hasPremiumAccess() {
    final plan = DatabaseService.subscriptionVersion.value;
    if (plan.isNotEmpty && plan != 'Free') return true;
    if (BillingService.isTrialActive()) return true;
    return false;
  }

  static Future<_CloudBackupSnapshot?> _fetchCloudBackupSnapshot() async {
    try {
      final signedIn = await CognitoService.isSignedIn();
      if (!signedIn) return null;

      final userId = await UserAuthService.getCurrentUserId();
      if (userId.isEmpty) return null;

      final key = 'backups/$userId/auto/latest.json';
      final tmpDir = Directory('${Directory.systemTemp.path}/cashsense_cloud_restore');
      await tmpDir.create(recursive: true);
      final tmpPath = '${tmpDir.path}/latest_${DateTime.now().millisecondsSinceEpoch}.json';

      final downloaded = await AmplifyService.downloadFile(key, tmpPath);
      if (!downloaded) return null;

      final file = File(tmpPath);
      if (!await file.exists()) return null;

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final accounts = _parseModelList<Account>(decoded['accounts'], Account.fromJson);
      final bills = _parseModelList<Bill>(decoded['bills'], Bill.fromJson);
      final transactions =
          _parseModelList<Transaction>(decoded['transactions'], Transaction.fromJson);
      final categories = _parseModelList<Category>(decoded['categories'], Category.fromJson);
      final payees = _parseMapList(decoded['payees']);
      final payers = _parseMapList(decoded['payers']);

      final paymentsRaw = decoded['payments_history'];
      final payments = paymentsRaw is List
          ? _parseMapList(paymentsRaw)
          : <Map<String, dynamic>>[];

      final statusRaw = decoded['bill_occurrence_status'] ??
          (paymentsRaw is Map<String, dynamic> ? paymentsRaw : null);
      final billOccurrenceStatuses =
          statusRaw is Map<String, dynamic> ? statusRaw : <String, dynamic>{};

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

  static List<Category> _buildCategoryList({
    required List<Category> remoteCategories,
    required List<Transaction> transactions,
    required List<Bill> bills,
  }) {
    final byId = <String, Category>{
      for (final c in DatabaseService.getAllCategories()) c.id: c,
      for (final c in remoteCategories) c.id: c,
    };

    void ensureCategoryId(String? id, CategoryType type) {
      final value = (id ?? '').trim();
      if (value.isEmpty || byId.containsKey(value)) return;
      byId[value] = Category(
        id: value,
        name: value,
        iconCodePoint: '0xe88a',
        colorValue: '0xFF607D8B',
        isDefault: false,
        type: type,
      );
    }

    for (final tx in transactions) {
      ensureCategoryId(tx.categoryId, tx.type == TransactionType.income ? CategoryType.income : CategoryType.expense);
    }

    for (final bill in bills) {
      final id = bill.categoryId;
      final type = bill.type.toString().contains('income') ? CategoryType.income : CategoryType.expense;
      ensureCategoryId(id, type);
    }

    return byId.values.toList();
  }

  static Map<String, List<Map<String, dynamic>>> _inferContactsFromTransactions(
    List<Transaction> transactions,
  ) {
    final payees = <String, Map<String, dynamic>>{};
    final payers = <String, Map<String, dynamic>>{};

    for (final tx in transactions) {
      final payeeId = (tx.payeeId ?? '').trim();
      if (payeeId.isNotEmpty) {
        payees[payeeId] = {
          'id': payeeId,
          'name': payeeId,
          'type': 'payee',
          'categoryId': tx.categoryId,
        };
      }

      final payerId = (tx.payerId ?? '').trim();
      if (payerId.isNotEmpty) {
        payers[payerId] = {
          'id': payerId,
          'name': payerId,
          'type': 'payer',
          'categoryId': tx.categoryId,
        };
      }
    }

    return {
      'payees': payees.values.toList(),
      'payers': payers.values.toList(),
    };
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
