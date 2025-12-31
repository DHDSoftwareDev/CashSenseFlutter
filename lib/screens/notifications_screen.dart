// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/bill_reminder_service.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _billReminders = false;
  int _billRemindersLeadDays = 1; // 0 = on due date, 1 = 1 day before, etc.
  // Only bill reminders are shown for now; other notification types hidden temporarily

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // Initialize local notification permissions (requests on iOS)
    initBillReminderNotifications().then((_) {});
  }

  void _loadSettings() {
    _billReminders = DatabaseService.getSetting<bool>('notif_billReminders', false) ?? false;
    _billRemindersLeadDays = DatabaseService.getSetting<int>('notif_billReminders_leadDays', 1) ?? 1;
  // no-op: other notification settings intentionally not loaded
    setState(() {});
  }

  Future<void> _setSetting(String key, bool value) async {
    await DatabaseService.setSetting(key, value);
    // optionally reconfigure background scheduling or services here
  }

  Future<void> _setBillReminders(bool value) async {
    if (value) {
      // If enabling, prompt user to choose lead time
      final choice = await showDialog<int>(
        context: context,
        builder: (context) {
          int selected = _billRemindersLeadDays;
          return AlertDialog(
            title: const Text('Bill reminder timing'),
            content: StatefulBuilder(builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<int>(
                    title: const Text('On due date'),
                    value: 0,
                    groupValue: selected,
                    onChanged: (v) => setState(() => selected = v ?? 0),
                  ),
                  RadioListTile<int>(
                    title: const Text('1 day before'),
                    value: 1,
                    groupValue: selected,
                    onChanged: (v) => setState(() => selected = v ?? 1),
                  ),
                  RadioListTile<int>(
                    title: const Text('3 days before'),
                    value: 3,
                    groupValue: selected,
                    onChanged: (v) => setState(() => selected = v ?? 3),
                  ),
                  RadioListTile<int>(
                    title: const Text('7 days before'),
                    value: 7,
                    groupValue: selected,
                    onChanged: (v) => setState(() => selected = v ?? 7),
                  ),
                ],
              );
            }),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, selected), child: const Text('Save')),
            ],
          );
        },
      );

      if (choice == null) {
        // user cancelled, do not enable
        return;
      }

      _billRemindersLeadDays = choice;
      await DatabaseService.setSetting('notif_billReminders_leadDays', _billRemindersLeadDays);
    }

    // Persist toggle
    await DatabaseService.setSetting('notif_billReminders', value);
    setState(() {
      _billReminders = value;
    });
    // Re-schedule or cancel reminders immediately based on the new global setting
    try {
      if (value) {
        await BillReminderService().scheduleAllReminders();
      } else {
        await BillReminderService().cancelAllReminders();
      }
    } catch (_) {}
  }

  /// Allow editing the lead-time even when toggle is already enabled.
  Future<void> _editReminderTiming() async {
    final choice = await showDialog<int>(
      context: context,
      builder: (context) {
        int selected = _billRemindersLeadDays;
        return AlertDialog(
          title: const Text('Bill reminder timing'),
          content: StatefulBuilder(builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<int>(
                  title: const Text('On due date'),
                  value: 0,
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v ?? 0),
                ),
                RadioListTile<int>(
                  title: const Text('1 day before'),
                  value: 1,
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v ?? 1),
                ),
                RadioListTile<int>(
                  title: const Text('3 days before'),
                  value: 3,
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v ?? 3),
                ),
                RadioListTile<int>(
                  title: const Text('7 days before'),
                  value: 7,
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v ?? 7),
                ),
              ],
            );
          }),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, selected), child: const Text('Save')),
          ],
        );
      },
    );

    if (choice == null) return; // user canceled

    _billRemindersLeadDays = choice;
    await DatabaseService.setSetting('notif_billReminders_leadDays', _billRemindersLeadDays);
    setState(() {});

    // If reminders are enabled, re-schedule immediately with the new lead time
    try {
      if (_billReminders) await BillReminderService().scheduleAllReminders();
    } catch (_) {}
  }

  Widget _buildSwitch(String title, bool value, String key) {
    String subtitle;
    if (key == 'notif_billReminders') {
      if (!value) {
        subtitle = 'Disabled';
      } else {
    subtitle = _billRemindersLeadDays == 0
      ? 'On due date'
      : '$_billRemindersLeadDays day${_billRemindersLeadDays == 1 ? '' : 's'} before';
      }
    } else {
      subtitle = value ? 'Enabled' : 'Disabled';
    }

    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (v) async {
        if (key == 'notif_billReminders') {
          await _setBillReminders(v);
        } else {
          setState(() {
            switch (key) {
              // other notification keys intentionally not handled here
            }
          });
          await _setSetting(key, v);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _buildSwitch('Bill Reminders', _billReminders, 'notif_billReminders'),
          ListTile(
            title: const Text('Reminder timing'),
            subtitle: Text(
              _billRemindersLeadDays == 0
                  ? 'On due date'
                  : '$_billRemindersLeadDays day${_billRemindersLeadDays == 1 ? '' : 's'} before',
            ),
            enabled: true,
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editReminderTiming,
            ),
            onTap: _editReminderTiming,
          ),
          // Only show bill reminders for now
          const Divider(),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Manage which notifications you want to receive from CashSense. For push notifications, ensure app permissions are enabled in system settings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
