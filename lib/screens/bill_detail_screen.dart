// Read-only bill detail screen
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../services/database_service.dart';
import 'pay_bill_screen.dart';
import 'add_bill_screen.dart';

class BillDetailScreen extends StatelessWidget {
  final Bill bill;

  const BillDetailScreen({super.key, required this.bill});

  String _recurrenceText(Recurrence r) {
    switch (r) {
      case Recurrence.none:
        return 'None';
      case Recurrence.daily:
        return 'Daily';
      case Recurrence.weekly:
        return 'Weekly';
      case Recurrence.monthly:
        return 'Monthly';
      case Recurrence.yearly:
        return 'Yearly';
      case Recurrence.custom:
        return 'Custom';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('yyyy-MM-dd');
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
              subtitle: Text(bill.description ?? ''),
            ),
            ListTile(
              title: const Text('Amount'),
              subtitle: Text(bill.amount.toStringAsFixed(2)),
            ),
            ListTile(
              title: const Text('Due Date'),
              subtitle: Text(dateFmt.format(bill.dueDate.toLocal())),
            ),
            ListTile(
              title: const Text('Recurrence'),
              subtitle: Text(_recurrenceText(bill.recurrence)),
            ),
            if (bill.recurrenceEndDate != null)
              ListTile(
                title: const Text('Recurrence End'),
                subtitle: Text(dateFmt.format(bill.recurrenceEndDate!.toLocal())),
              ),
            // Reminder is controlled globally via Settings now; per-bill flag removed.
            ListTile(
              title: const Text('Payment Status'),
              subtitle: Text(bill.paymentStatus?.toString().split('.').last ?? ''),
            ),
            if (bill.categoryId != null)
              ListTile(
                title: const Text('Category'),
                subtitle: Text(DatabaseService.getCategoryById(bill.categoryId!)?.name ?? 'Unknown'),
                onTap: () {
                  // Open categories screen (if present) or simply do nothing for now
                },
              ),
            if (bill.payeeId != null)
              ListTile(
                title: const Text('Payee'),
                subtitle: Text(() {
                  final payees = DatabaseService.getAllPayees();
                  final p = payees.firstWhere((p) => (p['id'] ?? '') == bill.payeeId, orElse: () => <String, dynamic>{});
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
                    onPressed: () {
                      // Open pay bill screen for this bill's occurrence (use due date)
                      Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => PayBillScreen(bill: bill, occurrenceDate: bill.dueDate)));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => AddBillScreen(existingBill: bill)));
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
