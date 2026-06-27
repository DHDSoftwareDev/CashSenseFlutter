// ignore_for_file: no_leading_underscores_for_local_identifiers, unnecessary_type_check, unnecessary_null_comparison, unnecessary_brace_in_string_interps, unused_local_variable

import 'dart:convert';

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
import '../models/reminder_offset.dart';

const String _workManagerTaskReminders = 'cashsense_schedule_reminders';
const String _storedScheduleIdsKey = 'notif_billReminders_scheduleIds';
const int _scheduleHorizonDays = 90;

class BillReminderService {
  BillReminderService._private();
  static final BillReminderService _instance = BillReminderService._private();
  factory BillReminderService() => _instance;

  bool _initialized = false;

  List<ReminderOffset> _selectedReminderOffsets() {
    try {
      final raw = DatabaseService.getSetting<String>(
        'notif_billReminderOffsets',
        null,
      );
      if (raw == null || raw.trim().isEmpty) return const <ReminderOffset>[];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <ReminderOffset>[];

      final reminders = <ReminderOffset>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          reminders.add(ReminderOffset.fromJson(item));
        } else if (item is Map) {
          reminders.add(
            ReminderOffset.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
      return reminders;
    } catch (_) {
      return const <ReminderOffset>[];
    }
  }

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
      // read global enable toggle and reminder duration preferences
      final bool globalEnabled =
          DatabaseService.getSetting<bool>('notif_billReminders', false) ??
          false;
      final reminders = _selectedReminderOffsets();

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

      await _cleanupLegacySchedules();

      if (reminders.isEmpty) {
        debugPrint(
          'Bill reminders enabled but no reminder durations are set; skipping scheduling',
        );
        return;
      }

      await TimezoneInit.ensureInitialized();
      final timeZone = TimezoneInit.localTimeZoneName();

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(
        start.year,
        start.month,
        start.day + _scheduleHorizonDays,
      );
      final occurrences = DatabaseService.getBillOccurrencesBetween(start, end);

      if (occurrences.isEmpty) {
        debugPrint(
          'No bill occurrences found in reminder scheduling window; nothing to schedule',
        );
        return;
      }

      for (final occ in occurrences) {
        final bill = occ['bill'] as Bill;
        final occDate = occ['date'] as DateTime;

        if (_isOccurrencePaid(bill, occDate)) {
          await cancelRemindersForBillOccurrence(bill.id, occDate);
          continue;
        }

        // Skip if notifications are disabled for this specific bill
        if (!_shouldNotifyForBill(bill.id)) continue;

        for (final reminder in reminders) {
          await scheduleReminderForBill(
            userId: userId,
            bill: bill,
            timeZone: timeZone,
            dueDateForMessage: occDate,
            leadDays: reminder.daysBefore,
            reminderHour: reminder.hour,
            reminderMinute: reminder.minute,
          );
        }
      }
    } catch (e) {
      debugPrint('scheduleAllReminders failed: $e');
    }
  }

  Future<void> refreshAllReminders() async {
    try {
      await cancelAllReminders();
    } catch (e) {
      debugPrint('refreshAllReminders cancel failed: $e');
    }
    await scheduleAllReminders();
  }

  Future<void> cancelRemindersForBillOccurrence(
    String billId,
    DateTime occurrenceDate,
  ) async {
    try {
      if (!AwsApiService.isConfigured) return;
      final stored = _loadStoredScheduleIds();
      if (stored.isEmpty) return;

      final dueLabel = DateFormat('MM/dd/yyyy').format(occurrenceDate);
      final keyPrefix = 'bill:$billId:$dueLabel:';
      final matchingEntries = stored.entries
          .where((entry) => entry.key.startsWith(keyPrefix))
          .toList();
      if (matchingEntries.isEmpty) return;

      final api = NotificationSchedulesApi(
        baseUrl: AwsApiService.baseUrl,
        getIdToken: AwsApiService.getIdToken,
      );

      for (final entry in matchingEntries) {
        try {
          await api.deleteSchedule(scheduleId: entry.value);
        } catch (e) {
          debugPrint('Failed to delete paid bill reminder ${entry.value}: $e');
        }
        stored.remove(entry.key);
      }

      await _saveStoredScheduleIds(stored);
    } catch (e) {
      debugPrint('cancelRemindersForBillOccurrence failed: $e');
    }
  }

  Future<void> scheduleReminderForBill({
    required String userId,
    required Bill bill,
    required String timeZone,
    DateTime? dueDateForMessage,
    required int leadDays,
    required int reminderHour,
    required int reminderMinute,
  }) async {
    try {
      final dueForMsg = dueDateForMessage ?? bill.dueDate;
      final runAtUtcIso = _computeRunAtUtcIsoOrNull(
        dueForMsg,
        leadDays,
        reminderHour,
        reminderMinute,
      );
      if (runAtUtcIso == null) {
        return;
      }
      final billName = _buildBillName(bill);
      final billNote = _buildBillNote(bill, fallbackName: billName);
      final amountText = NumberFormat.simpleCurrency().format(bill.amount);
      final dueLabel = DateFormat('MM/dd/yyyy').format(dueForMsg);
      final occurrenceDate = DateFormat('yyyy-MM-dd').format(dueForMsg);
      final isOverdue = _isPastDue(dueForMsg);

      final dedupeKey =
          'bill:${bill.id}:$occurrenceDate:lead$leadDays:t${reminderHour.toString().padLeft(2, '0')}${reminderMinute.toString().padLeft(2, '0')}:v3';
      final data = <String, dynamic>{
        'type': 'bill_reminder',
        'billId': bill.id,
        'userId': userId,
        'billName': billName,
        'note': billNote,
        'dueDate': dueLabel,
        'occurrenceDate': occurrenceDate,
        'amount': bill.amount,
        'leadDays': leadDays,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'isOverdue': isOverdue,
      };

      final bodyPrefix = isOverdue ? 'Overdue: Due' : 'Due';
      final body = billNote == null || billNote.isEmpty
          ? '$bodyPrefix $dueLabel - $amountText'
          : '$bodyPrefix $dueLabel - $amountText - $billNote';

      final api = NotificationSchedulesApi(
        baseUrl: AwsApiService.baseUrl,
        getIdToken: AwsApiService.getIdToken,
      );

      final baseTitle = billName.isEmpty ? 'Payment due' : billName;
      final title = isOverdue ? 'Overdue: $baseTitle' : baseTitle;

      final result = await api.createSchedule(
        runAtUtcIso: runAtUtcIso,
        timeZone: timeZone,
        title: title,
        body: body,
        data: data,
        dedupeKey: dedupeKey,
        environment: kReleaseMode ? 'production' : 'sandbox',
      );

      final scheduleId = _extractScheduleId(result);
      if (scheduleId.isNotEmpty) {
        final stored = _loadStoredScheduleIds()..[dedupeKey] = scheduleId;
        await _saveStoredScheduleIds(stored);
      } else {
        debugPrint(
          'Schedule created without scheduleId (dedupeKey=$dedupeKey)',
        );
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

  bool _isPastDue(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return due.isBefore(today);
  }

  /// Check if a bill should receive notifications.
  /// Returns true if notifications are enabled (default) or false if explicitly disabled.
  bool _shouldNotifyForBill(String billId) {
    final settingKey = 'notif_bill_${billId}_enabled';
    final setting = DatabaseService.getSetting<bool>(settingKey, true);
    return setting ?? true; // Default to true if setting not found
  }

  Future<void> cancelAllReminders() async {
    try {
      if (!AwsApiService.isConfigured) return;
      final stored = _loadStoredScheduleIds();
      final api = NotificationSchedulesApi(
        baseUrl: AwsApiService.baseUrl,
        getIdToken: AwsApiService.getIdToken,
      );

      final scheduleIds = <String>{
        ...stored.values.where((id) => id.isNotEmpty),
      };

      String? nextToken;
      do {
        final result = await api.listSchedules(
          status: 'scheduled',
          nextToken: nextToken,
        );
        final items = result['items'];
        if (items is List) {
          for (final item in items) {
            if (item is Map && item['scheduleId'] != null) {
              scheduleIds.add(item['scheduleId'].toString());
            }
          }
        }
        nextToken = result['nextToken']?.toString();
        if (nextToken != null && nextToken.isEmpty) nextToken = null;
      } while (nextToken != null);

      for (final scheduleId in scheduleIds) {
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

  String? _computeRunAtUtcIsoOrNull(
    DateTime dueDate,
    int leadDays,
    int reminderHour,
    int reminderMinute,
  ) {
    final dueDateStr = DateFormat('yyyy-MM-dd').format(dueDate);
    final runAtUtcIso = computeRunAtUtcIso(
      dueDate: dueDateStr,
      daysBefore: leadDays,
      reminderHour: reminderHour,
      reminderMinute: reminderMinute,
    );
    final runAtUtc = DateTime.parse(runAtUtcIso);
    final nowUtc = DateTime.now().toUtc();
    if (!runAtUtc.isAfter(nowUtc)) {
      // For overdue unpaid bills, send a catch-up reminder soon.
      final todayLocal = DateTime.now();
      final dueLocalDate = DateTime(dueDate.year, dueDate.month, dueDate.day);
      final todayDate = DateTime(
        todayLocal.year,
        todayLocal.month,
        todayLocal.day,
      );
      if (dueLocalDate.isBefore(todayDate)) {
        return nowUtc.add(const Duration(minutes: 1)).toIso8601String();
      }
      return null;
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
      return raw.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
    return <String, String>{};
  }

  Future<void> _saveStoredScheduleIds(Map<String, String> value) async {
    await DatabaseService.setSetting(_storedScheduleIdsKey, value);
  }

  Future<void> _cleanupLegacySchedules() async {
    final stored = _loadStoredScheduleIds();
    if (stored.isEmpty) return;

    final versionedReminderKey = RegExp(r':v\d+$');
    final legacyKeys = stored.keys
        .where((key) => !versionedReminderKey.hasMatch(key))
        .toList();
    if (legacyKeys.isEmpty) return;

    final api = NotificationSchedulesApi(
      baseUrl: AwsApiService.baseUrl,
      getIdToken: AwsApiService.getIdToken,
    );

    for (final key in legacyKeys) {
      final scheduleId = stored[key];
      if (scheduleId == null || scheduleId.isEmpty) continue;
      try {
        await api.deleteSchedule(scheduleId: scheduleId);
      } catch (e) {
        debugPrint('Failed to delete legacy schedule $scheduleId: $e');
      }
      stored.remove(key);
    }

    await _saveStoredScheduleIds(stored);
  }

  String _buildBillName(Bill bill) {
    final counterparty = _buildCounterpartyName(bill);
    if (counterparty != null && counterparty.isNotEmpty) {
      return _truncate(counterparty, 60);
    }

    final desc = bill.description?.trim() ?? '';
    if (desc.isNotEmpty && desc.toLowerCase() != 'bill') {
      return _truncate(desc, 60);
    }

    return '';
  }

  String? _buildBillNote(Bill bill, {required String fallbackName}) {
    final desc = bill.description?.trim() ?? '';
    if (desc.isNotEmpty && desc.toLowerCase() != fallbackName.toLowerCase()) {
      return _truncate(desc, 80);
    }
    return null;
  }

  String? _buildCounterpartyName(Bill bill) {
    if (bill.payeeId == null || bill.payeeId!.trim().isEmpty) return null;
    final payees = DatabaseService.getAllPayees();
    final match = payees.cast<Map<String, dynamic>?>().firstWhere(
      (entry) =>
          (entry?['id']?.toString() ?? '').trim() == bill.payeeId!.trim(),
      orElse: () => null,
    );
    final name = match?['name']?.toString().trim() ?? '';
    return name.isEmpty ? null : name;
  }

  String _truncate(String value, int maxLen) {
    final text = value.trim();
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen - 1)}…';
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
