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
    final refreshed = DatabaseService.getAllBills().where((b) => b.id == _bill.id);
    if (refreshed.isEmpty) return;
    setState(() {
      _bill = refreshed.first;
    });
  }

  String _recurrenceText(Bill bill) {
    final r = bill.recurrence;
    final interval = bill.recurrenceInterval <= 0 ? 1 : bill.recurrenceInterval;
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

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final category = (_bill.categoryId != null && _bill.categoryId!.isNotEmpty)
        ? DatabaseService.getCategoryById(_bill.categoryId!)
        : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Details'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ListTile(
              title: const Text('Description'),
              subtitle: Text(_bill.description ?? ''),
            ),
            ListTile(
              title: const Text('Amount'),
              subtitle: Text(_bill.amount.toStringAsFixed(2)),
            ),
            ListTile(
              title: const Text('Due Date'),
              subtitle: Text(dateFmt.format(_bill.dueDate.toLocal())),
            ),
            ListTile(
              title: const Text('Recurrence'),
              subtitle: Text(_recurrenceText(_bill)),
            ),
            if (_bill.recurrenceEndDate != null)
              ListTile(
                title: const Text('Recurrence End'),
                subtitle: Text(dateFmt.format(_bill.recurrenceEndDate!.toLocal())),
              ),
            // Reminder is controlled globally via Settings now; per-bill flag removed.
            ListTile(
              title: const Text('Payment Status'),
              subtitle: Text(_bill.paymentStatus?.toString().split('.').last ?? ''),
            ),
            if (_bill.categoryId != null)
              ListTile(
                leading: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: category?.color ?? Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                title: const Text('Category'),
                subtitle: Text(category?.name ?? 'Unknown'),
                onTap: () {
                  // Open categories screen (if present) or simply do nothing for now
                },
              ),
            if (_bill.payeeId != null)
              ListTile(
                title: const Text('Payee'),
                subtitle: Text(() {
                  final payees = DatabaseService.getAllPayees();
                  final p = payees.firstWhere((p) => (p['id'] ?? '') == _bill.payeeId, orElse: () => <String, dynamic>{});
                  return p.containsKey('name') ? (p['name'] as String) : 'Unknown';
                }()),
                onTap: () {
                  // Optionally navigate to payee list / details
                },
              ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payment),
                    label: const Text('Pay'),
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
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                    onPressed: () async {
                      final result = await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => AddBillScreen(existingBill: _bill),
                        ),
                      );
                      if (!mounted || result != true) return;
                      _reloadBill();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
