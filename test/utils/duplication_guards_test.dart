import 'package:flutter_test/flutter_test.dart';
import 'package:cashsenseflutter/models/bill.dart';
import 'package:cashsenseflutter/models/transaction.dart';
import 'package:cashsenseflutter/utils/duplication_guards.dart';

void main() {
  group('duplication guards', () {
    test('detects equivalent recurring successor bill', () {
      final source = Bill(
        id: 'source',
        amount: 120,
        description: 'Internet',
        dueDate: DateTime(2026, 4, 10),
        recurrence: Recurrence.weekly,
        recurrenceInterval: 1,
        recurrenceWeekdays: const [5],
        categoryId: 'cat-1',
        type: BillType.expense,
        accountId: 'acc-1',
      );

      final existingSuccessor = Bill(
        id: 'succ',
        amount: 120,
        description: 'Internet',
        dueDate: DateTime(2026, 4, 17),
        recurrence: Recurrence.weekly,
        recurrenceInterval: 1,
        recurrenceWeekdays: const [5],
        categoryId: 'cat-1',
        type: BillType.expense,
        accountId: 'acc-1',
      );

      final hasDup = hasEquivalentRecurringSuccessor(
        candidates: <Bill>[source, existingSuccessor],
        sourceBill: source,
        nextOccurrenceDate: DateTime(2026, 4, 17),
      );

      expect(hasDup, isTrue);
    });

    test('ignores non-equivalent successor bill', () {
      final source = Bill(
        id: 'source',
        amount: 120,
        description: 'Internet',
        dueDate: DateTime(2026, 4, 10),
        recurrence: Recurrence.weekly,
        recurrenceInterval: 1,
        recurrenceWeekdays: const [5],
        categoryId: 'cat-1',
        type: BillType.expense,
        accountId: 'acc-1',
      );

      final differentSuccessor = Bill(
        id: 'succ-2',
        amount: 130,
        description: 'Internet',
        dueDate: DateTime(2026, 4, 17),
        recurrence: Recurrence.weekly,
        recurrenceInterval: 1,
        recurrenceWeekdays: const [5],
        categoryId: 'cat-1',
        type: BillType.expense,
        accountId: 'acc-1',
      );

      final hasDup = hasEquivalentRecurringSuccessor(
        candidates: <Bill>[source, differentSuccessor],
        sourceBill: source,
        nextOccurrenceDate: DateTime(2026, 4, 17),
      );

      expect(hasDup, isFalse);
    });

    test('detects likely duplicate bill payment within guard window', () {
      final existing = Transaction(
        id: 'tx-1',
        amount: 45.50,
        categoryId: 'cat-1',
        type: TransactionType.expense,
        description: 'Payment for 04/10/2026 Internet Utilities',
        date: DateTime(2026, 4, 10),
        createdAt: DateTime(2026, 4, 10, 12, 0, 0),
        billId: 'bill-1',
        occurrenceDate: DateTime(2026, 4, 10),
        accountId: 'acc-1',
        paymentFor: '04/10/2026 Internet Utilities',
      );

      final isDup = isLikelyDuplicateBillPayment(
        transactions: <Transaction>[existing],
        billId: 'bill-1',
        occurrenceDate: DateTime(2026, 4, 10),
        paymentDate: DateTime(2026, 4, 10),
        amount: 45.50,
        type: TransactionType.expense,
        accountId: 'acc-1',
        description: 'Payment for 04/10/2026 Internet Utilities',
        paymentFor: '04/10/2026 Internet Utilities',
        now: DateTime(2026, 4, 10, 12, 0, 15),
      );

      expect(isDup, isTrue);
    });

    test('does not flag older matching payment outside guard window', () {
      final existing = Transaction(
        id: 'tx-2',
        amount: 45.50,
        categoryId: 'cat-1',
        type: TransactionType.expense,
        description: 'Payment for 04/10/2026 Internet Utilities',
        date: DateTime(2026, 4, 10),
        createdAt: DateTime(2026, 4, 10, 12, 0, 0),
        billId: 'bill-1',
        occurrenceDate: DateTime(2026, 4, 10),
        accountId: 'acc-1',
        paymentFor: '04/10/2026 Internet Utilities',
      );

      final isDup = isLikelyDuplicateBillPayment(
        transactions: <Transaction>[existing],
        billId: 'bill-1',
        occurrenceDate: DateTime(2026, 4, 10),
        paymentDate: DateTime(2026, 4, 10),
        amount: 45.50,
        type: TransactionType.expense,
        accountId: 'acc-1',
        description: 'Payment for 04/10/2026 Internet Utilities',
        paymentFor: '04/10/2026 Internet Utilities',
        now: DateTime(2026, 4, 10, 12, 1, 0),
      );

      expect(isDup, isFalse);
    });
  });
}
