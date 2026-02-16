// ignore_for_file: prefer_interpolation_to_compose_strings, use_build_context_synchronously, unused_import, unused_element, unused_local_variable

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:background_fetch/background_fetch.dart' as bf;
import '../services/auto_backup_service.dart';
import '../services/database_service.dart';
import '../models/category.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../models/bill.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isRunning = false;

  void _showAutoBackupHistoryPopup() async {
    // Get the CashSense folder in appropriate directory based on platform
    Directory dir;
    if (Platform.isIOS) {
      // iOS: Use app's documents directory
      final docsDir = await getApplicationDocumentsDirectory();
      dir = Directory('${docsDir.path}/CashSense');
    } else {
      // Android/Desktop: Use Downloads directory
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
      // Only include files that are automatic backups created by the app.
      // Filenames are expected to be like: cashsense_auto_backup_YYYY-MM-DDTHH-MM-SS.json
      files = dir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = f.path.split('/').last;
            return name.startsWith('cashsense_auto_backup_') && name.endsWith('.json');
          })
          .toList();

      // Sort by last modified time (newest first)
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
                      // Example: 11/6/25, 3:15 pm
                      final formatted = DateFormat('M/d/yy, h:mm a').format(modified).toLowerCase();
                      titleText = 'Backup $formatted';
                    } catch (_) {
                      titleText = 'Backup ${file.path.split('/').last}';
                    }

                    return ListTile(
                      title: Text(titleText),
                      subtitle: Text(
                        file.path,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
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
          const SnackBar(content: Text('Backup failed'), backgroundColor: Colors.redAccent),
        );
        return;
      }

      final bytes = utf8.encode(jsonString);
      final bytesData = Uint8List.fromList(bytes);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final name = 'cashsense_backup_' + timestamp + '.json';

      String filePath;
      if (Platform.isIOS) {
        // Use app's documents directory on iOS
        final docsDir = await getApplicationDocumentsDirectory();
        final dir = Directory('${docsDir.path}/CashSense');
        await dir.create(recursive: true);
        filePath = '${dir.path}/$name';
      } else {
        // Use Downloads/CashSense on Android/desktop
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Downloads directory not available.'), backgroundColor: Colors.redAccent),
          );
          return;
        }
        final dir = Directory('${downloadsDir.path}/CashSense');
        await dir.create(recursive: true);
        filePath = '${dir.path}/$name';
      }

      try {
        final outFile = File(filePath);
        await outFile.writeAsBytes(bytesData);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup saved: $filePath'), backgroundColor: Colors.blueGrey[400]),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.orangeAccent),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup error: $e'), backgroundColor: Colors.redAccent),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _performRestore(String jsonData) async {
    try {
      final Map<String, dynamic> backupData = jsonDecode(jsonData);

      if (!backupData.containsKey('version') || !backupData.containsKey('transactions')) {
        throw Exception('Invalid backup data format');
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Restore'),
          content: const Text('This will replace current data with the backup. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore', style: TextStyle(color: Colors.red))),
          ],
        ),
      );

      if (confirmed != true) return;

      // Clear existing data then restore
      await DatabaseService.clearAllData();

      // Restore categories
      for (var catData in backupData['categories'] as List) {
        try {
          final category = Category.fromJson(Map<String, dynamic>.from(catData));
          await DatabaseService.addCategory(category);
        } catch (_) {}
      }

      // Restore accounts
      for (var accData in backupData['accounts'] as List) {
        try {
          final account = Account.fromJson(Map<String, dynamic>.from(accData));
          await DatabaseService.addAccount(account);
        } catch (_) {}
      }

      // Restore transactions
      for (var txData in backupData['transactions'] as List) {
        try {
          final transaction = Transaction.fromJson(Map<String, dynamic>.from(txData));
          await DatabaseService.addTransaction(transaction);
        } catch (_) {}
      }

      // Restore bills
      for (var billData in backupData['bills'] as List) {
        try {
          final bd = Map<String, dynamic>.from(billData);
          final bill = Bill(
            id: bd['id'],
            description: bd['description'],
            amount: (bd['amount'] is num) ? (bd['amount'] as num).toDouble() : double.parse(bd['amount'].toString()),
            dueDate: DateTime.parse(bd['dueDate']),
            categoryId: bd['categoryId'],
            recurrence: Recurrence.values.firstWhere(
              (e) => e.toString().split('.').last == (bd['recurrence'] ?? 'none'),
              orElse: () => Recurrence.none,
            ),
            isPaid: bd['isPaid'] ?? false,
          );
          await DatabaseService.addBill(bill);
        } catch (_) {}
      }

      // Restore settings if included
      if (backupData.containsKey('settings')) {
        final settings = backupData['settings'] as Map<String, dynamic>;
        for (var entry in settings.entries) {
          await DatabaseService.setSetting(entry.key, entry.value);
        }
      }

      // Restore payment history / bill occurrence statuses if present
      if (backupData.containsKey('payments_history') || backupData.containsKey('bill_occurrence_status')) {
        try {
          final occ = (backupData['payments_history'] ?? backupData['bill_occurrence_status']) as Map<String, dynamic>;
          await DatabaseService.importBillOccurrenceStatuses(occ);
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restore complete'), backgroundColor: Colors.blueGrey),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = DatabaseService.subscriptionVersion.value != 'Free';
    final autoBackupEnabled = DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;
    final lastBackupRaw = DatabaseService.getSetting<String>('lastAutoBackupAt', null);
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
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                : null,
            onTap: _isRunning ? null : _runBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore Data'),
            subtitle: const Text('Restore from a backup file'),
            onTap: _restoreFromFile,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Backups include transactions, categories, accounts, bills, payment history, app settings, and bill occurrence statuses. Attachments are not included.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
