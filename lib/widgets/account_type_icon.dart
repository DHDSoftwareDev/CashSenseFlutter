import 'package:flutter/material.dart';

import '../models/account.dart';

class AccountTypeIcon extends StatelessWidget {
  const AccountTypeIcon({
    super.key,
    required this.type,
    this.displayName,
    this.color,
  });

  final AccountType type;
  final String? displayName;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    final normalizedName = displayName?.toLowerCase() ?? '';

    if (normalizedName.contains('saving')) {
      return Icon(Icons.savings_outlined, color: resolvedColor);
    }

    final isChecking =
        normalizedName.contains('checking') ||
        normalizedName.contains('check') ||
        type == AccountType.bank;
    if (isChecking) {
      return Semantics(
        label: 'Checking account',
        child: SizedBox(
          width: 28,
          height: 20,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: resolvedColor, width: 1.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Positioned(
                left: 4,
                top: 5,
                child: Container(
                  width: 8,
                  height: 1.6,
                  color: resolvedColor,
                ),
              ),
              Positioned(
                left: 4,
                top: 9,
                child: Container(
                  width: 14,
                  height: 1.4,
                  color: resolvedColor.withValues(alpha: 0.7),
                ),
              ),
              Positioned(
                right: 2,
                bottom: 0,
                child: Icon(
                  Icons.check_rounded,
                  size: 12,
                  color: resolvedColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Icon(
      switch (type) {
        AccountType.cash => Icons.account_balance_wallet_outlined,
        AccountType.bank => Icons.payments_outlined,
        AccountType.card => Icons.credit_card_outlined,
        AccountType.investment => Icons.savings_outlined,
      },
      color: resolvedColor,
    );
  }
}
