// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:async';
import '../lib/services/account_operations.dart';

Future<void> expectRejected(Future<void> Function() action) async {
  try { await action(); } on StateError { return; }
  throw StateError('Expected stale or paused work to be rejected.');
}

Future<void> main() async {
  var checks = 0;
  void pass(String name) { checks++; print('PASS: $name'); }
  final release = Completer<void>();
  final started = Completer<void>();
  var nestedFinished = false;
  final work = AccountOperations.run(() async {
    started.complete();
    await release.future;
    await AccountOperations.run(() async { nestedFinished = true; });
  });
  await started.future;
  AccountOperations.pause();
  await expectRejected(() => AccountOperations.run(() async {}));
  pass('New operations blocked while switching');
  var drained = false;
  final drain = AccountOperations.drain().then((_) { drained = true; });
  await Future<void>.delayed(Duration.zero);
  if (drained) { throw StateError('Drain returned before pending work finished.'); }
  release.complete();
  await work;
  await drain;
  if (!nestedFinished) { throw StateError('Nested work failed to finish.'); }
  pass('Drain waits for existing and nested operations');
  AccountOperations.nextGeneration();
  AccountOperations.resume();

  final oldGeneration = AccountOperations.generation;
  final uiWait = Completer<void>();
  final uiStarted = Completer<void>();
  var staleWrites = 0;
  final ui = AccountOperations.bind(oldGeneration, () async {
    uiStarted.complete();
    await uiWait.future;
    await AccountOperations.run(() async { staleWrites++; });
  });
  final uiRejected = expectRejected(() => ui);
  await uiStarted.future;
  AccountOperations.pause();
  await AccountOperations.drain();
  pass('A waiting screen does not block account switching');
  AccountOperations.nextGeneration();
  AccountOperations.resume();
  uiWait.complete();
  await uiRejected;
  if (staleWrites != 0) { throw StateError('Old UI wrote into the new account.'); }
  pass('Old screen continuation cannot write to the next account');
  await expectRejected(() => AccountOperations.bind(oldGeneration, () async {}));
  pass('Old screen callbacks rejected after switching');

  final sameGeneration = AccountOperations.generation;
  AccountOperations.pause();
  await AccountOperations.drain();
  AccountOperations.resume();
  if (sameGeneration != AccountOperations.generation) {
    throw StateError('Failed authentication should preserve the current generation.');
  }
  await AccountOperations.run(() async {});
  pass('Aborted authentication resumes the existing account');

  final delayedResult = Completer<bool>();
  final delayedGate = Completer<void>();
  await AccountOperations.run(() async {
    unawaited(() async {
      await delayedGate.future;
      try {
        await AccountOperations.run(() async {});
        delayedResult.complete(false);
      } on StateError { delayedResult.complete(true); }
    }());
  });
  delayedGate.complete();
  if (!await delayedResult.future) {
    throw StateError('Delayed work inherited a completed operation.');
  }
  pass('Delayed work from a completed operation is rejected');

  await expectRejected(() => AccountOperations.run<void>(() async {
    throw StateError('Synthetic failure');
  }));
  AccountOperations.pause();
  await AccountOperations.drain();
  AccountOperations.nextGeneration();
  await AccountOperations.maintain(() => AccountOperations.run(() async {}));
  AccountOperations.resume();
  pass('Failed operations release the barrier and maintenance can open a profile');
  print('$checks transition checks passed (coordinator only; no Hive, Cognito or device test).');
}
