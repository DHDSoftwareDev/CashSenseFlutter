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
    'Monthly': [],
    'Annual': [],
    'Lifetime': [],
  };

  final List<Map<String, String>> _plans = [
    {
      'id': 'Monthly',
      'title': 'Monthly',
      'desc': 'Billed monthly — full feature access.',
    },
    {
      'id': 'Annual',
      'title': 'Annual',
      'desc': 'Billed yearly — best value for active users.',
    },
    {
      'id': 'Lifetime',
      'title': 'Lifetime',
      'desc': 'One-time purchase — lifetime access.',
    },
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

  BoxDecoration _cardDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final headerColor =
        Theme.of(context).brightness == Brightness.light
            ? Colors.black87
            : Colors.white;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text(
          'Subscriptions',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          if (BillingService.isTrialActive()) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trial active',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Expires ${BillingService.trialExpiry()?.toLocal().toString().split(" ").first ?? ''}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // PROMO CODE
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(context),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promoController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Promo Code',
                      hintText: _appliedPromo ?? 'Enter Code',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 17,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () async {
                      final code = _promoController.text.trim();
                      if (code.isEmpty) return;
                      final res = await BillingService.applyPromoCode(code);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(res['message'] ?? '')),
                      );
                      setState(() {
                        _currentPlan =
                            DatabaseService.subscriptionVersion.value;
                        _appliedPromo = DatabaseService.getSetting<String>(
                          'appliedPromoCode',
                        );
                      });
                    },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // CURRENT PLAN
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(context),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.workspace_premium_outlined,
                      color: Colors.amber,
                      size: 30,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Plan',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currentPlan,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _openDeviceSubscriptionPage,
                    icon: const Icon(Icons.settings_outlined, size: 19),
                    label: const Text('Manage Subscription'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // PREMIUM FEATURES
          Container(
            decoration: _cardDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 4,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              leading: Icon(
                Icons.info_outline_rounded,
                color: colorScheme.primary,
              ),
              title: const Text(
                "What's included in Premium",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                _premiumFeature(
                  context,
                  'No Ads',
                  'Enjoy an ad-free experience throughout the app when you upgrade to Premium.',
                  headerColor,
                ),
                _premiumFeature(
                  context,
                  'Unlimited Reports',
                  'Create and manage detailed reports with filters by category, payee, payer, and custom date ranges to track every aspect of your finances.',
                  headerColor,
                ),
                _premiumFeature(
                  context,
                  'Unlimited Accounts',
                  'Create up to 3 accounts for free - upgrade for unlimited accounts.',
                  headerColor,
                ),
                _premiumFeature(
                  context,
                  'Unlimited Bills',
                  'Manage up to 100 bills and payments for free — upgrade for unlimited tracking.',
                  headerColor,
                ),
                _premiumFeature(
                  context,
                  'Unlimited Transactions',
                  'Free users are limited to 50 transactions per account. Upgrade to record unlimited transactions.',
                  headerColor,
                ),
                _premiumFeature(
                  context,
                  'Cloud Backup & Restore',
                  'Manually back up your data to the cloud and restore it on another device.',
                  headerColor,
                  isLast: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Available Plans',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),

          ..._plans.map((p) {
            final id = p['id']!;
            final isCurrent = id == _currentPlan;
            final price = _prices[id] ?? '';

            String? trialText;
            if (id == 'Monthly') {
              if (BillingService.isTrialActive() &&
                  DatabaseService.getSetting<String>('subscriptionPlan') ==
                      'Monthly') {
                final exp = BillingService.trialExpiry();
                trialText = exp != null
                    ? 'Trial active until ${exp.toLocal().toString().split(' ').first}'
                    : 'Trial active';
              } else {
                trialText = '7-day free trial';
              }
            } else if (id == 'Annual') {
              if (BillingService.isTrialActive() &&
                  DatabaseService.getSetting<String>('subscriptionPlan') ==
                      'Annual') {
                final exp = BillingService.trialExpiry();
                trialText = exp != null
                    ? 'Trial active until ${exp.toLocal().toString().split(' ').first}'
                    : 'Trial active';
              } else {
                trialText = '30-day free trial';
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isCurrent
                        ? colorScheme.primary.withValues(alpha: 0.55)
                        : colorScheme.outlineVariant.withValues(alpha: 0.35),
                    width: isCurrent ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      p['title']!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Current',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: colorScheme
                                                  .onPrimaryContainer,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                p['desc']!,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (price.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Text(
                            price,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ],
                    ),
                    if (trialText != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          trialText,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ],
                    ...?_benefits[id]?.map(
                      (benefit) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                benefit,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: isCurrent
                          ? OutlinedButton(
                              onPressed: () => _showManagePlanDialog(id),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Manage Plan'),
                            )
                          : FilledButton(
                              onPressed: () => _confirmSubscribe(id),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text('Choose ${p['title']}'),
                            ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 4),

          // RESTORE PURCHASES
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(context),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.restore_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Restore Purchases',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Restore previous purchase or subscription status',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () async {
                      final restored = await BillingService.restore();
                      if (!mounted) return;
                      setState(() {
                        _currentPlan =
                            DatabaseService.subscriptionVersion.value;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            restored
                                ? 'Your previous subscription has been restored.'
                                : 'No active subscription found to restore.',
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Restore Purchases'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumFeature(
    BuildContext context,
    String title,
    String description,
    Color headerColor, {
    bool isLast = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              Icons.check_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: headerColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmSubscribe(String id) async {
    try {
      final started = await BillingService.buy(id);
      if (!context.mounted) return;

      setState(() {
        _currentPlan = DatabaseService.subscriptionVersion.value;
      });

      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start purchase')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start purchase: $e')));
    }
  }

  void _showManagePlanDialog(String id) async {
    await _openDeviceSubscriptionPage();
  }

  // Add this method to open the device's subscription management page
  Future<void> _openDeviceSubscriptionPage() async {
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
          const SnackBar(
            content: Text('Could not open subscription management'),
          ),
        );
      }
    }
  }
}
