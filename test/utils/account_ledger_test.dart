import 'package:cashsenseflutter/models/transaction.dart';
import 'package:cashsenseflutter/utils/account_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountLedger', () {
    test('applies each cleared transaction exactly once in ledger order', () {
      final ledger = AccountLedger.calculate(
        initialBalance: 1000,
        transactions: [
          transaction(
            id: 'newest',
            amount: 25,
            type: TransactionType.expense,
            date: DateTime(2026, 7, 3),
            cleared: true,
          ),
          transaction(
            id: 'oldest',
            amount: 100,
            type: TransactionType.income,
            date: DateTime(2026, 7, 1),
            cleared: true,
          ),
          transaction(
            id: 'middle',
            amount: 40,
            type: TransactionType.expense,
            date: DateTime(2026, 7, 2),
            cleared: true,
          ),
        ],
      );

      expect(ledger.clearedRunningBalances['oldest'], 1100);
      expect(ledger.clearedRunningBalances['middle'], 1060);
      expect(ledger.clearedRunningBalances['newest'], 1035);
      expect(ledger.currentBalance, 1035);
    });

    test('pending ledger starts at current balance and remains contiguous', () {
      final ledger = AccountLedger.calculate(
        initialBalance: 500,
        transactions: [
          transaction(
            id: 'cleared',
            amount: 50,
            type: TransactionType.income,
            date: DateTime(2026, 7, 2),
            cleared: true,
          ),
          transaction(
            id: 'pending-old',
            amount: 20,
            type: TransactionType.expense,
            date: DateTime(2026, 7, 1),
            cleared: false,
          ),
          transaction(
            id: 'pending-new',
            amount: 10,
            type: TransactionType.income,
            date: DateTime(2026, 7, 3),
            cleared: false,
          ),
        ],
      );

      expect(ledger.currentBalance, 550);
      expect(ledger.pendingRunningBalances['pending-old'], 530);
      expect(ledger.pendingRunningBalances['pending-new'], 540);
      expect(ledger.availableBalance, 540);
    });

    test('same-day transactions use creation time and id as tie breakers', () {
      final date = DateTime(2026, 7, 1);
      final createdAt = DateTime(2026, 7, 1, 12);
      final ledger = AccountLedger.calculate(
        initialBalance: 100,
        transactions: [
          transaction(
            id: 'b',
            amount: 10,
            type: TransactionType.expense,
            date: date,
            createdAt: createdAt,
            cleared: true,
          ),
          transaction(
            id: 'a',
            amount: 20,
            type: TransactionType.income,
            date: date,
            createdAt: createdAt,
            cleared: true,
          ),
        ],
      );

      expect(ledger.clearedRunningBalances['a'], 120);
      expect(ledger.clearedRunningBalances['b'], 110);
    });

    test('same-day custom order recalculates running balances', () {
      final ledger = AccountLedger.calculate(
        initialBalance: 100,
        transactions: [
          transaction(
            id: 'income',
            amount: 20,
            type: TransactionType.income,
            date: DateTime(2026, 7, 1, 8),
            cleared: true,
            sortOrder: 2,
          ),
          transaction(
            id: 'expense',
            amount: 10,
            type: TransactionType.expense,
            date: DateTime(2026, 7, 1, 18),
            cleared: true,
            sortOrder: 1,
          ),
        ],
      );

      expect(ledger.clearedRunningBalances['expense'], 90);
      expect(ledger.clearedRunningBalances['income'], 110);
      expect(ledger.currentBalance, 110);
    });
  });
}

Transaction transaction({
  required String id,
  required double amount,
  required TransactionType type,
  required DateTime date,
  required bool cleared,
  DateTime? createdAt,
  int? sortOrder,
}) {
  return Transaction(
    id: id,
    amount: amount,
    categoryId: 'category',
    type: type,
    description: id,
    date: date,
    createdAt: createdAt ?? date,
    cleared: cleared,
    sortOrder: sortOrder,
  );
}
