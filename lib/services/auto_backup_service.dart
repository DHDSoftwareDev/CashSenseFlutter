import 'dart:convert';
import 'dart:io';

import 'package:background_fetch/background_fetch.dart' as bf;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart' as wm;

import 'amplify_service.dart';
import 'cognito_service.dart';
import 'database_service.dart';
import 'user_auth_service.dart';

const String _workManagerTask = 'cashsense_auto_backup';

class AutoBackupService {
  static Future<void> initialize() async {
    debugPrint('AutoBackupService.initialize() starting...');

    if (Platform.isAndroid) {
      try {
        debugPrint('Initializing Workmanager for Android...');
        await wm.Workmanager().initialize(callbackDispatcher);
        debugPrint('Workmanager initialized successfully');
      } catch (e) {
        debugPrint('Workmanager initialize failed: $e');
      }

      try {
        await configurePeriodicTaskFromSettings();
      } catch (e) {
        debugPrint('configurePeriodicTaskFromSettings failed: $e');
      }
    }

    try {
      debugPrint('Configuring BackgroundFetch...');
      await bf.BackgroundFetch.configure(
        bf.BackgroundFetchConfig(
          minimumFetchInterval: 15,
          stopOnTerminate: false,
          enableHeadless: true,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresStorageNotLow: false,
          requiresDeviceIdle: false,
          requiredNetworkType: bf.NetworkType.ANY,
        ),
        (taskId) async {
          debugPrint('[BackgroundFetch] Event received: $taskId');
          await _onBackgroundFetch(taskId);
        },
        (String taskId) async {
          debugPrint('[BackgroundFetch] Timeout: $taskId');
          bf.BackgroundFetch.finish(taskId);
        },
      );

      final status = await bf.BackgroundFetch.status;
      debugPrint('BackgroundFetch configured successfully. Status: $status');

      if (Platform.isIOS) {
        await bf.BackgroundFetch.start().then((status) {
          debugPrint('[BackgroundFetch] Started with status: $status');
        }).catchError((e) {
          debugPrint('[BackgroundFetch] Start failed: $e');
        });
      }
    } catch (e) {
      debugPrint('BackgroundFetch configure failed: $e');
    }

    debugPrint('AutoBackupService.initialize() completed');
  }

  static Future<void> configurePeriodicTaskFromSettings() async {
    if (!Platform.isAndroid) {
      debugPrint(
        'configurePeriodicTaskFromSettings: skipping Workmanager on non-Android platform',
      );
      return;
    }

    try {
      final enabled =
          DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;

      try {
        await wm.Workmanager()
            .cancelByUniqueName('cashsense_auto_backup_periodic');
      } catch (_) {}

      if (!enabled) {
        debugPrint('Automatic backups disabled; periodic task cancelled');
        return;
      }

      const Duration registerPeriod = Duration(days: 1);

      Duration initialDelay = const Duration(minutes: 1);
      try {
        final now = DateTime.now();
        final nextMidnight =
            DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        final diffToNextMidnight = nextMidnight.difference(now);
        if (!diffToNextMidnight.isNegative) {
          initialDelay = diffToNextMidnight;
        }
      } catch (_) {
        initialDelay = const Duration(minutes: 1);
      }

      debugPrint(
        'Registering auto-backup: period=$registerPeriod, initialDelay=${initialDelay.inSeconds}s',
      );

      await wm.Workmanager().registerPeriodicTask(
        'cashsense_auto_backup_periodic',
        _workManagerTask,
        frequency: registerPeriod,
        initialDelay: initialDelay,
        constraints: wm.Constraints(networkType: wm.NetworkType.notRequired),
      );

      debugPrint('Registered periodic auto-backup task (daily): $registerPeriod');
    } catch (e) {
      debugPrint('Error configuring periodic task: $e');
    }
  }

  static Future<String?> buildBackupJsonString() async {
    try {
      final transactions = DatabaseService.getAllTransactions();
      final categories = DatabaseService.getAllCategories();
      final accounts = DatabaseService.getAllAccounts();
      final bills = DatabaseService.getAllBills();
      final settings = DatabaseService.exportAllSettings();
      final billOccurrences = DatabaseService.exportBillOccurrenceStatuses();
      final payees = DatabaseService.getAllPayees();

      final backupData = {
        'version': '1.1.0',
        'timestamp': DateTime.now().toIso8601String(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'accounts': accounts
            .map((a) => {
                  'id': a.id,
                  'name': a.name,
                  'type': a.type.toString().split('.').last,
                  'balance': a.balance,
                  'isActive': a.isActive,
                  'currency': a.currency,
                  'description': a.description,
                  'institution': a.institution,
                  'accountNumber': a.accountNumber,
                  'availableBalance': a.availableBalance,
                  'customType': a.customType,
                })
            .toList(),
        'bills': bills.map((b) => b.toJson()).toList(),
        'payees': payees,
        'settings': settings,
        'bill_occurrence_status': billOccurrences,
      };

      return const JsonEncoder.withIndent('  ').convert(backupData);
    } catch (e) {
      debugPrint('buildBackupJsonString failed: $e');
      return null;
    }
  }

  static Future<String?> performBackup() async {
    try {
      debugPrint('performBackup() starting...');
      final jsonString = await buildBackupJsonString();
      if (jsonString == null) {
        debugPrint(
          'performBackup() failed: buildBackupJsonString returned null',
        );
        return null;
      }

      Directory baseDir;
      if (Platform.isIOS) {
        final docsDir = await getApplicationDocumentsDirectory();
        baseDir = Directory('${docsDir.path}/CashSense');
      } else {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir == null) {
          debugPrint('Downloads directory not available');
          return null;
        }
        baseDir = Directory('${downloadsDir.path}/CashSense');
      }

      await baseDir.create(recursive: true);
      debugPrint('Backup directory: ${baseDir.path}');

      final now = DateTime.now();
      final filenameTimestamp =
          DateFormat('M-d-yy_h-mm_a').format(now).toLowerCase();
      final filename = 'cashsense_auto_backup_$filenameTimestamp.json';
      final file = File('${baseDir.path}/$filename');
      await file.writeAsString(jsonString);
      debugPrint('Backup file written: ${file.path}');

      await DatabaseService.setSetting(
        'lastAutoBackupAt',
        DateTime.now().toIso8601String(),
      );
      debugPrint('lastAutoBackupAt setting updated');

      try {
        final files = Directory(baseDir.path)
            .listSync()
            .whereType<File>()
            .where((f) =>
                f.path.split('/').last.startsWith('cashsense_auto_backup_') &&
                f.path.endsWith('.json'))
            .toList();

        files.sort(
          (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
        );

        while (files.length > 3) {
          try {
            final toDelete = files.removeAt(0);
            toDelete.deleteSync();
            debugPrint('Deleted old auto-backup: ${toDelete.path}');
          } catch (e) {
            debugPrint('Failed to delete old auto-backup: $e');
            break;
          }
        }
      } catch (e) {
        debugPrint('Auto-backup retention housekeeping failed: $e');
      }

      try {
        final uploaded = await _uploadBackupToCloud(file.path, filename);
        debugPrint(
          uploaded
              ? 'Cloud S3 backup upload complete.'
              : 'Cloud S3 backup upload skipped/failed.',
        );
      } catch (e) {
        debugPrint('Cloud S3 backup upload error: $e');
      }

      debugPrint('performBackup() completed successfully');
      return file.path;
    } catch (e) {
      debugPrint('performBackup failed: $e');
      return null;
    }
  }

  static Future<bool> _uploadBackupToCloud(
    String localFilePath,
    String filename,
  ) async {
    final subscription = DatabaseService.subscriptionVersion.value;
    if (subscription == 'Free') {
      return false;
    }

    final bucketRaw = (dotenv.env['S3_BUCKET'] ?? '').trim();
    if (bucketRaw.isEmpty) {
      debugPrint('Skipping cloud backup: S3_BUCKET is not configured');
      return false;
    }

    final signedIn = await CognitoService.isSignedIn();
    if (!signedIn) {
      debugPrint('Skipping cloud backup: user not signed in');
      return false;
    }

    final userId = await UserAuthService.getCurrentUserId();
    if (userId.isEmpty) {
      debugPrint('Skipping cloud backup: missing userId');
      return false;
    }

    final key = 'backups/$userId/auto/$filename';
    final latestKey = 'backups/$userId/auto/latest.json';

    final uploaded = await AmplifyService.uploadFile(localFilePath, key);
    if (!uploaded) return false;

    await AmplifyService.uploadFile(localFilePath, latestKey);
    await DatabaseService.setSetting('lastCloudBackupKey', key);
    await DatabaseService.setSetting(
      'lastCloudBackupAt',
      DateTime.now().toIso8601String(),
    );
    return true;
  }

  static Future<void> checkAndRunIfDue() async {
    try {
      final subscription = DatabaseService.subscriptionVersion.value;
      if (subscription == 'Free') {
        debugPrint(
          'Skipping backup check: Free plan users do not have automatic backups',
        );
        return;
      }

      final enabled =
          DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;
      if (!enabled) return;

      final lastRaw =
          DatabaseService.getSetting<String>('lastAutoBackupAt', null);

      DateTime? last;
      if (lastRaw != null) {
        try {
          last = DateTime.parse(lastRaw);
        } catch (_) {
          last = null;
        }
      }

      const threshold = Duration(days: 1);
      final now = DateTime.now();
      if (last == null || now.difference(last) >= threshold) {
        await performBackup();
      }
    } catch (e) {
      debugPrint('checkAndRunIfDue failed: $e');
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  wm.Workmanager().executeTask((task, inputData) async {
    debugPrint('Workmanager executing task: $task');
    if (task == _workManagerTask) {
      try {
        await DatabaseService.init();

        final subscription = DatabaseService.subscriptionVersion.value;
        debugPrint(
          'Workmanager background subscriptionVersion = $subscription',
        );
        if (subscription == 'Free') {
          debugPrint(
            'Skipping backup: Free plan users do not have automatic backups',
          );
          return Future.value(true);
        }

        final enabled =
            DatabaseService.getSetting<bool>('autoBackupEnabled', false) ??
                false;
        if (!enabled) {
          debugPrint('Skipping backup: Automatic backups are disabled');
          return Future.value(true);
        }

        await AutoBackupService.performBackup();
      } catch (e) {
        debugPrint('callbackDispatcher performBackup error: $e');
      }
    }
    return Future.value(true);
  });
}

@pragma('vm:entry-point')
Future<void> _onBackgroundFetch(String taskId) async {
  try {
    await DatabaseService.init();

    final subscription = DatabaseService.subscriptionVersion.value;
    debugPrint('[BackgroundFetch] subscriptionVersion = $subscription');
    if (subscription == 'Free') {
      debugPrint(
        'Skipping backup: Free plan users do not have automatic backups',
      );
      bf.BackgroundFetch.finish(taskId);
      return;
    }

    final enabled =
        DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;
    if (!enabled) {
      debugPrint('Skipping backup: Automatic backups are disabled');
      bf.BackgroundFetch.finish(taskId);
      return;
    }

    await AutoBackupService.checkAndRunIfDue();
  } catch (e) {
    debugPrint('BackgroundFetch handler failed: $e');
  }
  bf.BackgroundFetch.finish(taskId);
}
