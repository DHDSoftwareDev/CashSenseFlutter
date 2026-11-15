import 'dart:async';
import 'dart:io';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'account_storage.dart';
import 'account_operations.dart';
import 'database_service.dart';
import 'billing_service.dart';
import 'push_token_service.dart';
import 'bill_reminder_service.dart';
import 'user_auth_service.dart';
import 'home_screen_widget_service.dart';

class AccountSessionService {
  static String? _openedKey;
  static String? _preparedKey;
  static Future<void>? _transition;
  static bool _managedAuthChange = false;
  static bool _watching = false;
  static Future<void> Function()? onProfileOpened;
  static void Function()? onProfileClosing;

  static Future<String> currentKey() async {
    final session = await Amplify.Auth.fetchAuthSession();
    if (!session.isSignedIn) { return AccountStorage.keyFor(null); }
    final user = await Amplify.Auth.getCurrentUser();
    if (user.userId.trim().isEmpty) { throw StateError('Missing authenticated account.'); }
    return AccountStorage.keyFor(user.userId);
  }

  /// Called before changing Cognito, while outstanding work still has its
  /// original credentials. Authentication is never changed until it drains.
  static Future<void> beginAuthChange() async {
    if (_managedAuthChange || _transition != null) {
      throw StateError('An account change is already in progress.');
    }
    _managedAuthChange = true;
    try {
      await _pauseAccountWork();
    } catch (_) {
      _managedAuthChange = false;
      await _resumeAccountWork();
      rethrow;
    }
  }

  static Future<void> _pauseAccountWork() async {
    AccountOperations.pause();
    await BillingService.pauseForAccountChange();
    await PushTokenService.pauseForAccountChange();
    await HomeScreenWidgetService.lockForAccountChange();
    await AccountOperations.drain();
  }

  static Future<void> _resumeAccountWork() async {
    AccountOperations.resume();
    await HomeScreenWidgetService.resumeForAccount();
    try { await BillingService.init(); } catch (e) {
      debugPrint('Billing will retry initialization: $e');
    }
    BillingService.resumePendingPurchases();
  }

  static Future<void> finishAuthChange() async {
    try {
      await enforceCurrentAccount();
    } finally {
      _managedAuthChange = false;
    }
  }

  static Future<void> enforceCurrentAccount({bool force = false}) {
    final running = _transition;
    if (running != null) { return running; }
    // Publish the flight before the first authentication read can yield.
    final done = Completer<void>();
    final task = done.future;
    _transition = task;
    unawaited(() async {
      try {
        if (!force && await currentKey() == _openedKey) {
          if (AccountOperations.paused) { await _resumeAccountWork(); }
        } else {
          await _switchProfile();
        }
        done.complete();
      } catch (e, stack) {
        done.completeError(e, stack);
      } finally {
        _transition = null;
      }
    }());
    return task;
  }

  static Future<void> _switchProfile() async {
    try {
      await _pauseAccountWork();
      // Remove all routes and providers before closing their Hive boxes.
      runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: Center(
        child: CircularProgressIndicator(),
      ))));
      await WidgetsBinding.instance.endOfFrame;
      onProfileClosing?.call();
      onProfileClosing = null;
      await DatabaseService.closeForAccountChange();
      AccountOperations.nextGeneration();
      final profile = await prepare();
      await AccountOperations.maintain(() =>
        DatabaseService.init(accountDirectory: profile.path),
      );
      await markProfileOpened();
      BillReminderService().resetForAccountChange();
      AccountOperations.resume();
      final mount = onProfileOpened;
      if (mount == null) { throw StateError('Account UI is unavailable.'); }
      await mount();
      await HomeScreenWidgetService.resumeForAccount();
      BillingService.resumePendingPurchases();
    } catch (e, stack) {
      debugPrint('Account transition stopped: $e');
      debugPrintStack(stackTrace: stack);
      AccountOperations.pause();
      _showTransitionFailure();
      rethrow;
    }
  }

  static void _showTransitionFailure() {
    runApp(MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24), child: Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('CashSense could not finish switching accounts. Your saved records have been kept.',
            textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () async {
            try { await enforceCurrentAccount(force: true); } catch (_) {}
          }, child: const Text('Try again')),
        ],
      )),
    )))));
  }

  static void watchSession() {
    if (_watching) { return; }
    _watching = true;
    Amplify.Hub.listen(HubChannel.Auth, (AuthHubEvent event) {
      if (!_managedAuthChange && (event.type == AuthHubEventType.signedIn ||
          event.type == AuthHubEventType.signedOut ||
          event.type == AuthHubEventType.sessionExpired)) {
        unawaited(enforceCurrentAccount().catchError((Object e) {
          debugPrint('Authentication transition failed: $e');
        }));
      }
    });
  }

  static Future<Directory> prepare() async {
    if (!Amplify.isConfigured) { throw StateError('Authentication is unavailable. Existing data was kept.'); }
    final key = await currentKey();
    final support = await getApplicationSupportDirectory();
    final store = AccountStorage(Directory('${support.path}/cashsense_accounts'));
    final legacy = Directory('${support.path}/.hive');
    final oldLegacy = Directory('${(await getApplicationDocumentsDirectory()).path}/CashSense/.hive');
    final original = await legacy.exists() ? legacy : oldLegacy;
    final recovery = File('${support.path}/cashsense_restore_recovery.json');
    final journal = await store.readBinding();
    if (journal != null && journal['owner'] == key && journal['state'] == 'copying') {
      await store.claim(key, original, recovery);
    } else if (journal == null && key != AccountStorage.keyFor(null) &&
        !await store.profile(key).exists() && await original.exists()) {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      final email = attributes.where((a) => a.userAttributeKey == AuthUserAttributeKey.email)
          .map((a) => a.value).join();
      final answer = Completer<bool>();
      runApp(MaterialApp(debugShowCheckedModeBanner: false, home: _OriginalDataChoice(email: email, answer: answer)));
      if (await answer.future) {
        // Fetch again after the prompt so a changed session cannot claim data.
        if (await currentKey() != key) { throw StateError('Account changed during recovery.'); }
        await store.claim(key, original, recovery);
      }
    }
    if (await currentKey() != key) { throw StateError('Account changed during startup.'); }
    if (key != AccountStorage.keyFor(null)) {
      final user = await Amplify.Auth.getCurrentUser();
      if (await UserAuthService.getCurrentUserId() != user.userId) {
        await UserAuthService.logout();
      }
      final attributes = await Amplify.Auth.fetchUserAttributes();
      String attribute(AuthUserAttributeKey field) => attributes
          .where((a) => a.userAttributeKey == field).map((a) => a.value).join();
      await UserAuthService.saveUserInfo(userId: user.userId,
        email: attribute(AuthUserAttributeKey.email),
        displayName: attribute(AuthUserAttributeKey.name));
    } else {
      await UserAuthService.logout();
    }
    _preparedKey = key;
    final profile = store.profile(key);
    await profile.create(recursive: true);
    return profile;
  }

  static Future<void> markProfileOpened() async {
    if (_preparedKey == null || await currentKey() != _preparedKey) {
      throw StateError('Authentication changed while opening account storage.');
    }
    _openedKey = _preparedKey;
  }

  static void showStartupFailure() {
    runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: SafeArea(child: Padding(
      padding: EdgeInsets.all(24), child: Center(child: Text(
        'CashSense could not safely open this account. Your existing files were kept. Close the app and contact support before clearing data or reinstalling.',
        textAlign: TextAlign.center,
      )),
    )))));
  }
}

class _OriginalDataChoice extends StatefulWidget {
  final String email;
  final Completer<bool> answer;
  const _OriginalDataChoice({required this.email, required this.answer});
  @override
  State<_OriginalDataChoice> createState() => _OriginalDataChoiceState();
}

class _OriginalDataChoiceState extends State<_OriginalDataChoice> {
  final _email = TextEditingController();
  bool _confirmed = false;
  @override
  void dispose() { _email.dispose(); super.dispose(); }
  void _finish(bool claim) {
    if (!widget.answer.isCompleted) { widget.answer.complete(claim); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Protect original account data')),
    body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Signed in as: ${widget.email}'),
        const SizedBox(height: 16),
        const Text('Previous local records have been preserved. Recover them only if they belong to the account shown above. Otherwise, keep them reserved for their owner.'),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: () => _finish(false), child: const Text('Keep original records reserved')),
        const SizedBox(height: 24),
        const Text('Only for the original account: confirm ownership and enter its email to copy the preserved records. The original files will be kept.'),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Original account email'),
          onChanged: (_) => setState(() {})),
        CheckboxListTile(value: _confirmed, onChanged: (value) => setState(() => _confirmed = value ?? false),
          title: const Text('These existing records belong to the account signed in above.')),
        ElevatedButton(onPressed: _confirmed && widget.email.isNotEmpty &&
            _email.text.trim().toLowerCase() == widget.email.trim().toLowerCase()
            ? () => _finish(true) : null,
          child: const Text('Recover original account records')),
      ],
    ))),
  );
}
