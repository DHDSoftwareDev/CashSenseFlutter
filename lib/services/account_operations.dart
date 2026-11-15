import 'dart:async';

/// Drains account work before changing authentication or opening another profile.
/// A zone lease keeps nested work together and rejects delayed work from an old
/// profile after the switch. No database files are deleted by this barrier.
class AccountOperations {
  static final Object _zoneKey = Object();
  static final Set<Future<void>> _pending = {};
  static bool _paused = false;
  static int _generation = 0;
  static int get generation => _generation;
  static bool get paused => _paused;

  static Future<T> run<T>(Future<T> Function() action) {
    final inherited = Zone.current[_zoneKey] as _AccountLease?;
    if (inherited != null) {
      if (!inherited.active || inherited.generation != _generation) {
        return Future<T>.error(StateError('This account session has ended.'));
      }
    }
    if (_paused && (inherited == null || !inherited.allowWhilePaused)) {
      return Future<T>.error(StateError('Account change in progress. Please wait.'));
    }
    final lease = _AccountLease(_generation, allowWhilePaused: true);
    final finished = Completer<void>();
    _pending.add(finished.future);
    return runZoned(() async {
      try {
        return await action();
      } finally {
        lease.active = false;
        _pending.remove(finished.future);
        finished.complete();
      }
    }, zoneValues: {_zoneKey: lease});
  }

  /// UI may wait for a dialog or route without delaying sign-out. Its lease
  /// still prevents that old screen from writing to a later account.
  static Future<T> bind<T>(int generation, Future<T> Function() action) async {
    if (generation != _generation || _paused) {
      throw StateError('This screen no longer belongs to the active account.');
    }
    final lease = _AccountLease(generation);
    try {
      return await runZoned(action, zoneValues: {_zoneKey: lease});
    } finally {
      lease.active = false;
    }
  }

  /// Long-lived platform subscriptions must not inherit a completed operation.
  static T outsideLease<T>(T Function() register) =>
      runZoned(register, zoneValues: {_zoneKey: null});

  static void pause() { _paused = true; }

  static Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_pending));
    }
  }

  static void nextGeneration() {
    if (!_paused || _pending.isNotEmpty) {
      throw StateError('Account work must finish before switching storage.');
    }
    _generation++;
  }

  static Future<T> maintain<T>(Future<T> Function() action) async {
    final lease = _AccountLease(_generation, allowWhilePaused: true);
    try {
      return await runZoned(action, zoneValues: {_zoneKey: lease});
    } finally {
      lease.active = false;
    }
  }

  static void resume() { _paused = false; }
}

class _AccountLease {
  final int generation;
  bool active = true;
  final bool allowWhilePaused;
  _AccountLease(this.generation, {this.allowWhilePaused = false});
}
