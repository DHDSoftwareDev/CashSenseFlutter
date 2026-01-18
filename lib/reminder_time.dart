import 'package:timezone/timezone.dart' as tz;

/// dueDate: "MM/DD/YYYY"
/// daysBefore: 0, 1, 3, 7
/// reminderHour: default 9 (9 AM)
/// reminderMinute: default 0
///
/// Returns UTC ISO string (e.g. "2026-02-02T14:00:00.000Z")
String computeRunAtUtcIso({
  required String dueDate,
  required int daysBefore,
  int reminderHour = 9,
  int reminderMinute = 0,
}) {
  final parts = dueDate.split('-');
  if (parts.length != 3) {
    throw ArgumentError('dueDate must be MM/DD/YYYY');
  }
  final year = int.parse(parts[0]);
  final month = int.parse(parts[1]);
  final day = int.parse(parts[2]);

  // Due date at 9:00 AM LOCAL timezone
  final dueLocal = tz.TZDateTime(tz.local, year, month, day, reminderHour, reminderMinute);

  // Subtract daysBefore
  final runLocal = dueLocal.subtract(Duration(days: daysBefore));

  // Convert to UTC ISO
  return runLocal.toUtc().toIso8601String();
}
