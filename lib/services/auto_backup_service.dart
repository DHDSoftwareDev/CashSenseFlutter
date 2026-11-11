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

class AutoBackupService {
  static Future<void> initialize() async {
    // Automatic backups were retired. Cancel legacy jobs so users who had
    // enabled the old setting do not continue uploading in the background.
    if (Platform.isAndroid) {
      try {
        await wm.Workmanager().initialize(callbackDispatcher);
        await wm.Workmanager().cancelByUniqueName(
          'cashsense_auto_backup_periodic',
        );
      } catch (e) {
        debugPrint('Failed to cancel legacy Android auto backup: $e');
      }
    }

    try {
      await bf.BackgroundFetch.stop();
    } catch (e) {
      debugPrint('Failed to stop legacy background backup fetch: $e');
    }

    await DatabaseService.setSetting('autoBackupEnabled', false);
  }

  static Future<String?> buildBackupJsonString() async {
    try {
      final transactions = DatabaseService.getAllTransactions();
      final categories = DatabaseService.getAllCategories();
      final accounts = DatabaseService.getAllAccountsForBackup();
      final bills = DatabaseService.getAllBills();
      final settings = DatabaseService.exportAllSettings();
    final billOccurrences = DatabaseService.exportBillOccurrenceStatuses();

final allContacts = DatabaseService.getAllPayees();

final payees = allContacts.where((contact) {
  return (contact['type'] ?? '')
          .toString()
          .trim()
          .toLowerCase() ==
      'payee';
}).toList();

final payers = allContacts.where((contact) {
  return (contact['type'] ?? '')
          .toString()
          .trim()
          .toLowerCase() ==
      'payer';
}).toList();

      final backupData = {
        'version': '1.1.0',
        'timestamp': DateTime.now().toIso8601String(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
      'accounts': accounts
    .map(
      (a) => {
        'id': a.id,
        'name': a.name,
        'type': a.type.name,
        'balance': a.balance,
        'initialBalance': DatabaseService.getInitialBalance(a.id),
        'isActive': a.isActive,
        'currency': a.currency,
        'description': a.description,
        'institution': a.institution,
        'accountNumber': a.accountNumber,
        'cardNumber': a.cardNumber,
        'availableBalance': a.availableBalance,
        'customType': a.customType,
      },
    )
    .toList(),
        'bills': bills.map((b) => b.toJson()).toList(),
       'payees': payees,
'payers': payers,
'settings': settings,
'bill_occurrence_status': billOccurrences,
      };

      return const JsonEncoder.withIndent('  ').convert(backupData);
    } catch (e) {
      debugPrint('buildBackupJsonString failed: $e');
      return null;
    }
  }

  static Future<bool> backupToCloud() async {
    File? tempFile;
    try {
      final subscription = DatabaseService.subscriptionVersion.value;
      if (subscription == 'Free') {
        debugPrint(
          'Skipping manual cloud backup: premium subscription required',
        );
        return false;
      }

      final jsonString = await buildBackupJsonString();
      if (jsonString == null) {
        debugPrint(
          'Manual cloud backup failed: buildBackupJsonString returned null',
        );
        return false;
      }

      final tmpDir = await getTemporaryDirectory();
      final timestamp = DateFormat(
        'yyyy-MM-dd_HH-mm-ss',
      ).format(DateTime.now());
      final filename = 'cashsense_cloud_backup_$timestamp.json';
      tempFile = File('${tmpDir.path}/$filename');
      await tempFile.writeAsString(jsonString);

      final uploaded = await _uploadBackupToCloud(tempFile.path, filename);
      if (uploaded) {
        await DatabaseService.setSetting(
          'lastManualCloudBackupAt',
          DateTime.now().toIso8601String(),
        );
      }
      return uploaded;
    } catch (e) {
      debugPrint('Manual cloud backup failed: $e');
      return false;
    } finally {
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }
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

   final uploaded = await AmplifyService.uploadFile(
  localFilePath,
  key,
);

if (!uploaded) {
  debugPrint('Cloud backup failed: timestamped upload failed');
  return false;
}

final latestUploaded = await AmplifyService.uploadFile(
  localFilePath,
  latestKey,
);

if (!latestUploaded) {
  debugPrint(
    'Cloud backup failed: latest.json upload failed. '
    'Timestamped backup was uploaded successfully.',
  );
  return false;
}

await DatabaseService.setSetting(
  'lastCloudBackupKey',
  key,
);

await DatabaseService.setSetting(
  'lastCloudBackupAt',
  DateTime.now().toIso8601String(),
);

debugPrint('Cloud backup successfully uploaded: $latestKey');

return true;
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  wm.Workmanager().executeTask((task, inputData) async => true);
}
