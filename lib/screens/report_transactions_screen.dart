// ignore_for_file: use_build_context_synchronously, use_super_parameters, curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../models/transaction.dart';
import '../utils/split_utils.dart';
import '../models/bill.dart';

class ReportTransactionsScreen extends StatefulWidget {
  final String filterType; // 'category' | 'payee' | 'payer'
  final String label;
  final DateTime start;
  final DateTime end;
  final TransactionType? type;
  final String? filterId;

  const ReportTransactionsScreen({
    Key? key,
    required this.filterType,
    required this.label,
    required this.start,
    required this.end,
    this.type,
    this.filterId,
  }) : super(key: key);

  @override
  State<ReportTransactionsScreen> createState() =>
      _ReportTransactionsScreenState();
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
    if (txPayeeName.isNotEmpty && _matchesLabelInsensitive(txPayeeName, label))
      return true;

    // Match by explicit payee id -> name
    if (t.payeeId != null && t.payeeId!.isNotEmpty) {
      final payee = DatabaseService.getAllPayees().firstWhere(
        (p) => (p['id'] ?? '') == t.payeeId,
        orElse: () => <String, dynamic>{},
      );
      final payeeName = (payee['name'] ?? '').toString();
      if (payeeName.isNotEmpty && _matchesLabelInsensitive(payeeName, label))
        return true;
    }

    // Match by extracted payee-like description (e.g. "Payment for Rent 11/06/2025")
    final extracted = _extractPayeeName(t.description);
    if (extracted.isNotEmpty && _matchesLabelInsensitive(extracted, label))
      return true;

    // Match by raw description containing the label
    if (t.description.isNotEmpty &&
        _matchesLabelInsensitive(t.description, label))
      return true;

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
      if (bdesc.isNotEmpty && _matchesLabelInsensitive(bdesc, label))
        return true;
    }
    return false;
  }

  bool _matchesPayer(Transaction t, String label) {
    final txPayerName = (t.payerName ?? '').trim();
    if (txPayerName.isNotEmpty && _matchesLabelInsensitive(txPayerName, label))
      return true;

    if (t.payerId != null && t.payerId!.isNotEmpty) {
      final payer = DatabaseService.getAllPayees().firstWhere(
        (p) => (p['id'] ?? '') == t.payerId,
        orElse: () => <String, dynamic>{},
      );
      final payerName = (payer['name'] ?? '').toString();
      if (payerName.isNotEmpty && _matchesLabelInsensitive(payerName, label))
        return true;
    }
    final extractedP = _extractPayeeName(t.description);
    if (extractedP.isNotEmpty && _matchesLabelInsensitive(extractedP, label))
      return true;
    if (t.description.isNotEmpty &&
        _matchesLabelInsensitive(t.description, label))
      return true;
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
      if (bdesc.isNotEmpty && _matchesLabelInsensitive(bdesc, label))
        return true;
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
      if (descLower.startsWith('__transfer_manual__') ||
          descLower.startsWith('__transfer_bill__'))
        return false;

      if (t.date.isBefore(start) || t.date.isAfter(end)) return false;
      if (widget.type != null && t.type != widget.type) return false;
      if (widget.filterType == 'category' ||
          widget.filterType == 'category_both') {
        final exactCategoryId = widget.filterId?.trim();
        if (exactCategoryId != null && exactCategoryId.isNotEmpty) {
          return transactionUsesCategory(
            primaryCategoryId: t.categoryId,
            total: t.amount,
            categoryId: exactCategoryId,
            splitsJson: t.splitsJson,
          );
        }

        final txCategoryName = (t.categoryName ?? '').trim();
        if (txCategoryName.isNotEmpty &&
            _matchesLabelInsensitive(txCategoryName, widget.label))
          return true;

        final cat = DatabaseService.getCategoryById(t.categoryId);
        if (cat != null && _matchesLabelInsensitive(cat.name, widget.label))
          return true;

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
    final cs = Theme.of(context).colorScheme;
    final dateStr = DateFormat('MMM d, yyyy').format(t.date);
    var displayedAmount = t.amount;
    final exactCategoryId = widget.filterId?.trim();
    if ((widget.filterType == 'category' || widget.filterType == 'category_both') &&
        exactCategoryId != null &&
        exactCategoryId.isNotEmpty) {
      displayedAmount = categoryAllocations(
            primaryCategoryId: t.categoryId,
            total: t.amount,
            splitsJson: t.splitsJson,
          )[exactCategoryId] ??
          t.amount;
    }

    final signedAmount = displayedAmount *
        (t.type == TransactionType.expense ? -1 : 1);
    final amountStr = _currencyFormat.format(signedAmount);
    final amountColor =
        t.type == TransactionType.income ? Colors.green : cs.error;
    final visibleNote = _stripAccountPrefix(t.note);
    final extracted = _extractPayeeName(t.description);
    final isPayment = t.description.toLowerCase().startsWith('payment for ');
    final displayTitle = (isPayment && extracted.isNotEmpty)
        ? extracted
        : (t.description.isNotEmpty ? t.description : '(No description)');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: amountColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                t.type == TransactionType.income
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
                color: amountColor,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if ((visibleNote ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      visibleNote!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                amountStr,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
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
      plainNote = plainNote
          .replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '')
          .trim();
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          '${widget.label} — Transactions',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _transactions.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 42,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No transactions for this selection',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _transactions.length,
              itemBuilder: (ctx, i) => _buildTxRow(_transactions[i]),
            ),
    );
  }

}
