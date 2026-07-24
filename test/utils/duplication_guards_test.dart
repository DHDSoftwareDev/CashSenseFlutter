import 'package:flutter_test/flutter_test.dart';
import 'package:cashsenseflutter/models/bill.dart';
import 'package:cashsenseflutter/models/transaction.dart';
import 'package:cashsenseflutter/services/database_service.dart';
import 'package:cashsenseflutter/utils/duplication_guards.dart';

void main() {
  group('bill model parsing', () {
    test('parses string recurrence interval as positive integer', () {
      final bill = Bill.fromJson({
        'id': 'bill-1',
        'amount': 120,
        'description': 'Molly Maid',
        'dueDate': '2026-06-12',
        'recurrence': 'weekly',
        'recurrenceInterval': '3',
        'recurrenceWeekdays': [5],
      });

      expect(bill.recurrence, Recurrence.weekly);
      expect(bill.recurrenceInterval, 3);
      expect(bill.recurrenceWeekdays, [5]);
      expect(bill.recurrenceEndDate, isNull);
    });
  });

  group('bill recurrence generation', () {
    test(
      'every 3 weeks forever includes November through March occurrences',
      () {
        final bill = Bill(
          id: 'molly-maid',
          amount: 120,
          description: 'Molly Maid',
          dueDate: DateTime(2026, 6, 12),
          recurrence: Recurrence.weekly,
          recurrenceInterval: 3,
          recurrenceWeekdays: const [5],
          recurrenceEndDate: null,
          type: BillType.expense,
        );

        final occurrences = DatabaseService.generateBillOccurrenceDatesForRange(
          bill,
          DateTime(2026, 10, 1),
          DateTime(2027, 4, 30),
        ).map((date) => DateTime(date.year, date.month, date.day)).toList();

        expect(
          occurrences,
          containsAll(<DateTime>[
            DateTime(2026, 10, 16),
            DateTime(2026, 11, 6),
            DateTime(2026, 11, 27),
            DateTime(2026, 12, 18),
            DateTime(2027, 1, 8),
            DateTime(2027, 1, 29),
            DateTime(2027, 2, 19),
            DateTime(2027, 3, 12),
            DateTime(2027, 4, 2),
            DateTime(2027, 4, 23),
          ]),
        );
      },
    );

    test('monthly last-day sentinel only emits month-end dates', () {
      final bill = Bill(
        id: 'last-day-bill',
        amount: 100,
        description: 'Last day bill',
        dueDate: DateTime(2026, 1, 31),
        recurrence: Recurrence.monthly,
        recurrenceInterval: 1,
        customDays: const [99],
        type: BillType.expense,
      );

      final occurrences = DatabaseService.generateBillOccurrenceDatesForRange(
        bill,
        DateTime(2026, 1, 1),
        DateTime(2026, 4, 30),
      ).map((date) => DateTime(date.year, date.month, date.day)).toList();

      expect(occurrences, <DateTime>[
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });

    test('legacy monthly 30 and 31 custom days are treated as last day', () {
      final bill = Bill(
        id: 'legacy-last-day-bill',
        amount: 100,
        description: 'Legacy last day bill',
        dueDate: DateTime(2026, 1, 31),
        recurrence: Recurrence.monthly,
        recurrenceInterval: 1,
        customDays: const [30, 31],
        type: BillType.expense,
      );

      final occurrences = DatabaseService.generateBillOccurrenceDatesForRange(
        bill,
        DateTime(2026, 1, 1),
        DateTime(2026, 4, 30),
      ).map((date) => DateTime(date.year, date.month, date.day)).toList();

      expect(occurrences, <DateTime>[
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });
  });

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

    test('does not treat different bill names as the same successor', () {
      final source = Bill(
        id: 'source',
        amount: 120,
        description: 'Molly Maid every 3 weeks',
        dueDate: DateTime(2026, 6, 12),
        recurrence: Recurrence.weekly,
        recurrenceInterval: 3,
        recurrenceWeekdays: const [5],
        categoryId: 'cat-1',
        type: BillType.expense,
        payeeId: 'payee-1',
        accountId: 'acc-1',
      );

      final separateBill = Bill(
        id: 'separate',
        amount: 120,
        description: 'Molly Maid deep clean',
        dueDate: DateTime(2026, 11, 6),
        recurrence: Recurrence.weekly,
        recurrenceInterval: 3,
        recurrenceWeekdays: const [5],
        categoryId: 'cat-1',
        type: BillType.expense,
        payeeId: 'payee-1',
        accountId: 'acc-1',
      );

      final hasDup = hasEquivalentRecurringSuccessor(
        candidates: <Bill>[source, separateBill],
        sourceBill: source,
        nextOccurrenceDate: DateTime(2026, 11, 6),
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

    test('identifies duplicate bill-payment records with different IDs', () {
      final first = Transaction(
        id: 'payment-local',
        amount: 75,
        categoryId: 'utilities',
        type: TransactionType.expense,
        description: 'Payment for Electric',
        date: DateTime(2026, 7, 24),
        createdAt: DateTime(2026, 7, 24, 9),
        updatedAt: DateTime(2026, 7, 24, 9),
        accountId: 'checking',
        billId: 'electric-bill',
        occurrenceDate: DateTime(2026, 7, 20),
        paymentFor: 'Electric 07/20/2026',
      );
      final duplicate = first.copyWith(
        id: 'payment-synced-copy',
        updatedAt: DateTime(2026, 7, 24, 9, 0, 2),
      );

      expect(areEquivalentBillPayments(first, duplicate), isTrue);
    });

    test('does not combine distinct installments', () {
      final first = Transaction(
        id: 'payment-one',
        amount: 50,
        categoryId: 'utilities',
        type: TransactionType.expense,
        description: 'Payment for Electric',
        date: DateTime(2026, 7, 24),
        accountId: 'checking',
        billId: 'electric-bill',
        occurrenceDate: DateTime(2026, 7, 20),
        paymentFor: 'Electric 07/20/2026',
      );
      final second = first.copyWith(id: 'payment-two', amount: 25);

      expect(areEquivalentBillPayments(first, second), isFalse);
    });
  });
}
