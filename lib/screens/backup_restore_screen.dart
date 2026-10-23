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
import '../services/remote_sync_service.dart';

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
      files = dir.listSync().whereType<File>().where((f) {
        final name = f.path.split('/').last;
        return name.startsWith('cashsense_auto_backup_') &&
            name.endsWith('.json');
      }).toList();

      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
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
                      final formatted = DateFormat(
                        'M/d/yy, h:mm a',
                      ).format(modified).toLowerCase();
                      titleText = 'Backup $formatted';
                    } catch (_) {
                      titleText = 'Backup ${file.path.split('/').last}';
                    }

                    return ListTile(
                      title: Text(titleText),
                      subtitle: Text(
                        file.path,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
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
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
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
              child: const Text('Restore', style: TextStyle(color: Colors.red)),
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
          final category = Category.fromJson(
            Map<String, dynamic>.from(catData as Map),
          );
          await DatabaseService.addCategory(category);
        } catch (_) {}
      }

      final accountsRaw =
          (backupData['accounts'] as List?) ?? const <dynamic>[];
      for (final accData in accountsRaw) {
        try {
          final account = Account.fromJson(
            Map<String, dynamic>.from(accData as Map),
          );
          await DatabaseService.addAccount(account);
        } catch (_) {}
      }

      final transactionsRaw =
          (backupData['transactions'] as List?) ?? const <dynamic>[];
      for (final txData in transactionsRaw) {
        try {
          final transaction = Transaction.fromJson(
            Map<String, dynamic>.from(txData as Map),
          );
          await DatabaseService.addTransaction(transaction);
        } catch (_) {}
      }

      final billsRaw = (backupData['bills'] as List?) ?? const <dynamic>[];
      for (final billData in billsRaw) {
        try {
          final bill = Bill.fromJson(
            Map<String, dynamic>.from(billData as Map),
          );
          await DatabaseService.addBill(bill);
        } catch (_) {}
      }

      final payeesRaw = backupData['payees'];
      if (payeesRaw is List) {
        for (final entry in payeesRaw) {
          try {
            if (entry is Map) {
              await DatabaseService.addPayee(Map<String, dynamic>.from(entry));
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

  Future<void> _restoreFromCloudBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Cloud Backup'),
        content: const Text(
          'This will replace current local data with your latest premium cloud backup. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRunning = true);
    try {
      final restored = await RemoteSyncService.restoreLatestCloudBackup(
        forceOverwrite: true,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restored
                ? 'Cloud backup restored successfully'
                : 'No cloud backup found for this account',
          ),
          backgroundColor: restored ? Colors.blueGrey : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloud restore failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  Future<void> _backupToCloud() async {
    setState(() => _isRunning = true);
    try {
      final uploaded = await AutoBackupService.backupToCloud();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploaded
                ? 'Cloud backup completed successfully'
                : 'Cloud backup failed',
          ),
          backgroundColor: uploaded ? Colors.blueGrey : Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloud backup failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  BoxDecoration _sectionDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BoxDecoration(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _actionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool showProgress = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: colorScheme.primary,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      trailing: showProgress
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final userSessionController = context.watch<UserSessionController>();
    final isPremium = userSessionController.isPremium;

    final autoBackupEnabled =
        DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;

    final lastBackupRaw = DatabaseService.getSetting<String>(
      'lastAutoBackupAt',
      null,
    );

    DateTime? lastBackup;
    if (lastBackupRaw != null) {
      try {
        lastBackup = DateTime.parse(lastBackupRaw);
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text(
          'Backup & Restore',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'LOCAL BACKUP',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
          ),
          const SizedBox(height: 8),

          Container(
            decoration: _sectionDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _actionTile(
                  context: context,
                  icon: Icons.backup_outlined,
                  title: 'Backup Data',
                  subtitle: 'Create a local backup file',
                  showProgress: _isRunning,
                  onTap: _isRunning ? null : _runBackup,
                ),
                Divider(
                  height: 1,
                  indent: 74,
                  color: colorScheme.outlineVariant
                      .withValues(alpha: 0.35),
                ),
                _actionTile(
                  context: context,
                  icon: Icons.restore_rounded,
                  title: 'Restore Data',
                  subtitle: 'Restore from a backup file',
                  onTap: _isRunning ? null : _restoreFromFile,
                ),
              ],
            ),
          ),

          if (isPremium) ...[
            const SizedBox(height: 24),

            Text(
              'CLOUD BACKUP',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
            ),
            const SizedBox(height: 8),

            Container(
              decoration: _sectionDecoration(context),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _actionTile(
                    context: context,
                    icon: Icons.cloud_upload_outlined,
                    title: 'Backup to Cloud',
                    subtitle:
                        'Upload your current data to your premium cloud backup',
                    showProgress: _isRunning,
                    onTap: _isRunning ? null : _backupToCloud,
                  ),
                  Divider(
                    height: 1,
                    indent: 74,
                    color: colorScheme.outlineVariant
                        .withValues(alpha: 0.35),
                  ),
                  _actionTile(
                    context: context,
                    icon: Icons.cloud_download_outlined,
                    title: 'Restore From Cloud Backup',
                    subtitle:
                        'Replace this device with your latest premium backup',
                    onTap: _isRunning ? null : _restoreFromCloudBackup,
                  ),
                  Divider(
                    height: 1,
                    indent: 74,
                    color: colorScheme.outlineVariant
                        .withValues(alpha: 0.35),
                  ),
                  _actionTile(
                    context: context,
                    icon: Icons.history_rounded,
                    title: 'Automatic Backup History',
                    subtitle: 'View and restore recent automatic backups',
                    onTap: _showAutoBackupHistoryPopup,
                  ),
                  Divider(
                    height: 1,
                    indent: 74,
                    color: colorScheme.outlineVariant
                        .withValues(alpha: 0.35),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    secondary: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.cloud_sync_outlined,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    title: const Text(
                      'Automatic Cloud Backup',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      autoBackupEnabled
                          ? lastBackup != null
                              ? 'Enabled • Last backup ${DateFormat('M/d/yy h:mm a').format(lastBackup)}'
                              : 'Enabled'
                          : 'Disabled',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: autoBackupEnabled,
                    onChanged: (value) async {
                      await DatabaseService.setSetting(
                        'autoBackupEnabled',
                        value,
                      );
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 21,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Backups include transactions, categories, accounts, bills, payees, app settings, and bill occurrence statuses. Attachments are not included.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
