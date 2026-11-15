// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:convert';
import 'dart:io';
import '../lib/services/account_storage.dart';

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('cashsense-isolation-check-');
  var passed = 0;
  void check(bool condition, String label) {
    if (!condition) { throw StateError('FAIL: $label'); }
    passed++;
    print('PASS: $label');
  }
  try {
    final a = AccountStorage.keyFor('synthetic-original');
    final b = AccountStorage.keyFor('synthetic-new');
    check(a != b && a != AccountStorage.keyFor(null), 'Distinct account and signed-out keys');
    check(a == AccountStorage.keyFor('synthetic-original'), 'Stable account key');
    final legacy = await Directory('${temp.path}/legacy').create();
    final transactions = File('${legacy.path}/transactions.hive');
    final settings = File('${legacy.path}/settings.hive');
    await transactions.writeAsString('synthetic original transactions');
    await settings.writeAsString('synthetic original settings');
    final recovery = File('${temp.path}/cashsense_restore_recovery.json');
    await recovery.writeAsString('synthetic recovery bytes');
    final store = AccountStorage(Directory('${temp.path}/scoped'));
    await store.claim(a, legacy, recovery);
    check(await transactions.readAsString() == 'synthetic original transactions', 'Original files retained unchanged');
    check(await File('${store.profile(a).path}/.hive/transactions.hive').readAsString() ==
        await transactions.readAsString(), 'Original account gets byte-identical copy');
    check(!await store.profile(b).exists(), 'New account receives no original files');
    check(await File('${store.profile(a).path}/cashsense_restore_recovery.json').readAsString() ==
        await recovery.readAsString(), 'Recovery file stays with original account');
    var denied = false;
    try { await store.claim(b, legacy, recovery); } on StateError { denied = true; }
    check(denied, 'Another account cannot claim bound original records');
    final journal = await store.readBinding();
    journal!['state'] = 'copying';
    await store.binding.writeAsString(jsonEncode(journal), flush: true);
    await store.claim(a, legacy, recovery);
    check((await store.readBinding())!['state'] == 'complete', 'Interrupted finalization resumes after verifying copied files');
    await File('${store.profile(a).path}/.hive/transactions.hive').writeAsString('synthetic original edit');
    await store.claim(a, legacy, recovery);
    check(await File('${store.profile(a).path}/.hive/transactions.hive').readAsString() ==
        'synthetic original edit', 'Repeat claim never overwrites active account data');
    final otherStore = AccountStorage(Directory('${temp.path}/other'));
    await otherStore.profile(a).create(recursive: true);
    denied = false;
    try { await otherStore.claim(a, legacy, recovery); } on StateError { denied = true; }
    check(denied, 'Existing destination is never overwritten');
    check(await recovery.exists() && await settings.exists(), 'Legacy recovery and settings remain available');
    print('$passed account storage checks passed (synthetic files, not Hive or device tests).');
  } finally {
    await temp.delete(recursive: true);
  }
}
