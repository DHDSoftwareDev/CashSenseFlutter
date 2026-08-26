import 'package:cashsenseflutter/models/bill.dart';
import 'package:cashsenseflutter/utils/bill_note_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('editableBillNote', () {
    test('keeps a note that happens to match an unrelated contact', () {
      final bill = Bill(
        amount: 75,
        description: 'Household',
        dueDate: DateTime(2026, 8, 25),
        recurrence: Recurrence.monthly,
        payeeId: 'linked-payee',
      );

      expect(editableBillNote(bill, payeeName: 'Utility Company'), 'Household');
    });

    test('suppresses the generated label for the linked payee', () {
      final bill = Bill(
        amount: 75,
        description: 'Utility Company',
        dueDate: DateTime(2026, 8, 25),
        recurrence: Recurrence.monthly,
        payeeId: 'linked-payee',
      );

      expect(editableBillNote(bill, payeeName: 'Utility Company'), isEmpty);
    });

    test('keeps an explicitly entered payee-prefixed note', () {
      final bill = Bill(
        amount: 75,
        description: 'Payee: use the rewards card',
        dueDate: DateTime(2026, 8, 25),
        recurrence: Recurrence.monthly,
      );

      expect(editableBillNote(bill), 'Payee: use the rewards card');
    });
  });
}
