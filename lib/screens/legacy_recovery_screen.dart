import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import '../services/account_session_service.dart';

/// Optional local recovery, opened explicitly from Settings; never at startup.
class LegacyRecoveryScreen extends StatefulWidget {
  const LegacyRecoveryScreen({super.key});
  @override
  State<LegacyRecoveryScreen> createState() => _LegacyRecoveryScreenState();
}

class _LegacyRecoveryScreenState extends State<LegacyRecoveryScreen> {
  final _emailInput = TextEditingController();
  String? _key;
  String _email = '';
  String? _error;
  bool _confirmed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    try {
      final key = await AccountSessionService.currentKey();
      final attributes = await Amplify.Auth.fetchUserAttributes();
      final email = attributes
          .where((a) => a.userAttributeKey == AuthUserAttributeKey.email)
          .map((a) => a.value).join();
      if (!mounted) { return; }
      setState(() { _key = key; _email = email; });
    } catch (e) {
      if (mounted) { setState(() => _error = 'Sign in to recover your previous records.'); }
    }
  }

  Future<void> _recover() async {
    final key = _key;
    if (_busy || key == null || !_confirmed || _email.isEmpty ||
        _emailInput.text.trim().toLowerCase() != _email.toLowerCase()) { return; }
    setState(() { _busy = true; _error = null; });
    try {
      await AccountSessionService.recoverLegacyForCurrentAccount(key);
    } catch (e) {
      if (mounted) { setState(() { _busy = false; _error = e.toString(); }); }
    }
  }

  @override
  void dispose() { _emailInput.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recover previous local records')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      Text('Signed in as: $_email'),
      const SizedBox(height: 16),
      const Text('Previous records on this device have not been assigned to an account. '
          'Recover them only if they belong to you. This uses local files and does not require Premium.'),
      const SizedBox(height: 16),
      const Text('Recovery replaces the records currently shown for this account. '
          'The current profile is preserved separately for support recovery; records are not merged. '
          'Original files and other accounts remain intact.'),
      const SizedBox(height: 16),
      TextField(controller: _emailInput, enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Confirm your account email'),
        onChanged: (_) => setState(() {})),
      CheckboxListTile(value: _confirmed,
        onChanged: _busy ? null : (v) => setState(() => _confirmed = v ?? false),
        title: const Text('The previous local records belong to this account.')),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ElevatedButton(
        onPressed: !_busy && _key != null && _confirmed && _email.isNotEmpty &&
            _emailInput.text.trim().toLowerCase() == _email.toLowerCase() ? _recover : null,
        child: Text(_busy ? 'Recovering…' : 'Recover local records')),
    ]),
  );
}
