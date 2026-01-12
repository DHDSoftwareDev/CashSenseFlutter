// ignore_for_file: no_leading_underscores_for_local_identifiers, unnecessary_type_check, unnecessary_null_comparison, unnecessary_brace_in_string_interps

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart' as wm;
import 'dart:ui' as ui;

import 'package:intl/intl.dart';

import 'notification_service.dart';
import 'database_service.dart';
import 'user_auth_service.dart';
import '../models/bill.dart';
import '../models/transaction.dart';

const String _workManagerTaskReminders = 'cashsense_schedule_reminders';

class BillReminderService {
  BillReminderService._private();
  static final BillReminderService _instance = BillReminderService._private();
  factory BillReminderService() => _instance;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Clear any legacy local reminders and schedule server push reminders now
    await flutterLocalNotificationsPlugin.cancelAll();
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
        await flutterLocalNotificationsPlugin.cancelAll();
        debugPrint('Bill reminders disabled; skipping server scheduling');
        return;
      }

      final userId = await UserAuthService.getCurrentUserId();
      if (userId.isEmpty) {
        debugPrint('Cannot schedule bill reminders: no logged-in user');
        return;
      }

      final now = DateTime.now();
      final DateTime targetDueDate = DateTime(now.year, now.month, now.day).add(Duration(days: leadDays));

      final start = targetDueDate;
      final end = targetDueDate.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      final occurrences = DatabaseService.getBillOccurrencesBetween(start, end);

      if (occurrences.isEmpty) {
        debugPrint('No bill occurrences due on $targetDueDate; nothing to schedule');
        return;
      }

      // Default reminder time: 9:00 AM local time on the target day. If that has already
      // passed (leadDays == 0 and user opens later), push it one minute into the future.
      DateTime scheduledAtLocal = DateTime(targetDueDate.year, targetDueDate.month, targetDueDate.day, 9);
      if (!scheduledAtLocal.isAfter(now)) {
        scheduledAtLocal = now.add(const Duration(minutes: 1));
      }
      final scheduledAtUtc = scheduledAtLocal.toUtc();

      for (final occ in occurrences) {
        final bill = occ['bill'] as Bill;
        final occDate = occ['date'] as DateTime;

        if (_isOccurrencePaid(bill, occDate)) continue;

      await scheduleReminderForBill(
        userId: userId,
        bill: bill,
        scheduledAt: scheduledAtUtc,
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
    required DateTime scheduledAt,
    DateTime? dueDateForMessage,
    required int leadDays,
  }) async {
    try {
      final dueForMsg = dueDateForMessage ?? bill.dueDate;
      final deviceLocale = _deviceLocale();
      final payeeName = () {
        try {
          if (bill.payeeId == null) return null;
          final payees = DatabaseService.getAllPayees();
          final match = payees.firstWhere((p) => p['id'] == bill.payeeId, orElse: () => <String, dynamic>{});
          if (match is Map && match['name'] != null) return match['name'] as String;
        } catch (_) {}
        return null;
      }();

      debugPrint(
        'Bill reminder skipped (AWS backend removed) for bill ${bill.id} at $scheduledAt '
        '(due=$dueForMsg, locale=$deviceLocale)',
      );
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
