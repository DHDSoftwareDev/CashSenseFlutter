// ignore_for_file: use_build_context_synchronously, use_super_parameters

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../models/transaction.dart';
import '../models/bill.dart';

class ReportTransactionsScreen extends StatefulWidget {
  final String filterType; // 'category' | 'payee' | 'payer'
  final String label;
  final DateTime start;
  final DateTime end;
  final TransactionType? type;

  const ReportTransactionsScreen({Key? key, required this.filterType, required this.label, required this.start, required this.end, this.type}) : super(key: key);

  @override
  State<ReportTransactionsScreen> createState() => _ReportTransactionsScreenState();
}

class _ReportTransactionsScreenState extends State<ReportTransactionsScreen> {
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$');
  List<Transaction> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    DatabaseService.transactionsVersion.addListener(_loadTransactions);
    DatabaseService.categoriesVersion.addListener(_onCategoriesChanged);
  }

  @override
  void dispose() {
    DatabaseService.transactionsVersion.removeListener(_loadTransactions);
    DatabaseService.categoriesVersion.removeListener(_onCategoriesChanged);
    super.dispose();
  }

  void _onCategoriesChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _extractPayeeName(String desc) {
    var name = desc.trim();
    if (name.toLowerCase().startsWith('payment for ')) {
      name = name.substring('payment for '.length).trim();
    }
    final dateRegex = RegExp(r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})$');
    name = name.replaceAll(dateRegex, '').trim();
    return name;
  }

  bool _matchesLabelInsensitive(String source, String label) {
    final s = source.toLowerCase().trim();
    final l = label.toLowerCase().trim();
    if (s == l) return true;
    if (s.contains(l)) return true;
    if (l.contains(s)) return true;
    return false;
  }

  bool _matchesPayee(Transaction t, String label) {
    // Prefer explicit transaction fields and ID-backed lookup first.
    final txPayeeName = (t.payeeName ?? '').trim();
    if (txPayeeName.isNotEmpty && _matchesLabelInsensitive(txPayeeName, label)) return true;

    // Match by explicit payee id -> name
    if (t.payeeId != null && t.payeeId!.isNotEmpty) {
      final payee = DatabaseService.getAllPayees().firstWhere((p) => (p['id'] ?? '') == t.payeeId, orElse: () => <String, dynamic>{});
      final payeeName = (payee['name'] ?? '').toString();
      if (payeeName.isNotEmpty && _matchesLabelInsensitive(payeeName, label)) return true;
    }

    // Match by extracted payee-like description (e.g. "Payment for Rent 11/06/2025")
    final extracted = _extractPayeeName(t.description);
    if (extracted.isNotEmpty && _matchesLabelInsensitive(extracted, label)) return true;

    // Match by raw description containing the label
    if (t.description.isNotEmpty && _matchesLabelInsensitive(t.description, label)) return true;

    // If transaction links to a bill whose description matches, include it
    if (t.billId != null && t.billId!.isNotEmpty) {
      final bill = DatabaseService.getAllBills().firstWhere(
        (b) => b.id == t.billId,
        orElse: () => Bill(
          id: '',
          amount: 0.0,
          description: '',
          dueDate: DateTime.now(),
          recurrence: Recurrence.none,
          recurrenceInterval: 1,
          type: BillType.expense,
        ),
      );
      final bdesc = (bill.description ?? '').toString();
      if (bdesc.isNotEmpty && _matchesLabelInsensitive(bdesc, label)) return true;
    }
    return false;
  }

  bool _matchesPayer(Transaction t, String label) {
    final txPayerName = (t.payerName ?? '').trim();
    if (txPayerName.isNotEmpty && _matchesLabelInsensitive(txPayerName, label)) return true;

    if (t.payerId != null && t.payerId!.isNotEmpty) {
      final payer = DatabaseService.getAllPayees().firstWhere((p) => (p['id'] ?? '') == t.payerId, orElse: () => <String, dynamic>{});
      final payerName = (payer['name'] ?? '').toString();
      if (payerName.isNotEmpty && _matchesLabelInsensitive(payerName, label)) return true;
    }
    final extractedP = _extractPayeeName(t.description);
    if (extractedP.isNotEmpty && _matchesLabelInsensitive(extractedP, label)) return true;
    if (t.description.isNotEmpty && _matchesLabelInsensitive(t.description, label)) return true;
    if (t.billId != null && t.billId!.isNotEmpty) {
      final bill = DatabaseService.getAllBills().firstWhere(
        (b) => b.id == t.billId,
        orElse: () => Bill(
          id: '',
          amount: 0.0,
          description: '',
          dueDate: DateTime.now(),
          recurrence: Recurrence.none,
          recurrenceInterval: 1,
          type: BillType.expense,
        ),
      );
      final bdesc = (bill.description ?? '').toString();
      if (bdesc.isNotEmpty && _matchesLabelInsensitive(bdesc, label)) return true;
    }
    return false;
  }

  void _loadTransactions() {
    final all = DatabaseService.getAllTransactions();
    final start = widget.start;
    final end = widget.end;
    List<Transaction> filtered = all.where((t) {
      if (!t.showInReports) return false;
      // Exclude transfers by category or by title/notes containing 'transfer'
      final descLower = t.description.toLowerCase();
      final noteLower = (t.note ?? '').toLowerCase();
      if (descLower.contains('transfer')) return false;
      if (noteLower.contains('transfer')) return false;
      if (descLower.startsWith('__transfer_manual__') || descLower.startsWith('__transfer_bill__')) return false;

      if (t.date.isBefore(start) || t.date.isAfter(end)) return false;
      if (widget.type != null && t.type != widget.type) return false;
      if (widget.filterType == 'category' || widget.filterType == 'category_both') {
        final txCategoryName = (t.categoryName ?? '').trim();
        if (txCategoryName.isNotEmpty && _matchesLabelInsensitive(txCategoryName, widget.label)) return true;

        final cat = DatabaseService.getCategoryById(t.categoryId);
        if (cat != null && _matchesLabelInsensitive(cat.name, widget.label)) return true;

        if (t.description.trim() == widget.label) return true;
        return false;
      } else if (widget.filterType == 'both') {
        // Combined payee OR payer matching
        if (_matchesPayee(t, widget.label)) return true;
        if (_matchesPayer(t, widget.label)) return true;
        return false;
      } else if (widget.filterType == 'payee') {
        return _matchesPayee(t, widget.label);
      } else if (widget.filterType == 'payer') {
        return _matchesPayer(t, widget.label);
      }
      return false;
    }).toList();

    filtered.sort((a, b) {
      final cmp = b.date.compareTo(a.date);
      if (cmp != 0) return cmp;
      final createdCmp = b.createdAt.compareTo(a.createdAt);
      if (createdCmp != 0) return createdCmp;
      return b.id.compareTo(a.id);
    });

    setState(() {
      _transactions = filtered;
    });
  }

  Widget _buildTxRow(Transaction t) {
    // Show date in MM/DD/YYYY for reports transactions list
    final dateStr = DateFormat('MM/dd/yyyy').format(t.date);
  // Category/account not shown in reports transactions list per UX request.
  // Keep lookup removed to avoid unused variable warnings.
  // final category = DatabaseService.getCategoryById(t.categoryId);
  // final catName = category?.name ?? '';
  final amountStr = _currencyFormat.format(t.amount * (t.type == TransactionType.expense ? -1 : 1));
  final color = t.type == TransactionType.income ? Colors.green : Colors.red;
  final visibleNote = _stripAccountPrefix(t.note);
  // For transactions created by the Pay Bill flow the description often
  // follows the pattern "Payment for {PayeeName} (MM/DD/YYYY)". Extract
  // a clean payee/payer name and, when a payment-style description is
  // detected, show only that name and hide the redundant date line.
  final extracted = _extractPayeeName(t.description);
  final isPayment = t.description.toLowerCase().startsWith('payment for ');
  final displayTitle = (isPayment && extracted.isNotEmpty) ? extracted : (t.description.isNotEmpty ? t.description : '(No description)');
  final showDate = !isPayment;

  return ListTile(
    title: Text(displayTitle),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Show date except for payment transactions where date is embedded
        // in the description and should be omitted from the subtitle.
        if (showDate) Text(dateStr),
        if ((visibleNote ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            visibleNote!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ],
    ),
    trailing: Text(amountStr, style: TextStyle(color: color)),
    onTap: () {
      // Navigate to the main Transactions screen focused on this account if desired.
      // For now, do nothing or could open transaction detail in future.
    },
  );
  }

  // Returns the user-visible portion of a note by removing any internal
  // embedded account marker like: 'account: Account Name — user note'.
  // Also strips legacy internal tokens so they don't show in reports.
  String? _stripAccountPrefix(String? note) {
    if (note == null) return null;
    var plainNote = note;
    // Strip any internal hide marker if present
    if (plainNote.contains('__hide_from_calendar__')) {
      plainNote = plainNote.replaceAll('__hide_from_calendar__', '').trim();
      if (plainNote.isEmpty) return null;
    }
    // Remove any internal pair tokens left in notes (e.g. 'pair:<id>').
    if (plainNote.contains('pair:')) {
      plainNote = plainNote.replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '').trim();
      if (plainNote.isEmpty) return null;
    }
    final lower = plainNote.toLowerCase();
    if (lower.startsWith('account:')) {
      final after = plainNote.substring('account:'.length).trim();
      final parts = after.split(RegExp(r'\s*[—–-]\s*'));
      if (parts.length > 1) {
        final extracted = parts.sublist(1).join(' — ').trim();
        return extracted.isEmpty ? null : extracted;
      }
      return null;
    }
    return plainNote.trim().isEmpty ? null : plainNote.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.label} — Transactions',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _transactions.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('No transactions for this selection', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
              ),
            )
          : ListView.separated(
              itemCount: _transactions.length,
              physics: const AlwaysScrollableScrollPhysics(),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) => _buildTxRow(_transactions[i]),
            ),
    );
  }
}
