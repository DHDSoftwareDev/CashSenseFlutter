// ignore_for_file: use_super_parameters, use_build_context_synchronously, unnecessary_to_list_in_spreads

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/database_service.dart';
import '../services/billing_service.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late String _currentPlan;
  final Map<String, String> _prices = {};
  final TextEditingController _promoController = TextEditingController();
  String? _appliedPromo;

  // Benefits per plan
  final Map<String, List<String>> _benefits = {
    'Monthly': [
    ],
    'Annual': [
    ],
    'Lifetime': [
    ],
  };

  final List<Map<String, String>> _plans = [
    {'id': 'Monthly', 'title': 'Monthly', 'desc': 'Billed monthly — full feature access.'},
    {'id': 'Annual', 'title': 'Annual', 'desc': 'Billed yearly — best value for active users.'},
    {'id': 'Lifetime', 'title': 'Lifetime', 'desc': 'One-time purchase — lifetime access.'},
  ];

  @override
  void initState() {
    super.initState();
  _currentPlan = DatabaseService.subscriptionVersion.value;
    _appliedPromo = DatabaseService.getSetting<String>('appliedPromoCode');
    // promo/trial info will be read on demand from DatabaseService/BillingService
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    for (final p in _plans) {
      final id = p['id']!;
      final price = await BillingService.getPrice(id);
      setState(() {
        _prices[id] = price ?? '';
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final Color headerColor = Theme.of(context).brightness == Brightness.light
        ? Colors.black87
        : Colors.white;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (BillingService.isTrialActive()) ...[
            Card(
              color: Colors.green[50],
              child: ListTile(
                leading: const Icon(Icons.timer, color: Colors.green),
                title: const Text('Trial active'),
                subtitle: Text('Expires ${BillingService.trialExpiry()?.toLocal().toString().split(" ").first ?? ''}'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Promo code input
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promoController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Promo Code',
                        hintText: _appliedPromo ?? 'Enter Code',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () async {
                      final code = _promoController.text.trim();
                      if (code.isEmpty) return;
                      final res = await BillingService.applyPromoCode(code);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? ''), backgroundColor: Colors.grey[400]));
                      setState(() {
                        _currentPlan = DatabaseService.subscriptionVersion.value;
                        _appliedPromo = DatabaseService.getSetting<String>('appliedPromoCode');
                      });
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                  title: const Text('Current Plan'),
                  subtitle: Text(_currentPlan),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _openDeviceSubscriptionPage,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.settings, size: 18),
                          const SizedBox(width: 4),
                          const Text('Manage Subscription'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Collapsible section describing what Premium includes
          Card(
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.info_outline, color: Colors.blue),
              title: const Text("What's included in Premium"),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Premium features include:', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No Ads', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: headerColor)),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Enjoy an ad-free experience throughout the app when you upgrade to Premium.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Unlimited Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: headerColor)),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Create and manage detailed reports with filters by category, payee, payer, and custom date ranges to track every aspect of your finances.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Unlimited Accounts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: headerColor)),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Create up to 3 accounts for free - upgrade for unlimited accounts.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Unlimited Bills', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: headerColor)),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                  "Manage up to 100 bills and payments for free — upgrade for unlimited tracking.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Unlimited Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: headerColor)),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Free users are limited to 50 transactions per account. Upgrade to record unlimited transactions.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Available Plans', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ..._plans.map((p) {
            final id = p['id']!;
            final isCurrent = id == _currentPlan;
            return Card(
              child: ListTile(
                // Title row: plan title (single line) and price aligned top-right
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        p['title']!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if ((_prices[id] ?? '').isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _prices[id]!,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['desc']!),
                    const SizedBox(height: 8),
                    // Trial badge for Monthly / Annual
                    Builder(builder: (context) {
                      if (id == 'Monthly') {
                        // Monthly has a 7-day trial promotion
                        if (BillingService.isTrialActive() && (DatabaseService.getSetting<String>('subscriptionPlan') == 'Monthly')) {
                          final exp = BillingService.trialExpiry();
                          final text = exp != null ? 'Trial active until ${exp.toLocal().toString().split(' ').first}' : 'Trial active';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Chip(label: Text(text, style: TextStyle(fontSize: 11)), backgroundColor: Colors.transparent),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Chip(label: const Text('7-day free trial', style: TextStyle(fontSize: 11)), backgroundColor: Colors.transparent),
                        );
                      }

                      if (id == 'Annual') {
                        // Annual has a 30-day trial promotion
                        if (BillingService.isTrialActive() && (DatabaseService.getSetting<String>('subscriptionPlan') == 'Annual')) {
                          final exp = BillingService.trialExpiry();
                          final text = exp != null ? 'Trial active until ${exp.toLocal().toString().split(' ').first}' : 'Trial active';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Chip(label: Text(text, style: TextStyle(fontSize: 11)), backgroundColor: Colors.transparent),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Chip(label: const Text('30-day free trial', style: TextStyle(fontSize: 11)), backgroundColor: Colors.transparent),
                        );
                      }

                      return const SizedBox.shrink();
                    }),
                    // Benefits
                    ...?_benefits[id]?.map((b) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(fontSize: 12)),
                            Expanded(child: Text(b, style: Theme.of(context).textTheme.bodySmall)),
                          ],
                        )),
                  ],
                ),
                trailing: isCurrent
                    ? TextButton(
                        onPressed: () => _showManagePlanDialog(id),
                        child: const Text('Manage'),
                      )
                    : TextButton(
                        onPressed: () => _confirmSubscribe(id),
                        child: const Text('Subscribe in App Store'),
                      ),
              ),
            );
          }).toList(),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore Purchases'),
              subtitle: const Text('Restore previous purchase or subscription status'),
              trailing: TextButton(
                onPressed: () async {
                  final restored = await BillingService.restore();
                  setState(() {
                    _currentPlan = DatabaseService.subscriptionVersion.value;
                  });
                  if (restored) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Your previous subscription has been restored.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No active subscription found to restore.')),
                    );
                  }
                },
                child: const Text('Restore'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmSubscribe(String id) async {
    await _openAppStoreForSubscription();
  }


  void _showManagePlanDialog(String id) async {
    await _openAppStoreForSubscription();
  }

  Future<void> _openAppStoreForSubscription() async {
    // Opens the app's page in the App Store or Play Store for subscription management
    String url;
    if (Platform.isIOS) {
      // Replace with your actual App Store app URL
      url = 'https://apps.apple.com/app/idYOUR_APP_ID';
    } else if (Platform.isAndroid) {
      // Replace with your actual Play Store app URL
      url = 'https://play.google.com/store/apps/details?id=YOUR_PACKAGE_NAME';
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App Store not available on this platform')),
        );
      }
      return;
    }

    final Uri appStoreUri = Uri.parse(url);
    if (await canLaunchUrl(appStoreUri)) {
      await launchUrl(appStoreUri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open app store')),
        );
      }
    }
  }

  // Add this method to open the device's subscription management page
  void _openDeviceSubscriptionPage() async {
    String url;
    if (Platform.isIOS) {
      url = 'https://apps.apple.com/account/subscriptions';
    } else if (Platform.isAndroid) {
      url = 'https://play.google.com/store/account/subscriptions';
    } else {
      url = 'https://dhdsoftware.com/CashSense';
    }
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open subscription management')),
        );
      }
    }
  }
}
