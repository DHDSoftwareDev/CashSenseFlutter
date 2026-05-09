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
import 'session_cleanup_service.dart';
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
      debugPrint('Remote sync allowed for premium user ($plan)');

      await DatabaseService.syncLocallyModifiedBills();

      var accounts = await safeFetch(AwsApiService.fetchAccounts);
      var bills = await safeFetch(AwsApiService.fetchBills);
      var transactions = await safeFetch(AwsApiService.fetchTransactions);
      var remoteCategories = await safeFetch(AwsApiService.fetchCategories);
      var remotePayees = await safeFetch(AwsApiService.fetchPayees);
      var remotePayers = await safeFetch(AwsApiService.fetchPayers);
      var payments = await safeFetch(AwsApiService.fetchPayments);

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
          debugPrint(
            'Remote API empty. Restoring latest cloud backup on login.',
          );
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

      final inferredContacts = _inferContactsFromTransactions(transactions);

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
    } on BackendUserInvalidatedException {
      await SessionCleanupService.clearInvalidatedBackendUser();
      rethrow;
    } catch (e) {
      debugPrint('Remote sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  static Future<void> _refreshSubscriptionFromApiUser() async {
    try {
      final user = await UserApiService.fetchCurrentUser();
      final resolvedPlan = _resolvePlanFromUser(user);

      final currentPlan = DatabaseService.subscriptionVersion.value;
      if (resolvedPlan != currentPlan) {
        await DatabaseService.setSubscriptionPlan(resolvedPlan);
        debugPrint('Subscription synced from /users/me: $resolvedPlan');
      }
    } on BackendUserInvalidatedException {
      rethrow;
    } catch (e) {
      debugPrint('Failed to refresh subscription from /users/me: $e');
    }
  }

  static Future<List<T>> safeFetch<T>(Future<List<T>> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      debugPrint('Remote fetch failed: $e');
      return <T>[];
    }
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

  static List<Category> _buildCategoryList({
    required List<Category> remoteCategories,
    required List<Transaction> transactions,
    required List<Bill> bills,
  }) {
    final byId = <String, Category>{
      for (final c in DatabaseService.getAllCategories()) c.id: c,
      for (final c in remoteCategories) c.id: c,
    };

    void ensureCategoryId(
      String? id,
      CategoryType type, {
      String? preferredName,
    }) {
      final value = (id ?? '').trim();
      if (value.isEmpty || byId.containsKey(value)) return;
      final name = (preferredName ?? '').trim();
      // Skip creating synthetic categories when the ID is opaque and no
      // readable name is available from upstream payloads.
      if (_looksLikeOpaqueId(value) &&
          (name.isEmpty || _looksLikeOpaqueId(name))) {
        return;
      }

      final fallbackName = _looksLikeOpaqueId(value) ? '' : value;
      final resolvedName = name.isEmpty ? fallbackName : name;
      if (resolvedName.trim().isEmpty || _looksLikeOpaqueId(resolvedName)) {
        return;
      }

      byId[value] = Category(
        id: value,
        name: resolvedName,
        iconCodePoint: '0xe88a',
        colorValue: '0xFF607D8B',
        isDefault: false,
        type: type,
      );
    }

    for (final tx in transactions) {
      ensureCategoryId(
        tx.categoryId,
        tx.type == TransactionType.income
            ? CategoryType.income
            : CategoryType.expense,
        preferredName: tx.categoryName,
      );
    }

    for (final bill in bills) {
      final id = bill.categoryId;
      final type = bill.type.toString().contains('income')
          ? CategoryType.income
          : CategoryType.expense;
      ensureCategoryId(id, type);
    }

    return byId.values.toList();
  }

  static bool _looksLikeOpaqueId(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (uuid.hasMatch(v)) return true;
    final longToken = RegExp(r'^[A-Za-z0-9_-]{16,}$');
    return longToken.hasMatch(v);
  }

  static Map<String, List<Map<String, dynamic>>> _inferContactsFromTransactions(
    List<Transaction> transactions,
  ) {
    final payees = <String, Map<String, dynamic>>{};
    final payers = <String, Map<String, dynamic>>{};

    bool isUsableName(String? value) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return false;
      if (_looksLikeOpaqueId(v)) return false;
      return true;
    }

    for (final tx in transactions) {
      final payeeId = (tx.payeeId ?? '').trim();
      if (payeeId.isNotEmpty) {
        final inferredName = isUsableName(tx.payeeName)
            ? tx.payeeName!.trim()
            : (isUsableName(tx.description) ? tx.description.trim() : '');
        if (inferredName.isEmpty) {
          continue;
        }
        payees[payeeId] = {
          'id': payeeId,
          'name': inferredName,
          'type': 'payee',
          'categoryId': tx.categoryId,
        };
      }

      final payerId = (tx.payerId ?? '').trim();
      if (payerId.isNotEmpty) {
        final inferredName = isUsableName(tx.payerName)
            ? tx.payerName!.trim()
            : (isUsableName(tx.description) ? tx.description.trim() : '');
        if (inferredName.isEmpty) {
          continue;
        }
        payers[payerId] = {
          'id': payerId,
          'name': inferredName,
          'type': 'payer',
          'categoryId': tx.categoryId,
        };
      }
    }

    return {'payees': payees.values.toList(), 'payers': payers.values.toList()};
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
