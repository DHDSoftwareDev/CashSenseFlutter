// ignore_for_file: no_leading_underscores_for_local_identifiers, unnecessary_type_check, unnecessary_null_comparison, unnecessary_brace_in_string_interps

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart' as wm;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:intl/intl.dart';

import 'notification_service.dart';
import 'database_service.dart';
import '../models/bill.dart';

const String _workManagerTaskReminders = 'cashsense_schedule_reminders';

class BillReminderService {
  BillReminderService._private();
  static final BillReminderService _instance = BillReminderService._private();
  factory BillReminderService() => _instance;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Initialize timezone data and set local timezone
    try {
      tzdata.initializeTimeZones();
      final String localTz = await FlutterNativeTimezone.getLocalTimezone();
      final location = tz.getLocation(localTz);
      tz.setLocalLocation(location);
    } catch (e) {
      debugPrint('Failed to initialize timezone: $e');
    }

    // Ensure NotificationService's plugin is ready (it should be initialized earlier)
    // Schedule reminders for upcoming bills now
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
      // Clear previously scheduled notifications that we manage (optional)
      await flutterLocalNotificationsPlugin.cancelAll();

      final bills = DatabaseService.getAllBills();

      // read global enable toggle and leadDays preference
      final bool globalEnabled = DatabaseService.getSetting<bool>('notif_billReminders', false) ?? false;
      final int leadDays = DatabaseService.getSetting<int>('notif_billReminders_leadDays', 1) ?? 1;

      final now = DateTime.now();
      final DateTime targetDueDate = DateTime(now.year, now.month, now.day).add(Duration(days: leadDays));

      if (!globalEnabled) {
        // If global reminders are disabled, ensure nothing is scheduled and exit
        await flutterLocalNotificationsPlugin.cancelAll();
        return;
      }

      for (final bill in bills) {
        // Compute next due date for this bill (handles recurrence basics)
        final DateTime? nextDue = _nextDueDate(bill, now);
        if (nextDue == null) continue;

        final DateTime nextDueDateOnly = DateTime(nextDue.year, nextDue.month, nextDue.day);
        if (nextDueDateOnly != targetDueDate) continue;

        // Schedule immediately since this is for bills due exactly leadDays from now
        final DateTime scheduledAt = now.add(const Duration(seconds: 5));

        await scheduleReminderForBill(bill, scheduledAt, dueDateForMessage: nextDue);
      }
    } catch (e) {
      debugPrint('scheduleAllReminders failed: $e');
    }
  }

  Future<void> scheduleReminderForBill(Bill bill, DateTime scheduledAt, {DateTime? dueDateForMessage}) async {
    try {
      final id = bill.id.hashCode & 0x7fffffff;
      final title = 'Upcoming Bill';
      final dueForMsg = dueDateForMessage ?? bill.dueDate;
      final dueLocal = dueForMsg.toLocal();

      // Determine a best-effort locale string for formatting (e.g. en_US)
      String _deviceLocale() {
        try {
          final ui.Locale loc = ui.PlatformDispatcher.instance.locale;
          if (loc.countryCode != null && loc.countryCode!.isNotEmpty) {
            return '${loc.languageCode}_${loc.countryCode}';
          }
          return loc.languageCode;
        } catch (e) {
          return Intl.getCurrentLocale();
        }
      }

      final String locale = _deviceLocale();

      // Localized currency and date formatting
      final currencyFormatter = NumberFormat.simpleCurrency(locale: locale);
      final amountStr = currencyFormatter.format(bill.amount);
      final dateFormatter = DateFormat.yMd(locale);
      final formattedDue = dateFormatter.format(dueLocal);

      final payeeName = () {
        try {
          if (bill.payeeId == null) return null;
          final payees = DatabaseService.getAllPayees();
          final match = payees.firstWhere((p) => p['id'] == bill.payeeId, orElse: () => <String, dynamic>{});
          if (match is Map && match['name'] != null) return match['name'] as String;
        } catch (_) {}
        return null;
      }();

        final namePrefix = payeeName != null
          ? '${bill.type == BillType.income ? 'Payer' : 'Payee'} ${payeeName}: '
          : '';
      final descPrefix = bill.description?.isNotEmpty == true ? '${bill.description!}: ' : '';
      final body = '${namePrefix}${descPrefix}Amount $amountStr is due on $formattedDue';

      final tz.TZDateTime tzDate = tz.TZDateTime.from(scheduledAt, tz.local);

      const androidDetails = AndroidNotificationDetails(
        'cashsense_channel',
        'CashSense Notifications',
        channelDescription: 'Bill reminders and notifications',
        importance: Importance.high,
        priority: Priority.high,
      );
      const iosDetails = DarwinNotificationDetails();
      const platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final payloadMap = {
        'type': 'bill',
        'billId': bill.id,
        if (payeeName != null) 'payee': payeeName,
        'amount': bill.amount,
        if (bill.description != null) 'description': bill.description,
        if (dueForMsg != null) 'dueAt': dueForMsg.toUtc().toIso8601String(),
      };

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzDate,
        platformDetails,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: null,
        payload: json.encode(payloadMap),
      );

      debugPrint('Scheduled reminder for bill ${bill.id} at $tzDate (id=$id)');
    } catch (e) {
      debugPrint('scheduleReminderForBill failed: $e');
    }
  }

  /// Compute the next due date for a bill on or after [from].
  /// Basic support for recurring types: daily, weekly, monthly, yearly.
  /// Returns null when no upcoming occurrence can be determined.
  DateTime? _nextDueDate(Bill bill, DateTime from) {
    DateTime candidate = bill.dueDate;

    // If the bill's dueDate is already in the future, that's the next occurrence
    if (candidate.isAfter(from) || candidate.isAtSameMomentAs(from)) {
      return candidate;
    }

    // If there is no recurrence, and dueDate is past, nothing to schedule
    if (bill.recurrence == Recurrence.none) return null;

    final interval = bill.recurrenceInterval <= 0 ? 1 : bill.recurrenceInterval;

    // Helper to add months safely
    DateTime addMonths(DateTime dt, int months) {
      final int yearOffset = (dt.month - 1 + months) ~/ 12;
      final int newYear = dt.year + yearOffset;
      final int newMonth = (dt.month - 1 + months) % 12 + 1;
      final int day = math.min(dt.day, DateTime(newYear, newMonth + 1, 0).day);
      return DateTime(newYear, newMonth, day, dt.hour, dt.minute, dt.second, dt.millisecond, dt.microsecond);
    }

    // Advance candidate until it is >= from or we've gone too far (safety limit)
    final DateTime safeLimit = from.add(const Duration(days: 365 * 5)); // 5 years max
    int safety = 0;
    while (candidate.isBefore(from) && candidate.isBefore(safeLimit) && safety < 10000) {
      switch (bill.recurrence) {
        case Recurrence.daily:
          candidate = candidate.add(Duration(days: interval));
          break;
        case Recurrence.weekly:
          candidate = candidate.add(Duration(days: 7 * interval));
          break;
        case Recurrence.monthly:
          candidate = addMonths(candidate, interval);
          break;
        case Recurrence.yearly:
          candidate = addMonths(candidate, 12 * interval);
          break;
        case Recurrence.custom:
          // Basic fallback for custom: use monthly step (custom handling not implemented)
          candidate = addMonths(candidate, interval);
          break;
        case Recurrence.none:
          return null;
      }
      safety++;
    }

    if (candidate.isBefore(from)) return null;

    // If recurrenceEndDate is set and the candidate is after it, don't schedule
    if (bill.recurrenceEndDate != null && candidate.isAfter(bill.recurrenceEndDate!)) return null;

    return candidate;
  }

  Future<void> cancelAllReminders() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint('cancelAllReminders failed: $e');
    }
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
