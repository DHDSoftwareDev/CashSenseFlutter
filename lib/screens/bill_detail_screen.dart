// Read-only bill detail screen
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../services/database_service.dart';
import 'pay_bill_screen.dart';
import 'add_bill_screen.dart';

class BillDetailScreen extends StatefulWidget {
  final Bill bill;

  const BillDetailScreen({super.key, required this.bill});

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  late Bill _bill;

  @override
  void initState() {
    super.initState();
    _bill = widget.bill;
  }

  void _reloadBill() {
    final refreshed =
        DatabaseService.getAllBills().where((b) => b.id == _bill.id);
    if (refreshed.isEmpty) return;

    setState(() {
      _bill = refreshed.first;
    });
  }

  String _recurrenceText(Bill bill) {
    final r = bill.recurrence;
    final interval =
        bill.recurrenceInterval <= 0 ? 1 : bill.recurrenceInterval;

    switch (r) {
      case Recurrence.none:
        return 'None';
      case Recurrence.daily:
        return interval == 1 ? 'Every day' : 'Every $interval days';
      case Recurrence.weekly:
        return interval == 1 ? 'Every week' : 'Every $interval weeks';
      case Recurrence.monthly:
        return interval == 1 ? 'Every month' : 'Every $interval months';
      case Recurrence.yearly:
        return interval == 1 ? 'Every year' : 'Every $interval years';
      case Recurrence.custom:
        return 'Custom';
    }
  }

  Widget _detailRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
    Widget? leading,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading ??
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 21,
                  color: iconColor ?? colorScheme.primary,
                ),
              ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('MMM d, yyyy');

    final category =
        (_bill.categoryId != null && _bill.categoryId!.isNotEmpty)
            ? DatabaseService.getCategoryById(_bill.categoryId!)
            : null;

    String payeeName = 'Unknown';
    if (_bill.payeeId != null) {
      final payees = DatabaseService.getAllPayees();
      final p = payees.firstWhere(
        (p) => (p['id'] ?? '') == _bill.payeeId,
        orElse: () => <String, dynamic>{},
      );

      if (p.containsKey('name')) {
        payeeName = p['name'] as String;
      }
    }

    final paymentStatus =
        _bill.paymentStatus?.toString().split('.').last ?? '';

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text(
          'Bill Details',
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            // BILL SUMMARY
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.receipt_long_outlined,
                      color: colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _bill.description?.trim().isNotEmpty == true
                        ? _bill.description!
                        : 'Bill',
                    textAlign: TextAlign.center,
                    style:
                        Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '\$${_bill.amount.toStringAsFixed(2)}',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // BILL DETAILS
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                children: [
                  _detailRow(
                    context: context,
                    icon: Icons.calendar_today_outlined,
                    label: 'Due Date',
                    value: dateFmt.format(_bill.dueDate.toLocal()),
                  ),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant
                        .withValues(alpha: 0.35),
                  ),
                  _detailRow(
                    context: context,
                    icon: Icons.repeat_rounded,
                    label: 'Recurrence',
                    value: _recurrenceText(_bill),
                  ),
                  if (_bill.recurrenceEndDate != null) ...[
                    Divider(
                      height: 1,
                      color: colorScheme.outlineVariant
                          .withValues(alpha: 0.35),
                    ),
                    _detailRow(
                      context: context,
                      icon: Icons.event_busy_outlined,
                      label: 'Recurrence End',
                      value: dateFmt.format(
                        _bill.recurrenceEndDate!.toLocal(),
                      ),
                    ),
                  ],
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant
                        .withValues(alpha: 0.35),
                  ),
                  _detailRow(
                    context: context,
                    icon: Icons.payments_outlined,
                    label: 'Payment Status',
                    value: paymentStatus.isEmpty
                        ? 'Unknown'
                        : paymentStatus,
                  ),
                  if (_bill.categoryId != null) ...[
                    Divider(
                      height: 1,
                      color: colorScheme.outlineVariant
                          .withValues(alpha: 0.35),
                    ),
                    _detailRow(
                      context: context,
                      icon: Icons.category_outlined,
                      label: 'Category',
                      value: category?.name ?? 'Unknown',
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: (category?.color ?? Colors.grey)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: category?.color ?? Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_bill.payeeId != null) ...[
                    Divider(
                      height: 1,
                      color: colorScheme.outlineVariant
                          .withValues(alpha: 0.35),
                    ),
                    _detailRow(
                      context: context,
                      icon: Icons.person_outline_rounded,
                      label: 'Payee',
                      value: payeeName,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 22),

            // PRIMARY ACTION
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => PayBillScreen(
                        bill: _bill,
                        occurrenceDate: _bill.dueDate,
                      ),
                    ),
                  );

                  if (!mounted) return;
                  _reloadBill();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.payment_rounded),
                label: const Text(
                  'Pay Bill',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result =
                            await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) =>
                                AddBillScreen(existingBill: _bill),
                          ),
                        );

                        if (!mounted || result != true) return;
                        _reloadBill();
                      },
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text(
                        'Edit',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text(
                        'Close',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
