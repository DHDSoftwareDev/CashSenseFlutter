import '../models/transaction.dart';

/// A single, deterministic account ledger used by every balance display.
///
/// Cleared transactions form the historical/current-balance ledger. Pending
/// transactions form a separate projection that starts at the current balance,
/// matching the separate Pending section in the transactions screen.
class AccountLedger {
  const AccountLedger({
    required this.currentBalance,
    required this.availableBalance,
    required this.clearedRunningBalances,
    required this.pendingRunningBalances,
  });

  final double currentBalance;
  final double availableBalance;
  final Map<String, double> clearedRunningBalances;
  final Map<String, double> pendingRunningBalances;

  static AccountLedger calculate({
    required double initialBalance,
    required Iterable<Transaction> transactions,
  }) {
    final ordered = transactions.toList()..sort(compareTransactions);
    final clearedRunningBalances = <String, double>{};
    final pendingRunningBalances = <String, double>{};

    var currentBalance = initialBalance;
    for (final transaction in ordered.where((tx) => tx.cleared == true)) {
      currentBalance += effectOf(transaction);
      clearedRunningBalances[transaction.id] = currentBalance;
    }

    var availableBalance = currentBalance;
    for (final transaction in ordered.where((tx) => tx.cleared != true)) {
      availableBalance += effectOf(transaction);
      pendingRunningBalances[transaction.id] = availableBalance;
    }

    return AccountLedger(
      currentBalance: currentBalance,
      availableBalance: availableBalance,
      clearedRunningBalances: clearedRunningBalances,
      pendingRunningBalances: pendingRunningBalances,
    );
  }

  static double effectOf(Transaction transaction) {
    return transaction.type == TransactionType.income
        ? transaction.amount
        : -transaction.amount;
  }

  static int compareTransactions(Transaction a, Transaction b) {
    final dateComparison = a.date.compareTo(b.date);
    if (dateComparison != 0) return dateComparison;
    final createdComparison = a.createdAt.compareTo(b.createdAt);
    if (createdComparison != 0) return createdComparison;
    return a.id.compareTo(b.id);
  }
}
