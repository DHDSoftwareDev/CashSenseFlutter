// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:io';
import 'dart:convert';
import '../lib/services/account_storage.dart';

Future<void> main() async {
  final temporary = await Directory.systemTemp.createTemp('cashsense_migration_check_');
  var checks = 0;
  void verify(bool value, String label) {
    if (!value) { throw StateError(label); }
    checks++; print('PASS: $label');
  }
  try {
    final store = AccountStorage(Directory('${temporary.path}/store'));
    final legacy = Directory('${temporary.path}/old');
    await legacy.create();
    await File('${legacy.path}/transactions.hive').writeAsString('original records');
    final recovery = File('${temporary.path}/old_recovery.json');
    await recovery.writeAsString('original recovery');
    final owner = AccountStorage.keyFor('original-owner');
    final other = AccountStorage.keyFor('another-user');
    final current = store.profile(owner);
    await Directory('${current.path}/.hive').create(recursive: true);
    await File('${current.path}/.hive/transactions.hive').writeAsString('new profile records');
    await store.completeAuthorizedRecovery(owner, legacy, recovery);
    verify(await store.readBinding() == null &&
        await File('${current.path}/.hive/transactions.hive').readAsString() == 'new profile records',
        'Unassigned files are not automatically claimed or overwritten');
    await store.authorizeRecovery(owner);
    await store.completeAuthorizedRecovery(other, legacy, recovery);
    verify(!await store.profile(other).exists() && await store.readBinding() == null,
        'Another account cannot execute the confirmed recovery');
    await store.completeAuthorizedRecovery(owner, legacy, recovery);
    verify(await File('${current.path}/.hive/transactions.hive').readAsString() == 'original records',
        'Confirmed owner receives the original records');
    final archiveRoot = Directory('${store.root.path}/preserved_profiles/$owner');
    final archives = await archiveRoot.list().toList();
    verify(archives.length == 1 &&
        await File('${archives.single.path}/.hive/transactions.hive').readAsString() == 'new profile records',
        'Existing account records are archived before recovery');
    verify(await File('${legacy.path}/transactions.hive').readAsString() == 'original records' &&
        await recovery.readAsString() == 'original recovery', 'Original database and recovery files remain untouched');
    verify((await store.readBinding())?['state'] == 'complete', 'Completed recovery records durable ownership');
    await store.completeAuthorizedRecovery(owner, legacy, recovery);
    verify((await archiveRoot.list().toList()).length == 1, 'Repeat startup does not archive or recover again');

    // Simulate interruption after archiving, before claim starts.
    final second = AccountStorage(Directory('${temporary.path}/interrupted'));
    await second.profile(owner).create(recursive: true);
    await File('${second.profile(owner).path}/kept').writeAsString('kept');
    await second.authorizeRecovery(owner);
    final requestFile = File('${second.root.path}/legacy_recovery_request.json');
    final request = jsonDecode(await requestFile.readAsString()) as Map;
    final archive = Directory('${second.root.path}/preserved_profiles/$owner/${request['archive']}');
    await archive.parent.create(recursive: true);
    await second.profile(owner).rename(archive.path);
    await second.completeAuthorizedRecovery(owner, legacy, recovery);
    verify(await File('${archive.path}/kept').readAsString() == 'kept' &&
        (await second.readBinding())?['state'] == 'complete',
        'Recovery resumes after interruption without losing the archived profile');
    print('$checks migration checks passed (synthetic files; no Hive or device test).');
  } finally { await temporary.delete(recursive: true); }
}
