import 'package:cashsenseflutter/models/account.dart';
import 'package:cashsenseflutter/services/cloud_restore_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudRestorePolicy', () {
    test('allows restore when only the install-time Cash account exists', () {
      final result = CloudRestorePolicy.isAutomaticRestoreTarget(
        accounts: [Account(name: 'Cash', type: AccountType.cash)],
        hasBills: false,
        hasTransactions: false,
        hasPayees: false,
        hasCustomCategories: false,
      );

      expect(result, isTrue);
    });

    test('allows restore before any account has been seeded', () {
      final result = CloudRestorePolicy.isAutomaticRestoreTarget(
        accounts: const [],
        hasBills: false,
        hasTransactions: false,
        hasPayees: false,
        hasCustomCategories: false,
      );

      expect(result, isTrue);
    });

    test('does not overwrite a user-configured local account', () {
      final result = CloudRestorePolicy.isAutomaticRestoreTarget(
        accounts: [
          Account(name: 'Checking', type: AccountType.bank, balance: 100),
        ],
        hasBills: false,
        hasTransactions: false,
        hasPayees: false,
        hasCustomCategories: false,
      );

      expect(result, isFalse);
    });

    test('does not restore over locally created finance data', () {
      final seededAccount = [Account(name: 'Cash', type: AccountType.cash)];

      expect(
        CloudRestorePolicy.isAutomaticRestoreTarget(
          accounts: seededAccount,
          hasBills: true,
          hasTransactions: false,
          hasPayees: false,
          hasCustomCategories: false,
        ),
        isFalse,
      );
      expect(
        CloudRestorePolicy.isAutomaticRestoreTarget(
          accounts: seededAccount,
          hasBills: false,
          hasTransactions: true,
          hasPayees: false,
          hasCustomCategories: false,
        ),
        isFalse,
      );
      expect(
        CloudRestorePolicy.isAutomaticRestoreTarget(
          accounts: seededAccount,
          hasBills: false,
          hasTransactions: false,
          hasPayees: true,
          hasCustomCategories: false,
        ),
        isFalse,
      );
    });

    test('does not restore over a locally created category', () {
      final result = CloudRestorePolicy.isAutomaticRestoreTarget(
        accounts: [Account(name: 'Cash', type: AccountType.cash)],
        hasBills: false,
        hasTransactions: false,
        hasPayees: false,
        hasCustomCategories: true,
      );

      expect(result, isFalse);
    });
  });

  test('Account parses the id and balance written by cloud backups', () {
    final account = Account.fromJson({
      'id': 'backup-account-id',
      'name': 'Checking',
      'type': 'bank',
      'balance': 425.50,
      'currency': 'USD',
    });

    expect(account.id, 'backup-account-id');
    expect(account.balance, 425.50);
  });
}
