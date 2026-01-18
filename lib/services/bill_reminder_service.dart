// ignore_for_file: no_leading_underscores_for_local_identifiers, unnecessary_type_check, unnecessary_null_comparison, unnecessary_brace_in_string_interps, unused_local_variable

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart' as wm;
import 'package:intl/intl.dart';

import '../notification_schedules_api.dart';
import '../reminder_time.dart';
import '../timezone_init.dart';
import 'aws_api_service.dart';
import 'database_service.dart';
import 'user_auth_service.dart';
import '../models/bill.dart';

const String _workManagerTaskReminders = 'cashsense_schedule_reminders';
const String _storedScheduleIdsKey = 'notif_billReminders_scheduleIds';

class BillReminderService {
  BillReminderService._private();
  static final BillReminderService _instance = BillReminderService._private();
  factory BillReminderService() => _instance;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Clear any legacy local reminders and schedule server push reminders now
    await scheduleAllReminders();

    // Initialize Workmanager to refresh schedules daily (best-effort)
    try {
      await wm.Workmanager().initialize(_workmanagerCallback);
      // register a periodic task that runs once a day to refresh schedules
      await wm.Workmanager().registerPeriodicTask(
        'cashsense_schedule_reminders_periodic',
        _workManagerTaskReminders,
        frequency: const Duration(days: 1),
        initialDelay: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('Workmanager initialize/register for reminders failed: $e');
    }
  }

  /// Cancel any previously scheduled notifications and reschedule all upcoming reminders.
  Future<void> scheduleAllReminders() async {
    try {
      // read global enable toggle and leadDays preference
      final bool globalEnabled = DatabaseService.getSetting<bool>('notif_billReminders', false) ?? false;
      final int leadDays = DatabaseService.getSetting<int>('notif_billReminders_leadDays', 1) ?? 1;

      if (!globalEnabled) {
        debugPrint('Bill reminders disabled; skipping server scheduling');
        return;
      }

      if (!AwsApiService.isConfigured) {
        debugPrint('Bill reminders skipped: AWS API base URL not configured');
        return;
      }

      final userId = await UserAuthService.getCurrentUserId();
      if (userId.isEmpty) {
        debugPrint('Cannot schedule bill reminders: no logged-in user');
        return;
      }

      await TimezoneInit.ensureInitialized();
      final timeZone = TimezoneInit.localTimeZoneName();

      final now = DateTime.now();
      final DateTime targetDueDate = DateTime(now.year, now.month, now.day).add(Duration(days: leadDays));

      final start = targetDueDate;
      final end = targetDueDate.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      final occurrences = DatabaseService.getBillOccurrencesBetween(start, end);

      if (occurrences.isEmpty) {
        debugPrint('No bill occurrences due on $targetDueDate; nothing to schedule');
        return;
      }

      for (final occ in occurrences) {
        final bill = occ['bill'] as Bill;
        final occDate = occ['date'] as DateTime;

        if (_isOccurrencePaid(bill, occDate)) continue;

        await scheduleReminderForBill(
          userId: userId,
          bill: bill,
          timeZone: timeZone,
          dueDateForMessage: occDate,
          leadDays: leadDays,
        );
      }
    } catch (e) {
      debugPrint('scheduleAllReminders failed: $e');
    }
  }

  Future<void> scheduleReminderForBill({
    required String userId,
    required Bill bill,
    required String timeZone,
    DateTime? dueDateForMessage,
    required int leadDays,
  }) async {
    try {
      final dueForMsg = dueDateForMessage ?? bill.dueDate;
      final runAtUtcIso = _computeRunAtUtcIso(dueForMsg, leadDays);
      final billName = (bill.description == null || bill.description!.trim().isEmpty)
          ? 'Bill'
          : bill.description!.trim();
      final amountText = NumberFormat.simpleCurrency().format(bill.amount);
      final dueLabel = DateFormat('MM/dd/yyyy').format(dueForMsg);

      final dedupeKey = 'bill:${bill.id}:$dueLabel:lead$leadDays';
      final data = <String, dynamic>{
        'type': 'bill_reminder',
        'billId': bill.id,
        'userId': userId,
        'dueDate': dueLabel,
        'leadDays': leadDays,
      };

      final api = NotificationSchedulesApi(
        baseUrl: AwsApiService.baseUrl,
        getIdToken: AwsApiService.getIdToken,
      );

      final result = await api.createSchedule(
        runAtUtcIso: runAtUtcIso,
        timeZone: timeZone,
        title: '$billName due',
        body: '$amountText due on $dueLabel',
        data: data,
        dedupeKey: dedupeKey,
      );

      final scheduleId = _extractScheduleId(result);
      if (scheduleId.isNotEmpty) {
        final stored = _loadStoredScheduleIds()..[dedupeKey] = scheduleId;
        await _saveStoredScheduleIds(stored);
      } else {
        debugPrint('Schedule created without scheduleId (dedupeKey=$dedupeKey)');
      }
    } catch (e) {
      debugPrint('scheduleReminderForBill failed: $e');
    }
  }

  bool _isOccurrencePaid(Bill bill, DateTime occDate) {
    // Use persisted status if available
    final persisted = DatabaseService.getBillOccurrenceStatus(bill.id, occDate);
    if (persisted != null) {
      final isPaid = persisted['isPaid'] as bool? ?? false;
      final status = persisted['paymentStatus'] as PaymentStatus?;
      if (isPaid || status == PaymentStatus.paid) return true;
    }

    if (bill.paymentStatus == PaymentStatus.paid || bill.isPaid) return true;

    // Fallback: compute from transactions similar to calendar logic
    final occDateStr = DateFormat('MM/dd/yyyy').format(occDate);
    final payments = DatabaseService.getAllTransactions().where((tx) {
      if (tx.billId != bill.id) return false;
      if (tx.occurrenceDate != null) {
        return tx.occurrenceDate!.year == occDate.year &&
            tx.occurrenceDate!.month == occDate.month &&
            tx.occurrenceDate!.day == occDate.day;
      }
      return (tx.date.year == occDate.year &&
              tx.date.month == occDate.month &&
              tx.date.day == occDate.day) ||
          tx.description.contains(occDateStr);
    }).toList();

    double totalPaid = 0.0;
    for (final tx in payments) {
      // Mirror dashboard behavior: treat amounts as positive against bill amount
      totalPaid += tx.amount;
    }

    return totalPaid >= (bill.amount - 0.01);
  }

  Future<void> cancelAllReminders() async {
    try {
      if (!AwsApiService.isConfigured) return;
      final stored = _loadStoredScheduleIds();
      if (stored.isEmpty) return;

      final api = NotificationSchedulesApi(
        baseUrl: AwsApiService.baseUrl,
        getIdToken: AwsApiService.getIdToken,
      );

      for (final scheduleId in stored.values) {
        try {
          await api.deleteSchedule(scheduleId: scheduleId);
        } catch (e) {
          debugPrint('Failed to delete schedule $scheduleId: $e');
        }
      }

      await _saveStoredScheduleIds(<String, String>{});
    } catch (e) {
      debugPrint('cancelAllReminders failed: $e');
    }
  }

  String _computeRunAtUtcIso(DateTime dueDate, int leadDays) {
    final dueDateStr = DateFormat('yyyy-MM-dd').format(dueDate);
    var runAtUtcIso = computeRunAtUtcIso(
      dueDate: dueDateStr,
      daysBefore: leadDays,
      reminderHour: 9,
      reminderMinute: 0,
    );
    final runAtUtc = DateTime.parse(runAtUtcIso);
    final nowUtc = DateTime.now().toUtc();
    if (!runAtUtc.isAfter(nowUtc)) {
      runAtUtcIso = nowUtc.add(const Duration(minutes: 1)).toIso8601String();
    }
    return runAtUtcIso;
  }

  String _extractScheduleId(Map<String, dynamic> result) {
    final id = result['scheduleId'] ?? result['id'];
    if (id == null) return '';
    return id.toString();
  }

  Map<String, String> _loadStoredScheduleIds() {
    final raw = DatabaseService.getSetting<Map>(_storedScheduleIdsKey);
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
    }
    return <String, String>{};
  }

  Future<void> _saveStoredScheduleIds(Map<String, String> value) async {
    await DatabaseService.setSetting(_storedScheduleIdsKey, value);
  }
}

/// Workmanager callback for reminders (Android)
void _workmanagerCallback() {
  wm.Workmanager().executeTask((task, inputData) async {
    debugPrint('Workmanager executing task (reminders): $task');
    if (task == _workManagerTaskReminders) {
      await BillReminderService().scheduleAllReminders();
    }
    return Future.value(true);
  });
}
