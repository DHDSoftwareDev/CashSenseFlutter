import '../models/account.dart';

class CloudRestorePolicy {
  const CloudRestorePolicy._();

  /// A newly installed app is seeded with a blank Cash account before sign-in.
  /// That seed must not prevent a premium backup from being restored.
  static bool isAutomaticRestoreTarget({
    required List<Account> accounts,
    required bool hasBills,
    required bool hasTransactions,
    required bool hasPayees,
    required bool hasCustomCategories,
  }) {
    if (hasBills || hasTransactions || hasPayees || hasCustomCategories) {
      return false;
    }
    return accounts.every(_isBlankSeedAccount);
  }

  static bool _isBlankSeedAccount(Account account) {
    return account.name.trim().toLowerCase() == 'cash' &&
        account.type == AccountType.cash &&
        account.balance == 0 &&
        account.currency.trim().toUpperCase() == 'USD' &&
        account.isActive &&
        (account.description ?? '').trim().isEmpty &&
        (account.institution ?? '').trim().isEmpty &&
        (account.accountNumber ?? '').trim().isEmpty &&
        (account.cardNumber ?? '').trim().isEmpty &&
        account.availableBalance == null &&
        (account.customType ?? '').trim().isEmpty;
  }
}
