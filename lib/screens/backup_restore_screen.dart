// ignore_for_file: prefer_interpolation_to_compose_strings, use_build_context_synchronously, unused_import, unused_element, unused_local_variable

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:background_fetch/background_fetch.dart' as bf;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/bill.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../providers/user_session_controller.dart';
import '../services/auto_backup_service.dart';
import '../services/database_service.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isRunning = false;

  void _showAutoBackupHistoryPopup() async {
    Directory dir;
    if (Platform.isIOS) {
      final docsDir = await getApplicationDocumentsDirectory();
      dir = Directory('${docsDir.path}/CashSense');
    } else {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Automatic Backups'),
            content: const Text('Downloads directory not available.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }
      dir = Directory('${downloadsDir.path}/CashSense');
    }

    List<File> files = [];
    if (await dir.exists()) {
      files = dir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = f.path.split('/').last;
            return name.startsWith('cashsense_auto_backup_') &&
                name.endsWith('.json');
          })
          .toList();

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Automatic Backups'),
        content: SizedBox(
          width: 350,
          child: files.isEmpty
              ? const Text('No automatic backups found.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: files.length,
                  itemBuilder: (context, idx) {
                    final file = files[idx];

                    String titleText;
                    try {
                      final modified = file.lastModifiedSync();
                      final formatted = DateFormat('M/d/yy, h:mm a')
                          .format(modified)
                          .toLowerCase();
                      titleText = 'Backup $formatted';
                    } catch (_) {
                      titleText = 'Backup ${file.path.split('/').last}';
                    }

                    return ListTile(
                      title: Text(titleText),
                      subtitle: Text(
                        file.path,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[700],
                        ),
                        child: const Text('Restore'),
                        onPressed: () async {
                          Navigator.pop(context);
                          final jsonString = await file.readAsString();
                          await _performRestore(jsonString);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _runBackup() async {
    setState(() => _isRunning = true);
    try {
      final jsonString = await AutoBackupService.buildBackupJsonString();
      if (!mounted) return;

      if (jsonString == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup failed'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final bytes = utf8.encode(jsonString);
      final bytesData = Uint8List.fromList(bytes);
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final name = 'cashsense_backup_$timestamp.json';

      String filePath;
      if (Platform.isIOS) {
        final docsDir = await getApplicationDocumentsDirectory();
        final dir = Directory('${docsDir.path}/CashSense');
        await dir.create(recursive: true);
        filePath = '${dir.path}/$name';
      } else {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Downloads directory not available.'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
        final dir = Directory('${downloadsDir.path}/CashSense');
        await dir.create(recursive: true);
        filePath = '${dir.path}/$name';
      }

      final outFile = File(filePath);
      await outFile.writeAsBytes(bytesData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup saved: $filePath'),
          backgroundColor: Colors.blueGrey[400],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  Future<void> _restoreFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Backup File',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      await _performRestore(jsonString);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _performRestore(String jsonData) async {
    try {
      final decoded = jsonDecode(jsonData);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid backup data format');
      }

      final backupData = decoded;
      if (!backupData.containsKey('version') ||
          !backupData.containsKey('transactions')) {
        throw Exception('Invalid backup data format');
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Restore'),
          content: const Text(
            'This will replace current data with the backup. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Restore',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      await DatabaseService.clearAllData();

      final categoriesRaw =
          (backupData['categories'] as List?) ?? const <dynamic>[];
      for (final catData in categoriesRaw) {
        try {
          final category =
              Category.fromJson(Map<String, dynamic>.from(catData as Map));
          await DatabaseService.addCategory(category);
        } catch (_) {}
      }

      final accountsRaw =
          (backupData['accounts'] as List?) ?? const <dynamic>[];
      for (final accData in accountsRaw) {
        try {
          final account =
              Account.fromJson(Map<String, dynamic>.from(accData as Map));
          await DatabaseService.addAccount(account);
        } catch (_) {}
      }

      final transactionsRaw =
          (backupData['transactions'] as List?) ?? const <dynamic>[];
      for (final txData in transactionsRaw) {
        try {
          final transaction =
              Transaction.fromJson(Map<String, dynamic>.from(txData as Map));
          await DatabaseService.addTransaction(transaction);
        } catch (_) {}
      }

      final billsRaw = (backupData['bills'] as List?) ?? const <dynamic>[];
      for (final billData in billsRaw) {
        try {
          final bill =
              Bill.fromJson(Map<String, dynamic>.from(billData as Map));
          await DatabaseService.addBill(bill);
        } catch (_) {}
      }

      final payeesRaw = backupData['payees'];
      if (payeesRaw is List) {
        for (final entry in payeesRaw) {
          try {
            if (entry is Map) {
              await DatabaseService.addPayee(
                Map<String, dynamic>.from(entry),
              );
            }
          } catch (_) {}
        }
      }

      final settingsRaw = backupData['settings'];
      if (settingsRaw is Map<String, dynamic>) {
        for (final entry in settingsRaw.entries) {
          await DatabaseService.setSetting(entry.key, entry.value);
        }
      }

      final occurrenceRaw = backupData['bill_occurrence_status'];
      if (occurrenceRaw is Map<String, dynamic>) {
        await DatabaseService.importBillOccurrenceStatuses(occurrenceRaw);
      }

      await DatabaseService.persistBillOccurrenceStatuses();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restore complete'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userSessionController = context.watch<UserSessionController>();
    final isPremium = userSessionController.isPremium;
    final autoBackupEnabled =
        DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;
    final lastBackupRaw =
        DatabaseService.getSetting<String>('lastAutoBackupAt', null);

    DateTime? lastBackup;
    if (lastBackupRaw != null) {
      try {
        lastBackup = DateTime.parse(lastBackupRaw);
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Backup Data'),
            subtitle: const Text('Create a local backup file'),
            trailing: _isRunning
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(),
                  )
                : null,
            onTap: _isRunning ? null : _runBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore Data'),
            subtitle: const Text('Restore from a backup file'),
            onTap: _restoreFromFile,
          ),
          if (isPremium) ...[
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Automatic Backup History'),
              subtitle: const Text('View and restore recent automatic backups'),
              onTap: _showAutoBackupHistoryPopup,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_upload),
              title: const Text('Automatic Cloud Backup'),
              subtitle: Text(
                autoBackupEnabled
                    ? lastBackup != null
                        ? 'Enabled • Last backup ${DateFormat('M/d/yy h:mm a').format(lastBackup)}'
                        : 'Enabled'
                    : 'Disabled',
              ),
              value: autoBackupEnabled,
              onChanged: (value) async {
                await DatabaseService.setSetting('autoBackupEnabled', value);
                setState(() {});
              },
            ),
          ],
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Backups include transactions, categories, accounts, bills, payees, app settings, and bill occurrence statuses. Attachments are not included.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
