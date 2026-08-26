import '../models/bill.dart';

/// Returns the text that should be shown in the editable bill notes field.
///
/// Older bills sometimes stored a generated counterparty or transfer label in
/// [Bill.description]. Only suppress a label when it belongs to this bill;
/// matching an unrelated saved contact must not erase a legitimate note.
String editableBillNote(
  Bill bill, {
  String? payeeName,
  String? fromAccountName,
  String? toAccountName,
}) {
  final raw = (bill.description ?? '').trim();
  if (raw.isEmpty || raw.toLowerCase() == 'bill') return '';

  final normalizedPayeeName = (payeeName ?? '').trim();
  if (normalizedPayeeName.isNotEmpty &&
      raw.toLowerCase() == normalizedPayeeName.toLowerCase()) {
    return '';
  }

  final normalizedFromName = (fromAccountName ?? '').trim();
  final normalizedToName = (toAccountName ?? '').trim();
  if (bill.type == BillType.transfer &&
      normalizedFromName.isNotEmpty &&
      normalizedToName.isNotEmpty &&
      raw.toLowerCase() ==
          'transfer from $normalizedFromName to $normalizedToName'
              .toLowerCase()) {
    return '';
  }

  return raw;
}
