import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/bill.dart';
import '../models/transaction.dart';
import 'add_transaction_screen.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../services/database_service.dart';
import '../services/bill_reminder_service.dart';
import '../services/lookups_state.dart';
import '../theme/app_theme.dart';
import '../utils/duplication_guards.dart';
import '../widgets/splits_editor.dart';
import '../utils/split_utils.dart';
import 'dart:convert';

class PayBillScreen extends StatefulWidget {
  final Bill bill;
  final DateTime occurrenceDate;

  const PayBillScreen({
    super.key,
    required this.bill,
    required this.occurrenceDate,
  });

  @override
  State<PayBillScreen> createState() => _PayBillScreenState();
}

class _PayBillScreenState extends State<PayBillScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _paymentForController = TextEditingController();
  final _notesController = TextEditingController();
  String? _lastAutoPaymentFor;
  late DateTime _paymentDate;
  String? _selectedAccountId;
  List<Account> _accounts = [];
  List<Transaction> _paymentHistory = [];
  List<Map<String, dynamic>> _splits = [];
  bool _useSplits = false;
  bool _isRefund = false; // If true, record payment as income (refund)
  bool _showInReports = true;
  bool _isSaving = false;

  String _visibleBillText(String? raw) {
    final text = (raw ?? '').trim();
    if (text.toLowerCase() == 'bill') return '';
    return text;
  }

  String _extractPaymentForValue(String description) {
    final trimmed = description.trim();
    if (!trimmed.toLowerCase().startsWith('payment for ')) return '';
    return trimmed.substring('payment for '.length).trim();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _matchesBillOccurrence(Transaction tx, DateTime occurrenceDate) {
    final dateShort = DateFormat('MM/dd/yy').format(occurrenceDate);
    final dateLong = DateFormat('MM/dd/yyyy').format(occurrenceDate);

    final txBillId = (tx.billId ?? '').trim();
    if (txBillId.isNotEmpty && txBillId != widget.bill.id) return false;

    final paymentFor = (tx.paymentFor ?? '').trim();
    if (txBillId.isEmpty) {
      // Legacy fallback for old bill payments that predate billId linkage.
      final billText = _visibleBillText(widget.bill.description).toLowerCase();
      final paymentForLower = paymentFor.toLowerCase();
      final descriptionLower = tx.description.toLowerCase();
      final dateMatches =
          paymentFor.contains(dateLong) ||
          paymentFor.contains(dateShort) ||
          descriptionLower.contains(dateLong.toLowerCase()) ||
          descriptionLower.contains(dateShort.toLowerCase());
      final billMatches =
          billText.isNotEmpty &&
          (paymentForLower.contains(billText) ||
              descriptionLower.contains(billText));
      if (!(dateMatches && billMatches)) return false;
    }

    if (tx.occurrenceDate != null) {
      return _isSameDay(tx.occurrenceDate!, occurrenceDate);
    }

    if (_isSameDay(tx.date, occurrenceDate)) return true;
    final description = tx.description;

    return description.contains(dateLong) ||
        description.contains(dateShort) ||
        paymentFor.contains(dateLong) ||
        paymentFor.contains(dateShort);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _paymentDate = DateTime(now.year, now.month, now.day);
    // Show bill amount as placeholder, let user input their own amount
    // Load payment history first so we can compute the current amount due and prefill the amount field
    _loadAccounts();
    _loadPaymentHistory();
    // Compute amount due (original amount minus payments made for this occurrence)
    final totalPaid = _computeSignedTotalPaidForBill(_paymentHistory);
    final amountDue = widget.bill.amount - totalPaid;
    // Prefill the amount field with the amount due (if > 0), otherwise default to the bill amount
    // Use setState so the UI reliably updates after init
    final initialBillNote = _visibleBillText(widget.bill.description);
    setState(() {
      _amountController.text = amountDue > 0
          ? amountDue.toStringAsFixed(2)
          : widget.bill.amount.toStringAsFixed(2);
      _notesController.text = initialBillNote;
      _selectedAccountId = widget.bill.accountId;
    });
    _refreshAutoPaymentFor(force: true);
    // Initialize empty splits for payment (user may add splits before saving)
    _splits = [];
    _useSplits = _splits.isNotEmpty;
    _isRefund = false;
    // If the amount due is already zero (e.g. paid via multiple partial payments),
    // persist the paid status so the pay bill screen and calendar/dashboard reflect it.
    // Use tolerance of 0.01 to handle floating-point precision issues
    if (amountDue <= 0.01) {
      _recalculateAndPersistBillStatus();
    }
    // Listen for transaction changes so the payment history refreshes when a payment is edited elsewhere
    DatabaseService.transactionsVersion.addListener(_onTransactionsChanged);
  }

  void _onTransactionsChanged() {
    if (!mounted) return;
    setState(() {
      _loadPaymentHistory();
      // After reloading payment history, ensure bill paid status is recalculated and persisted
      _recalculateAndPersistBillStatus();
    });
  }

  /// Recalculate total paid for this bill occurrence and persist the
  /// bill's isPaid/paymentStatus if needed. This makes sure installments
  /// are counted and the bill is marked paid when amount due reaches zero.
  Future<void> _recalculateAndPersistBillStatus() async {
    try {
      final allTransactions = DatabaseService.getAllTransactions();
      final relatedPayments = allTransactions
          .where((tx) => _matchesBillOccurrence(tx, widget.occurrenceDate))
          .toList();
      double totalPaid = 0.0;
      for (final tx in relatedPayments) {
        if (widget.bill.type == BillType.expense) {
          // For expense bills, expense transactions increase paid amount,
          // income transactions (refunds) decrease the paid total.
          totalPaid += (tx.type == TransactionType.expense)
              ? tx.amount
              : -tx.amount;
        } else {
          // For income bills, income transactions increase paid amount,
          // expense transactions (refunds/chargebacks) decrease it.
          totalPaid += (tx.type == TransactionType.income)
              ? tx.amount
              : -tx.amount;
        }
      }
      final newStatus = _statusForTotalPaid(totalPaid);

      // Persist occurrence-level status instead of editing the top-level Bill.
      final existing = DatabaseService.getBillOccurrenceStatus(
        widget.bill.id,
        widget.occurrenceDate,
      );
      final bool existingIsPaid = existing != null
          ? (existing['isPaid'] as bool)
          : false;
      final PaymentStatus existingStatus = existing != null
          ? (existing['paymentStatus'] as PaymentStatus)
          : widget.bill.paymentStatus ?? PaymentStatus.unpaid;
      if (existingIsPaid != (newStatus == PaymentStatus.paid) ||
          existingStatus != newStatus) {
        await DatabaseService.setBillOccurrenceStatus(
          widget.bill.id,
          widget.occurrenceDate,
          newStatus == PaymentStatus.paid,
          newStatus,
        );
        if (newStatus == PaymentStatus.paid) {
          _refreshBillReminders();
        }
      }
    } catch (_) {
      // Swallow errors - non-critical. UI will still reflect computed status.
    }
  }

  PaymentStatus _statusForTotalPaid(double totalPaid) {
    if (totalPaid >= (widget.bill.amount - 0.01)) {
      return PaymentStatus.paid;
    }
    if (totalPaid > 0) {
      return PaymentStatus.partial;
    }
    return PaymentStatus.unpaid;
  }

  double _computeSignedTotalPaidForBill(Iterable<Transaction> txs) {
    double totalPaid = 0.0;
    for (final tx in txs) {
      if (widget.bill.type == BillType.expense) {
        totalPaid += (tx.type == TransactionType.expense)
            ? tx.amount
            : -tx.amount;
      } else {
        totalPaid += (tx.type == TransactionType.income)
            ? tx.amount
            : -tx.amount;
      }
    }
    return totalPaid;
  }

  void _loadAccounts() {
    _accounts = DatabaseService.getAllAccounts();
  }

  void _loadPaymentHistory() {
    // Only include payments for this bill occurrence (billId + occurrenceDate)
    final allTransactions = DatabaseService.getAllTransactions();
    // Match by billId and either the transaction date equals the occurrence date
    // or the transaction description includes the occurrence date string (this
    // covers payments recorded on a different date but explicitly for this
    // occurrence).
    _paymentHistory =
        allTransactions
            .where((tx) => _matchesBillOccurrence(tx, widget.occurrenceDate))
            .toList()
          ..sort(
            (a, b) => b.date.compareTo(a.date),
          ); // Sort by date, newest first
  }

  String _resolveCounterpartyName() {
    String counterparty = _visibleBillText(widget.bill.description);
    if (widget.bill.payeeId != null) {
      final payees = DatabaseService.getAllPayees();
      final p = payees.firstWhere(
        (p) => p['id'] == widget.bill.payeeId,
        orElse: () => <String, dynamic>{},
      );
      final payeeName = p['name']?.toString().trim() ?? '';
      if (payeeName.isNotEmpty) {
        counterparty = payeeName;
      }
    }
    return counterparty.isNotEmpty ? counterparty : 'Unknown';
  }

  String _resolveCategoryName() {
    final categoryId = widget.bill.categoryId?.trim();
    if (categoryId != null && categoryId.isNotEmpty) {
      final category = DatabaseService.getCategoryById(categoryId);
      final name = category?.name.trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    return 'Uncategorized';
  }

  String _buildAutoPaymentFor({String? counterpartyName}) {
    final formattedDate = DateFormat(
      'MM/dd/yyyy',
    ).format(widget.occurrenceDate);
    final counterparty = (counterpartyName ?? _resolveCounterpartyName())
        .trim();
    final category = _resolveCategoryName().trim();
    return '$formattedDate $counterparty $category';
  }

  void _refreshAutoPaymentFor({bool force = false}) {
    final current = _paymentForController.text.trim();
    final canOverwrite =
        force ||
        current.isEmpty ||
        (_lastAutoPaymentFor != null && current == _lastAutoPaymentFor);
    if (!canOverwrite) return;

    final autoText = _buildAutoPaymentFor();
    _paymentForController.text = autoText;
    _lastAutoPaymentFor = autoText;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _paymentForController.dispose();
    _notesController.dispose();
    DatabaseService.transactionsVersion.removeListener(_onTransactionsChanged);
    super.dispose();
  }

  void _refreshBillReminders() {
    BillReminderService().refreshAllReminders().catchError((e) {
      debugPrint('Reminder refresh failed after payment change: $e');
    });
  }

  Future<void> _handlePay() async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    // Strip out any non-numeric characters (currency symbols, spaces, etc.) before parsing
    final cleanedAmountText = _amountController.text.replaceAll(
      RegExp(r'[^0-9\.]'),
      '',
    );
    final amount = double.tryParse(cleanedAmountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid amount'),
          backgroundColor: Colors.blueGrey[400],
        ),
      );
      return;
    }

    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select an account'),
          backgroundColor: Colors.blueGrey[400],
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Validate splits if present
      if (_splits.isNotEmpty && !validateSplitsEqualAmount(_splits, amount)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Split amounts must equal the payment amount'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      // Build description with unique format: "Payment for (BillName) (DueDate)"
      final counterpartyName = _resolveCounterpartyName();

      final paymentForInput = _paymentForController.text.trim();
      final paymentForValue = paymentForInput.isNotEmpty
          ? paymentForInput
          : _buildAutoPaymentFor(counterpartyName: counterpartyName);
      final desc = 'Payment for $paymentForValue';

      final lookupsState = context.read<LookupsState>();
      final categoryLookup = widget.bill.categoryId != null
          ? lookupsState.categoriesById[widget.bill.categoryId!]
          : null;
      final payeeLookup = widget.bill.payeeId != null
          ? lookupsState.payeesById[widget.bill.payeeId!]
          : null;

      // Use only the user-provided notes for the transaction. Do not inject account info.
      final userNote = _notesController.text.trim();
      final String? finalNote = userNote.isNotEmpty ? userNote : null;

      final txType = _isRefund
          ? TransactionType.income
          : (widget.bill.type == BillType.income
                ? TransactionType.income
                : TransactionType.expense);

      if (isLikelyDuplicateBillPayment(
        transactions: DatabaseService.getAllTransactions(),
        billId: widget.bill.id,
        occurrenceDate: widget.occurrenceDate,
        paymentDate: _paymentDate,
        amount: amount,
        type: txType,
        accountId: _selectedAccountId,
        description: desc,
        paymentFor: paymentForValue,
      )) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('This payment was already saved.'),
              backgroundColor: Colors.blueGrey[400],
            ),
          );
        }
        return;
      }

      // Create transaction for the payment, set billId and unique id
      final transaction = Transaction(
        id: const Uuid().v4(),
        amount: amount,
        categoryId: widget.bill.categoryId ?? '',
        categoryName:
            categoryLookup?.name ??
            (widget.bill.categoryId != null
                ? DatabaseService.getCategoryById(widget.bill.categoryId!)?.name
                : null),
        type: txType,
        description: desc,
        date: _paymentDate,
        updatedAt: DateTime.now(),
        note: finalNote,
        paymentFor: paymentForValue,
        accountId: _selectedAccountId,
        cleared: false,
        payeeId: widget.bill.payeeId,
        payeeName: payeeLookup?.name ?? counterpartyName,
        billId: widget.bill.id,
        occurrenceDate: widget.occurrenceDate,
        splitsJson: (_useSplits && _splits.isNotEmpty)
            ? jsonEncode(_splits)
            : null,
        showInReports: _showInReports,
      );

      await DatabaseService.addTransaction(transaction);

      // Update account balance
      if (_selectedAccountId != null) {
        final account = DatabaseService.getAccountById(_selectedAccountId!);
        if (account != null) {
          // Update account based on transaction type (income increases, expense decreases)
          final newBalance =
              (_isRefund || (widget.bill.type == BillType.income && !_isRefund))
              ? account.balance + amount
              : account.balance - amount;
          final updatedAccount = account.copyWith(balance: newBalance);
          await DatabaseService.updateAccount(updatedAccount);
        }
      }

      // Calculate total paid and amount due for this specific bill occurrence
      final allTransactions = DatabaseService.getAllTransactions();
      final relatedPayments = allTransactions
          .where((tx) => _matchesBillOccurrence(tx, widget.occurrenceDate))
          .toList();
      double totalPaid2 = 0.0;
      for (final tx in relatedPayments) {
        if (widget.bill.type == BillType.expense) {
          totalPaid2 += (tx.type == TransactionType.expense)
              ? tx.amount
              : -tx.amount;
        } else {
          totalPaid2 += (tx.type == TransactionType.income)
              ? tx.amount
              : -tx.amount;
        }
      }
      final totalPaid = totalPaid2;
      final newStatus = _statusForTotalPaid(totalPaid);
      // Persist occurrence-level status instead of editing top-level Bill
      await DatabaseService.setBillOccurrenceStatus(
        widget.bill.id,
        widget.occurrenceDate,
        newStatus == PaymentStatus.paid,
        newStatus,
      );

      if (mounted) {
        // Notify dashboard/calendar to refresh immediately
        DatabaseService.billsVersion.value++;
        DatabaseService.transactionsVersion.value++;
        _refreshBillReminders();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing payment: $e'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.bill.categoryId != null
        ? DatabaseService.getCategoryById(widget.bill.categoryId!)
        : null;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Pay Bill'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // SECTION 1: Transaction Details
            _buildSectionHeader('Transaction Details', Icons.receipt_long),
            const SizedBox(height: 12),
            _buildTransactionDetailsCard(category),
            const SizedBox(height: 24),

            // SECTION 2: Payment History
            _buildSectionHeader('Payment History', Icons.history),
            const SizedBox(height: 12),
            _buildPaymentHistoryCard(),
            const SizedBox(height: 24),

            // SECTION 3: Payment Details
            _buildSectionHeader('Payment Details', Icons.payment),
            const SizedBox(height: 12),
            _buildPaymentDetailsCard(),
            const SizedBox(height: 32),

           SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    onPressed: _isSaving ? null : _handlePay,
    style: ElevatedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    child: _isSaving
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 8),
              const Text('Saving...'),
            ],
          )
        : const Text('Save Payment'),
  ),
),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

 Widget _buildTransactionDetailsCard(category) {
  final colorScheme = Theme.of(context).colorScheme;

  // Calculate total amount paid from payment history.
  final totalPaid = _computeSignedTotalPaidForBill(_paymentHistory);

  // Calculate remaining balance.
  final amountDue = widget.bill.amount - totalPaid;
  final displayAmountDue = amountDue > 0 ? amountDue : 0.0;

  // Resolve payee/payer name.
  String billName = _visibleBillText(widget.bill.description);

  if (widget.bill.payeeId != null) {
    final payees = DatabaseService.getAllPayees();

    final p = payees.firstWhere(
      (p) => p['id'] == widget.bill.payeeId,
      orElse: () => <String, dynamic>{},
    );

    if (p.containsKey('name')) {
      billName = p['name'] as String;
    }
  }

  if (billName.isEmpty) {
    billName = 'Payment';
  }

  final categoryName = category?.name ?? 'Uncategorized';

  final String statusText;
  final Color statusColor;
  final Color statusBackground;

  if (amountDue <= 0.01) {
    statusText = 'Paid';
    statusColor = AppTheme.incomeGreen;
    statusBackground =
        AppTheme.incomeGreen.withValues(alpha: 0.12);
  } else if (totalPaid > 0) {
    statusText = 'Partially Paid';
    statusColor = Colors.orange;
    statusBackground =
        Colors.orange.withValues(alpha: 0.12);
  } else {
    statusText = 'Unpaid';
    statusColor = AppTheme.expenseRed;
    statusBackground =
        AppTheme.expenseRed.withValues(alpha: 0.10);
  }

  final typeText = widget.bill.type == BillType.expense
      ? 'Expense'
      : widget.bill.type == BillType.income
          ? 'Income'
          : 'Transfer';

  return Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: category != null
                      ? category.color.withValues(alpha: 0.14)
                      : colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: category != null
                    ? category.displayEmoji != null
                        ? Text(
                            category.displayEmoji!,
                            style: const TextStyle(fontSize: 24),
                          )
                        : Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: category.color,
                              shape: BoxShape.circle,
                            ),
                          )
                    : Icon(
                        Icons.receipt_long_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      billName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AMOUNT DUE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  NumberFormat.currency(
                    symbol: '\$',
                  ).format(displayAmountDue),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: amountDue > 0
                            ? AppTheme.expenseRed
                            : AppTheme.incomeGreen,
                      ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          _buildDetailRow(
            'Original amount',
            NumberFormat.currency(
              symbol: '\$',
            ).format(widget.bill.amount),
          ),

          const SizedBox(height: 10),

          _buildDetailRow(
            'Amount paid',
            NumberFormat.currency(
              symbol: '\$',
            ).format(totalPaid),
            valueColor:
                totalPaid > 0 ? AppTheme.incomeGreen : null,
          ),

          const SizedBox(height: 16),

          Divider(
            height: 1,
            color: colorScheme.outlineVariant
                .withValues(alpha: 0.45),
          ),

          const SizedBox(height: 16),

          _buildDetailRow(
            'Due date',
            DateFormat.yMMMd().format(widget.occurrenceDate),
          ),

          const SizedBox(height: 10),

          _buildDetailRow(
            'Type',
            typeText,
          ),
        ],
      ),
    ),
  );
}

  Widget _buildPaymentHistoryCard() {
    final colorScheme = Theme.of(context).colorScheme;

return Card(
  margin: EdgeInsets.zero,
  elevation: 0,
  color: colorScheme.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: BorderSide(
      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
    ),
  ),
  child: Padding(
        padding: const EdgeInsets.all(16),
        child: _paymentHistory.isEmpty
    ? Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 19,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No payments yet',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Payments for this bill will appear here.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent Payments',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...(_paymentHistory.take(5).map((tx) {
                    // Show the account name under the date (strip any leading 'account:' text from notes)
                    String subtitleText = '';
                    if (tx.accountId != null) {
                      final acct = DatabaseService.getAccountById(
                        tx.accountId!,
                      );
                      if (acct != null) subtitleText = acct.name;
                    }
                    // Prepare a user-visible note by stripping internal markers and pair tokens
                    String displayNote = '';
                    final displayPaymentFor =
                        (tx.paymentFor ?? '').trim().isNotEmpty
                        ? (tx.paymentFor ?? '').trim()
                        : _extractPaymentForValue(tx.description);
                    final rawNote = (tx.note ?? '').trim();
                    if (rawNote.isNotEmpty) {
                      String n = rawNote;
                      // If note contains an account: prefix like 'account: Name — usernote', extract the user part
                      if (n.toLowerCase().startsWith('account:')) {
                        final parts = n.split('—');
                        if (parts.length > 1) {
                          n = parts.sublist(1).join('—').trim();
                        } else {
                          // No user note after account prefix
                          n = '';
                        }
                        // Also extract account name for subtitle if present
                        final left = parts.first;
                        final idx = left.indexOf(':');
                        if (idx >= 0 && idx + 1 < left.length) {
                          final name = left.substring(idx + 1).trim();
                          if (name.isNotEmpty) subtitleText = name;
                        }
                      }

                      // Remove known internal markers and transfer pairing tokens
                      n = n.replaceAll('__transfer_bill__', '');
                      n = n.replaceAll('__transfer_manual__', '');
                      n = n.replaceAll('__hide_from_calendar__', '');
                      n = n.replaceAll(RegExp(r'pair:[A-Za-z0-9\-]+'), '');
                      displayNote = n.trim();
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () async {
                          final ctx = context;
                          // Capture local references before any awaits to avoid using
                          // the BuildContext across async gaps.
                          final overlay =
                              Overlay.of(context).context.findRenderObject()
                                  as RenderBox?;
                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);

                          final position = overlay != null
                              ? RelativeRect.fromLTRB(
                                  overlay.size.width / 2,
                                  overlay.size.height / 2,
                                  overlay.size.width / 2,
                                  overlay.size.height / 2,
                                )
                              : const RelativeRect.fromLTRB(100, 100, 100, 100);

                          final result = await showMenu<String>(
                            context: ctx,
                            position: position,
                            items: [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          );

                          if (result == 'edit') {
                            final editResult = await navigator.push<bool?>(
                              MaterialPageRoute(
                                // Allow editing date/description when opening the
                                // transaction editor from the Pay Bill screen so
                                // user changes persist on both sides.
                                builder: (_) => AddTransactionScreen(
                                  existingTransaction: tx,
                                  preserveDescriptionAndDate: false,
                                ),
                              ),
                            );
                            if (!mounted) return;
                            if (editResult == true) {
                              setState(() {
                                _loadPaymentHistory();
                              });
                              await _recalculateAndPersistBillStatus();
                              DatabaseService.billsVersion.value++;
                              _refreshBillReminders();
                            }
                          } else if (result == 'delete') {
                            if (!mounted) return;
                            final confirm = await showDialog<bool>(
                              context: navigator.context,
                              builder: (dialogCtx) => AlertDialog(
                                title: const Text('Delete Payment'),
                                content: const Text(
                                  'Are you sure you want to delete this payment? This action cannot be undone.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogCtx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogCtx).pop(true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              try {
                                // Revert the transaction effect on the linked account balance (if any)
                                final accId = tx.accountId;
                                if (accId != null) {
                                  final acc = DatabaseService.getAccountById(
                                    accId,
                                  );
                                  if (acc != null) {
                                    final effect =
                                        tx.type == TransactionType.income
                                        ? tx.amount
                                        : -tx.amount;
                                    final updatedAcc = acc.copyWith(
                                      balance: acc.balance - effect,
                                    );
                                    await DatabaseService.updateAccount(
                                      updatedAcc,
                                    );
                                  }
                                }
                              } catch (_) {
                                // ignore failures reverting balance but still proceed with deletion
                              }

                              // Remove from hidden list (if present) and delete the transaction
                              try {
                                await DatabaseService.removeHiddenTransactionId(
                                  tx.id,
                                );
                              } catch (_) {}
                              await DatabaseService.deleteTransaction(tx.id);
                              if (!mounted) return;
                              setState(() {
                                _loadPaymentHistory();
                              });
                              // Keep occurrence-level status in sync with dashboard after deletion.
                              await _recalculateAndPersistBillStatus();

                              _refreshBillReminders();
                              messenger.clearSnackBars();
                            }
                          }
                        },
                        child: Container(
  padding: const EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 10,
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.receipt_long_outlined,
          size: 19,
          color: colorScheme.primary,
        ),
      ),

      const SizedBox(width: 12),

      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat.yMMMd().format(tx.date),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),

            if (subtitleText.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                subtitleText,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],

            if (displayPaymentFor.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                'Payment for $displayPaymentFor',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            if (displayNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                displayNote,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),

      const SizedBox(width: 12),

      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            NumberFormat.currency(
              symbol: '\$',
            ).format(tx.amount),
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tx.type == TransactionType.income
                      ? AppTheme.incomeGreen
                      : AppTheme.expenseRed,
                ),
          ),
          const SizedBox(height: 8),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    ],
  ),
),
                      ),
                    );
                  })),
                  if (_paymentHistory.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '+ ${_paymentHistory.length - 5} more payments',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildPaymentDetailsCard() {
  final colorScheme = Theme.of(context).colorScheme;

  return Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount Field
           TextFormField(
  controller: _amountController,
  keyboardType: const TextInputType.numberWithOptions(
    decimal: true,
  ),
  inputFormatters: [
    FilteringTextInputFormatter.allow(
      RegExp(r'[0-9\.]'),
    ),
  ],
  style: const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  ),
  decoration: InputDecoration(
    labelText: 'Payment Amount',
    hintText: NumberFormat.currency(
      symbol: '\$',
    ).format(widget.bill.amount),
    prefixText: '\$ ',
    prefixStyle: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
    suffixIcon: IconButton(
      tooltip: 'Calculator',
      icon: const Icon(
        Icons.calculate_outlined,
        size: 22,
      ),
      onPressed: () async {
        final result = await showModalBottomSheet<double?>(
          context: context,
          isScrollControlled: true,
          builder: (_) => FractionallySizedBox(
            heightFactor: 0.6,
            child: _CalculatorSheet(
              initialValue: _amountController.text,
            ),
          ),
        );

        if (result != null) {
          setState(() {
            _amountController.text =
                result.toStringAsFixed(2);
          });
        }
      },
    ),
    filled: true,
    fillColor: Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.35),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 1.5,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 16,
    ),
  ),
  validator: (value) {
    if (value == null || value.isEmpty) {
      return 'Please enter an amount';
    }

    final cleaned =
        value.replaceAll(RegExp(r'[^0-9\.]'), '');

    final amount = double.tryParse(cleaned);

    if (amount == null || amount <= 0) {
      return 'Please enter a valid amount';
    }

    return null;
  },
  onChanged: (_) => setState(() {}),
),
            const SizedBox(height: 16),

            // Optional splits editor for payment allocations - clickable text to toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _useSplits = !_useSplits;
                      if (!_useSplits) _splits = [];
                    });
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.0),
                    child: Text(
                      'Split Categories',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _useSplits = !_useSplits;
                      if (!_useSplits) _splits = [];
                    });
                  },
                  child: Text(
                    _useSplits ? 'Disable' : 'Enable',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            if (_useSplits)
              SplitsEditor(
                initialSplits: _splits,
                transactionAmount: double.tryParse(_amountController.text),
                onChanged: (s) => _splits = s,
                categoryTypeFilter: widget.bill.type == BillType.income
                    ? CategoryType.income
                    : CategoryType.expense,
              ),

// Payment Date
InkWell(
  borderRadius: BorderRadius.circular(12),
  onTap: () async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() => _paymentDate = picked);
    }
  },
  child: Padding(
    padding: const EdgeInsets.symmetric(
      vertical: 14,
    ),
    child: Row(
      children: [
        Icon(
          Icons.calendar_today_outlined,
          size: 21,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Payment Date',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
        Text(
          DateFormat.yMMMd().format(_paymentDate),
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
      ],
    ),
  ),
),
          Divider(
  height: 1,
  color: Theme.of(context)
      .colorScheme
      .outlineVariant
      .withValues(alpha: 0.45),
),

// Account Selector
InkWell(
  borderRadius: BorderRadius.circular(12),
  onTap: () async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: _accounts.map((account) {
          return ListTile(
            leading: Icon(
              account.type == AccountType.bank
                  ? Icons.account_balance
                  : account.type == AccountType.card
                      ? Icons.credit_card
                      : Icons.money,
            ),
            title: Text(account.name),
            selected: _selectedAccountId == account.id,
            onTap: () =>
                Navigator.pop(context, account.id),
          );
        }).toList(),
      ),
    );

    if (selected != null) {
      setState(() => _selectedAccountId = selected);
    }
  },
  child: Padding(
    padding: const EdgeInsets.symmetric(
      vertical: 14,
    ),
    child: Row(
      children: [
        Icon(
          Icons.account_balance_wallet_outlined,
          size: 21,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pay From Account',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                _selectedAccountId != null
                    ? _accounts
                        .firstWhere(
                          (a) => a.id == _selectedAccountId,
                          orElse: () => Account(
                            name: 'Unknown',
                            type: AccountType.cash,
                            balance: 0,
                          ),
                        )
                        .name
                    : 'Select account',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
      ],
    ),
  ),
),
            const Divider(),
            const SizedBox(height: 8),

          TextFormField(
  controller: _paymentForController,
  textCapitalization: TextCapitalization.sentences,
  readOnly: true,
enableInteractiveSelection: false,
  maxLines: 2,
  decoration: InputDecoration(
    labelText: 'Payment for',
    hintText: 'Ex: 1/1/25 Aloe Road rent',
    alignLabelWithHint: true,
    filled: true,
    fillColor: Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.35),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 1.5,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 16,
    ),
  ),
),
            const SizedBox(height: 12),

            // Notes Field
          TextFormField(
  controller: _notesController,
  textCapitalization: TextCapitalization.sentences,
  minLines: 2,
maxLines: 2,
  decoration: InputDecoration(
    labelText: 'Notes (optional)',
    hintText: 'Add a note about this payment',
    alignLabelWithHint: true,
    filled: true,
    fillColor: Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.35),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 1.5,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 16,
    ),
  ),
),
            const SizedBox(height: 12),
            // Refund toggle: record this payment as an income (refund) which
            // will be treated as reducing the paid total for expense bills.
          Container(
  padding: const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  ),
  decoration: BoxDecoration(
    color: colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.30,
    ),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    children: [
      Icon(
        Icons.currency_exchange_rounded,
        size: 21,
        color: colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Refund (money received)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Record this as income instead of a payment',
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Switch(
        value: _isRefund,
        onChanged: (v) => setState(() => _isRefund = v),
      ),
    ],
  ),
),

const SizedBox(height: 10),

Container(
  padding: const EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  ),
  decoration: BoxDecoration(
    color: colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.30,
    ),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    children: [
      Icon(
        Icons.bar_chart_rounded,
        size: 21,
        color: colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Show in reports',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Include this payment in report totals and charts',
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Switch(
        value: _showInReports,
        onChanged: (v) => setState(() => _showInReports = v),
      ),
    ],
  ),
),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    Color? valueColor,
    bool valueBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: valueBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// Calculator bottom sheet widget
class _CalculatorSheet extends StatefulWidget {
  final String? initialValue;
  const _CalculatorSheet({this.initialValue});

  @override
  State<_CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<_CalculatorSheet> {
  String _expression = '';

  @override
  void initState() {
    super.initState();
    if ((widget.initialValue ?? '').isNotEmpty) {
      _expression = widget.initialValue!;
    }
  }

  void _append(String s) {
    setState(() => _expression += s);
  }

  void _backspace() {
    if (_expression.isNotEmpty) {
      setState(
        () => _expression = _expression.substring(0, _expression.length - 1),
      );
    }
  }

  void _clear() {
    setState(() => _expression = '');
  }

  double? _evaluate() {
    try {
      // Very small expression evaluator supporting + - * /
      final tokens = <String>[];
      String numBuf = '';
      for (var i = 0; i < _expression.length; i++) {
        final ch = _expression[i];
        if ('0123456789.'.contains(ch)) {
          numBuf += ch;
        } else if ('+-*/'.contains(ch)) {
          if (numBuf.isNotEmpty) {
            tokens.add(numBuf);
            numBuf = '';
          }
          tokens.add(ch);
        }
      }
      if (numBuf.isNotEmpty) tokens.add(numBuf);

      if (tokens.isEmpty) return null;

      // first pass: *,/
      final stack = <String>[];
      for (var i = 0; i < tokens.length; i++) {
        final t = tokens[i];
        if (t == '*' || t == '/') {
          final prev = stack.removeLast();
          final next = tokens[++i];
          final a = double.parse(prev);
          final b = double.parse(next);
          final res = t == '*' ? a * b : a / b;
          stack.add(res.toString());
        } else {
          stack.add(t);
        }
      }

      // second pass: +,-
      var result = double.parse(stack[0]);
      for (var i = 1; i < stack.length; i += 2) {
        final op = stack[i];
        final val = double.parse(stack[i + 1]);
        if (op == '+') result += val;
        if (op == '-') result -= val;
      }
      return result;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final eval = _evaluate();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _expression,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                IconButton(
                  onPressed: _backspace,
                  icon: const Icon(Icons.backspace),
                ),
              ],
            ),
          ),
          if (eval != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  const Text(
                    'Result:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    eval.toStringAsFixed(2),
                    style: const TextStyle(fontSize: 20),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              childAspectRatio: 1.6,
              padding: const EdgeInsets.all(12),
              children:
                  [
                    '7',
                    '8',
                    '9',
                    '/',
                    '4',
                    '5',
                    '6',
                    '*',
                    '1',
                    '2',
                    '3',
                    '-',
                    '.',
                    '0',
                    '=',
                    '+',
                  ].map((label) {
                    return Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: ElevatedButton(
                        onPressed: () {
                          if (label == '=') {
                            final value = _evaluate();
                            if (value != null) Navigator.of(context).pop(value);
                            return;
                          }
                          _append(label);
                        },
                        child: Text(
                          label,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: _clear,
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
                InkWell(
                  onTap: () {
                    final value = _evaluate();
                    if (value != null) Navigator.of(context).pop(value);
                  },
                  child: Text(
                    'Accept',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
