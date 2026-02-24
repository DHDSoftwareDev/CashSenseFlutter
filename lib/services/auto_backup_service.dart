import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart' as wm;
import 'package:background_fetch/background_fetch.dart' as bf;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'database_service.dart';
import 'amplify_service.dart';
import 'cognito_service.dart';
import 'user_auth_service.dart';

const String _workManagerTask = 'cashsense_auto_backup';

class AutoBackupService {
  /// Initialize background schedulers. Call from `main()` after DB init.
  static Future<void> initialize() async {
    debugPrint('AutoBackupService.initialize() starting...');
    
    // ANDROID: Workmanager for periodic background tasks
    if (Platform.isAndroid) {
      try {
        debugPrint('Initializing Workmanager for Android...');
        await wm.Workmanager().initialize(
          callbackDispatcher,
        );
        debugPrint('Workmanager initialized successfully');
      } catch (e) {
        debugPrint('Workmanager initialize failed: $e');
      }

      // Configure periodic task from settings (enabled/disabled)
      try {
        await configurePeriodicTaskFromSettings();
      } catch (e) {
        debugPrint('configurePeriodicTaskFromSettings failed: $e');
      }
    }

    // BackgroundFetch for iOS (and can also be used on Android as fallback)
    try {
      debugPrint('Configuring BackgroundFetch...');
      await bf.BackgroundFetch.configure(
        bf.BackgroundFetchConfig(
          minimumFetchInterval: 15, // minutes; iOS decides actual frequency
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
      
      // Get the status to verify configuration
      final status = await bf.BackgroundFetch.status;
      debugPrint('BackgroundFetch configured successfully. Status: $status');
      // Status meanings: 0=restricted, 1=denied, 2=available
      
      if (Platform.isIOS) {
        // On iOS, we need to explicitly start BackgroundFetch
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

  /// Configure (register or cancel) the Workmanager periodic task based on
  /// current user settings (autoBackupEnabled). Android only.
  static Future<void> configurePeriodicTaskFromSettings() async {
    // Only relevant on Android; skip on iOS/other
    if (!Platform.isAndroid) {
      debugPrint('configurePeriodicTaskFromSettings: skipping Workmanager on non-Android platform');
      return;
    }

    try {
      final enabled = DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;

      // Cancel any existing periodic task with the unique name
      try {
        await wm.Workmanager().cancelByUniqueName('cashsense_auto_backup_periodic');
      } catch (e) {
        // ignore cancellation errors
      }

      if (!enabled) {
        debugPrint('Automatic backups disabled; periodic task cancelled');
        return;
      }

      // Use a fixed daily period for automatic backups on Android
      const Duration registerPeriod = Duration(days: 1);

      // Compute an initial delay so backups start at the next local midnight.
      Duration initialDelay = const Duration(minutes: 1);
      try {
        final now = DateTime.now();
        final nextMidnight = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        final diffToNextMidnight = nextMidnight.difference(now);
        if (!diffToNextMidnight.isNegative) {
          initialDelay = diffToNextMidnight;
        }
      } catch (e) {
        // Fallback to short delay on error
        initialDelay = const Duration(minutes: 1);
      }

      debugPrint('Registering auto-backup: period=$registerPeriod, initialDelay=${initialDelay.inSeconds}s');

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

  /// Build and return the JSON string for a backup without writing to disk.
  static Future<String?> buildBackupJsonString() async {
    try {
      final transactions = DatabaseService.getAllTransactions();
      final categories = DatabaseService.getAllCategories();
      final accounts = DatabaseService.getAllAccounts();
      final bills = DatabaseService.getAllBills();
      // Export settings and bill occurrence statuses as well
      final settings = DatabaseService.exportAllSettings();
      final billOccurrences = DatabaseService.exportBillOccurrenceStatuses();
      final payees = DatabaseService.getAllPayees();

      final backupData = {
        'version': '1.0.0',
        'timestamp': DateTime.now().toIso8601String(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'accounts': accounts.map((a) => {
          'id': a.id,
          'name': a.name,
          'type': a.type.toString().split('.').last,
          'balance': a.balance,
          'isActive': a.isActive,
          'currency': a.currency,
          'description': a.description,
          'accountNumber': a.accountNumber,
          'availableBalance': a.availableBalance,
          'customType': a.customType,
        }).toList(),
        'bills': bills.map((b) => {
          'id': b.id,
          'amount': b.amount,
          'description': b.description,
          'dueDate': b.dueDate.toIso8601String(),
          'recurrence': b.recurrence.toString().split('.').last,
          'recurrenceInterval': b.recurrenceInterval,
          'recurrenceWeekdays': b.recurrenceWeekdays,
          'customDays': b.customDays,
          'recurrenceEndDate': b.recurrenceEndDate?.toIso8601String(),
          'categoryId': b.categoryId,
          'type': b.type.toString().split('.').last,
          'isPaid': b.isPaid,
          'paymentStatus': b.paymentStatus?.toString().split('.').last,
          'payeeId': b.payeeId,
          'accountId': b.accountId,
          'fromAccountId': b.fromAccountId,
          'toAccountId': b.toAccountId,
        }).toList(),
        'payees': payees,
        'settings': settings,
        'bill_occurrence_status': billOccurrences,
        'payments_history': billOccurrences,
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      return jsonString;
    } catch (e) {
      debugPrint('buildBackupJsonString failed: $e');
      return null;
    }
  }

  /// Perform the actual backup to both local file and AWS S3 (used by automatic/background backups).
  static Future<String?> performBackup() async {
    try {
      debugPrint('performBackup() starting...');
      final jsonString = await buildBackupJsonString();
      if (jsonString == null) {
        debugPrint('performBackup() failed: buildBackupJsonString returned null');
        return null;
      }

      // Use appropriate directory based on platform
      Directory baseDir;
      if (Platform.isIOS) {
        // iOS: Use app's documents directory since Downloads is not accessible
        final docsDir = await getApplicationDocumentsDirectory();
        baseDir = Directory('${docsDir.path}/CashSense');
      } else {
        // Android/Desktop: Use Downloads directory
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
      // Filename-safe timestamp: M-d-yy_h-mm_a -> e.g. 11-6-25_3-15_pm
      final filenameTimestamp = DateFormat('M-d-yy_h-mm_a').format(now).toLowerCase();
      final filename = 'cashsense_auto_backup_$filenameTimestamp.json';
      final file = File('${baseDir.path}/$filename');
      await file.writeAsString(jsonString);
      debugPrint('Backup file written: ${file.path}');

      // Persist last auto-backup timestamp so the app can inspect it
      await DatabaseService.setSetting('lastAutoBackupAt', DateTime.now().toIso8601String());
      debugPrint('lastAutoBackupAt setting updated');

      debugPrint('Auto backup written: ${file.path}');

      // Maintain at most 3 automatic backup files.
      try {
        final files = Directory(baseDir.path)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.split('/').last.startsWith('cashsense_auto_backup_') && f.path.endsWith('.json'))
            .toList();

        // Sort by last modified ascending (oldest first)
        files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

        // Delete oldest files if more than 3 exist
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

      // Upload to AWS S3 for premium users when configured.
      try {
        final uploaded = await _uploadBackupToCloud(file.path, filename);
        debugPrint(uploaded
            ? 'Cloud S3 backup upload complete.'
            : 'Cloud S3 backup upload skipped/failed.');
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

  static Future<bool> _uploadBackupToCloud(String localFilePath, String filename) async {
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

    // Also maintain a stable latest object for easier restore workflows.
    await AmplifyService.uploadFile(localFilePath, latestKey);
    await DatabaseService.setSetting('lastCloudBackupKey', key);
    await DatabaseService.setSetting('lastCloudBackupAt', DateTime.now().toIso8601String());
    return true;
  }

  /// Optional helper: check settings and run backup if enabled and at least
  /// one day has passed since the last auto-backup.
  static Future<void> checkAndRunIfDue() async {
    try {
      // Only backup for premium users
      final subscription = DatabaseService.subscriptionVersion.value;
      if (subscription == 'Free') {
        debugPrint('Skipping backup check: Free plan users do not have automatic backups');
        return;
      }

      final enabled = DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;
      if (!enabled) return;

      final lastRaw = DatabaseService.getSetting<String>('lastAutoBackupAt', null);
      DateTime? last;
      if (lastRaw != null) {
        try {
          last = DateTime.parse(lastRaw);
        } catch (_) {
          last = null;
        }
      }

      // Fixed threshold: once per day
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

/// Workmanager callback (Android).
@pragma('vm:entry-point')
void callbackDispatcher() {
  wm.Workmanager().executeTask((task, inputData) async {
    debugPrint('Workmanager executing task: $task');
    if (task == _workManagerTask) {
      try {
        // Initialize database service in the background isolate
        await DatabaseService.init();

        // Check subscription status - only backup for premium users
        final subscription = DatabaseService.subscriptionVersion.value;
        debugPrint('Workmanager background subscriptionVersion = $subscription');
        if (subscription == 'Free') {
          debugPrint('Skipping backup: Free plan users do not have automatic backups');
          return Future.value(true);
        }

        // Check if auto-backup is enabled
        final enabled = DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;
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

/// BackgroundFetch handler
@pragma('vm:entry-point')
Future<void> _onBackgroundFetch(String taskId) async {
  try {
    // Initialize database service in the background isolate
    await DatabaseService.init();

    // Check subscription status - only backup for premium users
    final subscription = DatabaseService.subscriptionVersion.value;
    debugPrint('[BackgroundFetch] subscriptionVersion = $subscription');
    if (subscription == 'Free') {
      debugPrint('Skipping backup: Free plan users do not have automatic backups');
      bf.BackgroundFetch.finish(taskId);
      return;
    }

    // Check if auto-backup is enabled
    final enabled = DatabaseService.getSetting<bool>('autoBackupEnabled', false) ?? false;
    if (!enabled) {
      debugPrint('Skipping backup: Automatic backups are disabled');
      bf.BackgroundFetch.finish(taskId);
      return;
    }

    // Either run directly or use checkAndRunIfDue() if you want the 1-day threshold:
    await AutoBackupService.checkAndRunIfDue();
  } catch (e) {
    debugPrint('BackgroundFetch handler failed: $e');
  }
  bf.BackgroundFetch.finish(taskId);
}
