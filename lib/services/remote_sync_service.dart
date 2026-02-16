import 'package:flutter/foundation.dart' show debugPrint;

import '../models/account.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import 'aws_api_service.dart';
import 'billing_service.dart';
import 'cognito_service.dart';
import 'database_service.dart';
import 'user_auth_service.dart';

class RemoteSyncService {
  static bool _isSyncing = false;

  static Future<void> syncUserDataOnLogin() async {
    if (_isSyncing) return;
    if (!AwsApiService.isConfigured) return;
    if (!_hasPremiumAccess()) {
      debugPrint('Remote sync skipped: premium account required');
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

      final accounts = (results[0] as List).cast<Account>();
      final bills = (results[1] as List).cast<Bill>();
      final transactions = (results[2] as List).cast<Transaction>();
      final remoteCategories = (results[3] as List).cast<Category>();
      final remotePayees = (results[4] as List<Map<String, dynamic>>).toList();
      final remotePayers = (results[5] as List<Map<String, dynamic>>).toList();
      final payments = (results[6] as List<Map<String, dynamic>>).toList();

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

  static bool _hasPremiumAccess() {
    final plan = DatabaseService.subscriptionVersion.value;
    if (plan.isNotEmpty && plan != 'Free') return true;
    if (BillingService.isTrialActive()) return true;
    return false;
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
