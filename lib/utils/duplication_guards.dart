import '../models/bill.dart';
import '../models/transaction.dart';

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _sameIntSet(List<int>? a, List<int>? b) {
  final aa = (a ?? <int>[]).toSet();
  final bb = (b ?? <int>[]).toSet();
  if (aa.length != bb.length) return false;
  return aa.containsAll(bb);
}

bool hasEquivalentRecurringSuccessor({
  required List<Bill> candidates,
  required Bill sourceBill,
  required DateTime nextOccurrenceDate,
  String? excludedBillId,
}) {
  for (final candidate in candidates) {
    if (candidate.id == sourceBill.id) continue;
    if (excludedBillId != null && candidate.id == excludedBillId) continue;
    if (candidate.recurrence == Recurrence.none) continue;
    if (!_sameDate(candidate.dueDate, nextOccurrenceDate)) continue;

    final equivalent =
        candidate.recurrence == sourceBill.recurrence &&
        candidate.recurrenceInterval == sourceBill.recurrenceInterval &&
        (candidate.description ?? '').trim().toLowerCase() ==
            (sourceBill.description ?? '').trim().toLowerCase() &&
        _sameIntSet(candidate.customDays, sourceBill.customDays) &&
        _sameIntSet(
          candidate.recurrenceWeekdays,
          sourceBill.recurrenceWeekdays,
        ) &&
        candidate.amount == sourceBill.amount &&
        candidate.type == sourceBill.type &&
        candidate.categoryId == sourceBill.categoryId &&
        candidate.payeeId == sourceBill.payeeId &&
        candidate.accountId == sourceBill.accountId &&
        candidate.fromAccountId == sourceBill.fromAccountId &&
        candidate.toAccountId == sourceBill.toAccountId;

    if (equivalent) return true;
  }

  return false;
}

bool isLikelyDuplicateBillPayment({
  required List<Transaction> transactions,
  required String billId,
  required DateTime occurrenceDate,
  required DateTime paymentDate,
  required double amount,
  required TransactionType type,
  required String? accountId,
  required String description,
  required String paymentFor,
  DateTime? now,
  Duration window = const Duration(seconds: 30),
}) {
  final normalizedNow = now ?? DateTime.now();
  final normalizedAccountId = (accountId ?? '').trim();

  for (final tx in transactions) {
    if ((tx.billId ?? '').trim() != billId) continue;
    if (tx.type != type) continue;
    if ((tx.accountId ?? '').trim() != normalizedAccountId) continue;
    if ((tx.amount - amount).abs() > 0.0001) continue;
    if (!_sameDate(tx.date, paymentDate)) continue;

    final occ = tx.occurrenceDate ?? tx.date;
    if (!_sameDate(occ, occurrenceDate)) continue;
    if (tx.description.trim() != description.trim()) continue;
    if ((tx.paymentFor ?? '').trim() != paymentFor.trim()) continue;

    if (normalizedNow.difference(tx.createdAt) <= window) {
      return true;
    }
  }

  return false;
}

/// Whether two records are duplicate representations of the same bill
/// payment. IDs and timestamps are excluded because legacy save/sync races
/// produced identical payments under different IDs.
bool areEquivalentBillPayments(Transaction a, Transaction b) {
  final aBillId = (a.billId ?? '').trim();
  final bBillId = (b.billId ?? '').trim();
  if (aBillId.isEmpty || aBillId != bBillId) return false;

  final aOccurrence = a.occurrenceDate ?? a.date;
  final bOccurrence = b.occurrenceDate ?? b.date;

  return _sameDate(aOccurrence, bOccurrence) &&
      _sameDate(a.date, b.date) &&
      a.type == b.type &&
      (a.accountId ?? '').trim() == (b.accountId ?? '').trim() &&
      (a.amount - b.amount).abs() <= 0.0001 &&
      a.description.trim().toLowerCase() ==
          b.description.trim().toLowerCase() &&
      (a.paymentFor ?? '').trim().toLowerCase() ==
          (b.paymentFor ?? '').trim().toLowerCase();
}
