import '../services/account_operations.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/aws_api_service.dart';
import '../services/billing_service.dart';

/// Open from your signed-in app only in an explicitly configured staging build.
class BillingStagingScreen extends StatefulWidget {
  const BillingStagingScreen({super.key});
  @override
  State<BillingStagingScreen> createState() => _BillingStagingScreenState();
}

class _BillingStagingScreenState extends State<BillingStagingScreen> {
  final int _accountGeneration = AccountOperations.generation;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _timer;
  StreamSubscription<String>? _purchaseStatus;
  Map<String, dynamic>? _profile;
  String _message = 'Loading staging membership…';
  bool _busy = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    if (!BillingService.isStaging) {
      _message = 'Staging billing is disabled for this build.';
      return;
    }
    _subscription = BillingService.stagingProfiles.listen((profile) {
      if (mounted) {
        setState(() => _profile = profile);
      }
    });
    _purchaseStatus = BillingService.purchaseStatus.listen((message) {
      if (mounted) {
        setState(() => _message = message);
      }
    });
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  Future<void> _refresh() {
    return AccountOperations.bind(_accountGeneration, () async {
    if (_refreshing || !BillingService.isStaging) return;
    _refreshing = true;
    try {
      final profile = await BillingService.refreshStagingProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _message = 'Staging membership refreshed.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _profile = null;
          _message = error.toString();
        });
      }
    } finally {
      _refreshing = false;
    }
      });
  }

  Future<void> _buy(String plan) {
    return AccountOperations.bind(_accountGeneration, () async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final started = await BillingService.buy(plan);
      if (mounted) {
        setState(() => _message = started
          ? 'Store flow opened. Waiting for server verification.'
          : 'Purchase could not start. Check sign-in and store products.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
      });
  }

  Future<void> _restore() {
    return AccountOperations.bind(_accountGeneration, () async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final restored = await BillingService.restore();
      await _refresh();
      if (mounted) {
        setState(() => _message = restored
          ? 'A purchase was verified in staging.'
          : 'No valid purchase was verified before the restore timeout.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
      });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    _purchaseStatus?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = BillingService.isStaging;
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Billing Staging Tests')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Use Apple Sandbox or a Google Play license-test account.'),
          const SizedBox(height: 12),
          Text(enabled ? AwsApiService.billingBaseUrl : 'Production build: test actions disabled'),
          const SizedBox(height: 16),
          if (profile != null) ...[
            Text('Account: ${profile['userId']}'),
            Text('Premium: ${profile['isPremium']}'),
            Text('Status: ${profile['premiumStatus']}'),
            Text('Source: ${profile['premiumSource']}'),
            Text('Premium until (Unix seconds): ${profile['premiumUntil']}'),
            Text('Developer override: ${profile['devOverride']}'),
            Text('Tester override: ${profile['testerOverride']}'),
          ],
          const SizedBox(height: 16),
          Text(_message),
          const SizedBox(height: 16),
          for (final plan in ['Monthly', 'Annual', 'Lifetime'])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ElevatedButton(
                onPressed: enabled && !_busy ? () => _buy(plan) : null,
                child: Text('Test $plan Purchase'),
              ),
            ),
          OutlinedButton(onPressed: enabled && !_busy ? _restore : null,
              child: const Text('Restore Purchases in Staging')),
          TextButton(onPressed: enabled ? _refresh : null,
              child: const Text('Refresh Staging Membership')),
          const SizedBox(height: 16),
          const Text('Cancel and request refunds through the store. '
              'This screen reports staging membership only. '
              'Normal app Premium status remains separate.'),
        ],
      ),
    );
  }
}
