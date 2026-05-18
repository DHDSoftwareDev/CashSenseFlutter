// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/reminder_offset.dart';
import '../services/database_service.dart';
import '../services/bill_reminder_service.dart';
import '../services/cognito_service.dart';
import '../services/push_token_service.dart';
import '../widgets/bill_reminder_picker.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _billReminders = false;
  int _billRemindersLeadDays = 1; // 0 = on due date, 1 = 1 day before, etc.
  List<ReminderOffset> selectedReminders = [];
  bool _syncingToken = false;
  bool _reschedulingReminders = false;
  // Only bill reminders are shown for now; other notification types hidden temporarily

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    _billReminders =
        DatabaseService.getSetting<bool>('notif_billReminders', false) ?? false;
    _billRemindersLeadDays =
        DatabaseService.getSetting<int>('notif_billReminders_leadDays', 1) ?? 1;
    _loadSelectedReminders();
    // no-op: other notification settings intentionally not loaded
    setState(() {});
  }

  void _loadSelectedReminders() {
    final raw = DatabaseService.getSetting<String>(
      'notif_billReminderOffsets',
      null,
    );
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final loaded = <ReminderOffset>[];
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              loaded.add(
                ReminderOffset(
                  daysBefore: (item['daysBefore'] as num?)?.toInt() ?? 1,
                  hour: (item['hour'] as num?)?.toInt() ?? 9,
                  minute: (item['minute'] as num?)?.toInt() ?? 0,
                ),
              );
            } else if (item is Map) {
              loaded.add(
                ReminderOffset(
                  daysBefore: (item['daysBefore'] as num?)?.toInt() ?? 1,
                  hour: (item['hour'] as num?)?.toInt() ?? 9,
                  minute: (item['minute'] as num?)?.toInt() ?? 0,
                ),
              );
            }
          }
          if (loaded.isNotEmpty) {
            selectedReminders = loaded;
            _billRemindersLeadDays = selectedReminders
                .map((r) => r.daysBefore)
                .reduce((a, b) => a < b ? a : b);
            return;
          }
        }
      } catch (_) {}
    }

    selectedReminders = [];
  }

  Future<void> _persistSelectedReminders() async {
    final encoded = jsonEncode(
      selectedReminders.map((r) => r.toJson()).toList(),
    );
    await DatabaseService.setSetting('notif_billReminderOffsets', encoded);
    if (selectedReminders.isNotEmpty) {
      _billRemindersLeadDays = selectedReminders
          .map((r) => r.daysBefore)
          .reduce((a, b) => a < b ? a : b);
      await DatabaseService.setSetting(
        'notif_billReminders_leadDays',
        _billRemindersLeadDays,
      );
    }
  }

  Future<void> _setSetting(String key, bool value) async {
    await DatabaseService.setSetting(key, value);
    // optionally reconfigure background scheduling or services here
  }

  Future<void> _setBillReminders(bool value) async {
    // Persist toggle
    await DatabaseService.setSetting('notif_billReminders', value);
    setState(() {
      _billReminders = value;
    });
    // Re-schedule or cancel reminders immediately based on the new global setting
    try {
      if (value) {
        await BillReminderService().scheduleAllReminders();
        // If enabling bill reminders, register this device for push notifications now
        try {
          final signedIn = await CognitoService.isSignedIn();
          if (signedIn) {
            await PushTokenService.registerDeviceOnLogin();
            PushTokenService.initTokenRefreshListener();
            final info = await PackageInfo.fromPlatform();
            final currentBuild = int.tryParse(info.buildNumber) ?? 0;
            await DatabaseService.setSetting(
              'lastDeviceRegisterBuild',
              currentBuild,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notification device token synced.'),
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sign in to enable push notifications.'),
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to register device: $e')),
            );
          }
        }
      } else {
        await BillReminderService().cancelAllReminders();
      }
    } catch (_) {}
  }

  Future<void> _updateReminderOffsets(List<ReminderOffset> reminders) async {
    setState(() {
      selectedReminders = reminders;
    });
    await _persistSelectedReminders();

    try {
      if (_billReminders) await BillReminderService().refreshAllReminders();
    } catch (_) {}
  }

  String _billReminderSubtitle(bool enabled) {
    if (!enabled) return 'Disabled';
    if (selectedReminders.isEmpty) return 'No duration set';
    if (selectedReminders.length == 1) return selectedReminders.first.daysLabel;
    return '${selectedReminders.length} reminder durations';
  }

  Widget _buildSwitch(String title, bool value, String key) {
    String subtitle;
    if (key == 'notif_billReminders') {
      subtitle = _billReminderSubtitle(value);
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

  Future<void> _syncDeviceToken() async {
    if (_syncingToken) return;
    setState(() => _syncingToken = true);
    try {
      final signedIn = await CognitoService.isSignedIn();
      if (!signedIn) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to sync push notifications.')),
        );
        return;
      }

      if (!_billReminders) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enable bill reminders to sync notifications.'),
          ),
        );
        return;
      }

      await PushTokenService.registerDeviceOnLogin();
      PushTokenService.initTokenRefreshListener();

      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      await DatabaseService.setSetting('lastDeviceRegisterBuild', currentBuild);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification device token synced.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to sync device token: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncingToken = false);
    }
  }

  Future<void> _rescheduleBillRemindersNow() async {
    if (_reschedulingReminders) return;
    setState(() => _reschedulingReminders = true);

    try {
      if (!_billReminders) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enable bill reminders first.')),
        );
        return;
      }

      final signedIn = await CognitoService.isSignedIn();
      if (!signedIn) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to reschedule reminders.')),
        );
        return;
      }

      await BillReminderService().refreshAllReminders();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill reminders rescheduled.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reschedule reminders: $e')),
      );
    } finally {
      if (mounted) setState(() => _reschedulingReminders = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications'), centerTitle: true),
      body: ListView(
        children: [
          _buildSwitch('Bill Reminders', _billReminders, 'notif_billReminders'),
          if (_billReminders)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: BillReminderPicker(
                initialValue: selectedReminders,
                onChanged: _updateReminderOffsets,
              ),
            ),
          ListTile(
            title: const Text('Sync push notifications'),
            subtitle: const Text('Re-register this device with the server'),
            trailing: _syncingToken
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onTap: _syncingToken ? null : _syncDeviceToken,
          ),
          ListTile(
            title: const Text('Reschedule bill reminders now'),
            subtitle: const Text('Refresh scheduled reminders immediately'),
            trailing: _reschedulingReminders
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onTap: _reschedulingReminders ? null : _rescheduleBillRemindersNow,
          ),
          // Only show bill reminders for now
          const Divider(),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              "Turn on notifications to get bill reminders from CashSense Money Management at the time you choose.\nDon’t forget to allow push notifications in your device’s system settings.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
