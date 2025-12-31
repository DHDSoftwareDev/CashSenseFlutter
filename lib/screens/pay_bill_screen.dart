import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/bill.dart';
import '../models/transaction.dart';
import 'add_transaction_screen.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
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
  final _notesController = TextEditingController();
  late DateTime _paymentDate;
  String? _selectedAccountId;
  List<Account> _accounts = [];
  List<Transaction> _paymentHistory = [];
  List<Map<String, dynamic>> _splits = [];
  bool _useSplits = false;
  bool _isRefund = false; // If true, record payment as income (refund)

  @override
  void initState() {
    super.initState();
    _paymentDate = widget.occurrenceDate;
  // Show bill amount as placeholder, let user input their own amount
    // Load payment history first so we can compute the current amount due and prefill the amount field
    _loadAccounts();
    _loadPaymentHistory();
    // Compute amount due (original amount minus payments made for this occurrence)
    final totalPaid = _paymentHistory.fold<double>(0.0, (sum, tx) => sum + tx.amount);
    final amountDue = widget.bill.amount - totalPaid;
    // Prefill the amount field with the amount due (if > 0), otherwise default to the bill amount
    // Use setState so the UI reliably updates after init
    setState(() {
      _amountController.text = amountDue > 0 ? amountDue.toStringAsFixed(2) : widget.bill.amount.toStringAsFixed(2);
      // Autofill notes field with bill description if available
      _notesController.text = widget.bill.description?.trim() ?? '';
      _selectedAccountId = widget.bill.accountId;
    });
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
      final formattedDate = DateFormat('MM/dd/yyyy').format(widget.occurrenceDate);
      final relatedPayments = allTransactions.where((tx) =>
        tx.billId == widget.bill.id && (
          (tx.occurrenceDate != null
            ? (tx.occurrenceDate!.year == widget.occurrenceDate.year && tx.occurrenceDate!.month == widget.occurrenceDate.month && tx.occurrenceDate!.day == widget.occurrenceDate.day)
            : ((tx.date.year == widget.occurrenceDate.year && tx.date.month == widget.occurrenceDate.month && tx.date.day == widget.occurrenceDate.day) || tx.description.contains(formattedDate))
          )
        )
      ).toList();
      double totalPaid = 0.0;
      for (final tx in relatedPayments) {
        if (widget.bill.type == BillType.expense) {
          // For expense bills, expense transactions increase paid amount,
          // income transactions (refunds) decrease the paid total.
          totalPaid += (tx.type == TransactionType.expense) ? tx.amount : -tx.amount;
        } else {
          // For income bills, income transactions increase paid amount,
          // expense transactions (refunds/chargebacks) decrease it.
          totalPaid += (tx.type == TransactionType.income) ? tx.amount : -tx.amount;
        }
      }
      final amountDue = widget.bill.amount - totalPaid;

      PaymentStatus newStatus;
      // Use tolerance of 0.01 to handle floating-point precision issues
      if (amountDue <= 0.01) {
        newStatus = PaymentStatus.paid;
      } else if (totalPaid > 0 && amountDue > 0) {
        newStatus = PaymentStatus.partial;
      } else {
        newStatus = PaymentStatus.unpaid;
      }

      // Persist occurrence-level status instead of editing the top-level Bill.
      final existing = DatabaseService.getBillOccurrenceStatus(widget.bill.id, widget.occurrenceDate);
      final bool existingIsPaid = existing != null ? (existing['isPaid'] as bool) : false;
      final PaymentStatus existingStatus = existing != null ? (existing['paymentStatus'] as PaymentStatus) : widget.bill.paymentStatus ?? PaymentStatus.unpaid;
      if (existingIsPaid != (newStatus == PaymentStatus.paid) || existingStatus != newStatus) {
        await DatabaseService.setBillOccurrenceStatus(widget.bill.id, widget.occurrenceDate, newStatus == PaymentStatus.paid, newStatus);
      }
    } catch (_) {
      // Swallow errors - non-critical. UI will still reflect computed status.
    }
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
    final occDateStr = DateFormat('MM/dd/yyyy').format(widget.occurrenceDate);
    _paymentHistory = allTransactions.where((tx) =>
      tx.billId == widget.bill.id && (
        (tx.occurrenceDate != null
          ? (tx.occurrenceDate!.year == widget.occurrenceDate.year && tx.occurrenceDate!.month == widget.occurrenceDate.month && tx.occurrenceDate!.day == widget.occurrenceDate.day)
          : ((tx.date.year == widget.occurrenceDate.year && tx.date.month == widget.occurrenceDate.month && tx.date.day == widget.occurrenceDate.day) || tx.description.contains(occDateStr))
        )
      )
    ).toList()
      ..sort((a, b) => b.date.compareTo(a.date)); // Sort by date, newest first
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    DatabaseService.transactionsVersion.removeListener(_onTransactionsChanged);
    super.dispose();
  }

  Future<void> _handlePay() async {
    if (!_formKey.currentState!.validate()) return;

    // Strip out any non-numeric characters (currency symbols, spaces, etc.) before parsing
    final cleanedAmountText = _amountController.text.replaceAll(RegExp(r'[^0-9\.]'), '');
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

    try {
      // Validate splits if present
      if (_splits.isNotEmpty && !validateSplitsEqualAmount(_splits, amount)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Split amounts must equal the payment amount'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }
      // Build description with unique format: "Payment for (BillName) (DueDate)"
      String billName = widget.bill.description ?? 'Bill Payment';
      if (widget.bill.payeeId != null) {
        final payees = DatabaseService.getAllPayees();
        final p = payees.firstWhere(
          (p) => p['id'] == widget.bill.payeeId,
          orElse: () => <String, dynamic>{},
        );
        if (p.containsKey('name')) billName = p['name'] as String;
      }
      
      final formattedDate = DateFormat('MM/dd/yyyy').format(widget.occurrenceDate);
      final desc = 'Payment for $billName ($formattedDate)';

      // Use only the user-provided notes for the transaction. Do not inject account info.
      final userNote = _notesController.text.trim();
      final String? finalNote = userNote.isNotEmpty ? userNote : null;

      // Create transaction for the payment, set billId and unique id
      final transaction = Transaction(
        id: const Uuid().v4(),
        amount: amount,
        categoryId: widget.bill.categoryId ?? '',
        type: _isRefund ? TransactionType.income : (widget.bill.type == BillType.income ? TransactionType.income : TransactionType.expense),
        description: desc,
        date: _paymentDate,
        note: finalNote,
        accountId: _selectedAccountId,
        billId: widget.bill.id,
        occurrenceDate: widget.occurrenceDate,
  splitsJson: (_useSplits && _splits.isNotEmpty) ? jsonEncode(_splits) : null,
      );

      await DatabaseService.addTransaction(transaction);
      // Hide bill payments from calendar/dashboard views
      await DatabaseService.addHiddenTransactionId(transaction.id);

      // Update account balance
      if (_selectedAccountId != null) {
        final account = DatabaseService.getAccountById(_selectedAccountId!);
        if (account != null) {
          // Update account based on transaction type (income increases, expense decreases)
          final newBalance = ( _isRefund || (widget.bill.type == BillType.income && !_isRefund) )
              ? account.balance + amount
              : account.balance - amount;
          final updatedAccount = account.copyWith(balance: newBalance);
          await DatabaseService.updateAccount(updatedAccount);
        }
      }

      // Calculate total paid and amount due for this specific bill occurrence
      final allTransactions = DatabaseService.getAllTransactions();
      // Match related payments by billId and either the occurrence date or the
      // occurrence date string embedded in the description (covers payments
      // made on a different date but explicitly for this occurrence).
      final relatedPayments = allTransactions.where((tx) =>
        tx.billId == widget.bill.id && (
          (tx.occurrenceDate != null
            ? (tx.occurrenceDate!.year == widget.occurrenceDate.year && tx.occurrenceDate!.month == widget.occurrenceDate.month && tx.occurrenceDate!.day == widget.occurrenceDate.day)
            : ((tx.date.year == widget.occurrenceDate.year && tx.date.month == widget.occurrenceDate.month && tx.date.day == widget.occurrenceDate.day) || tx.description.contains(formattedDate))
          )
        )
      ).toList();
      double totalPaid2 = 0.0;
      for (final tx in relatedPayments) {
        if (widget.bill.type == BillType.expense) {
          totalPaid2 += (tx.type == TransactionType.expense) ? tx.amount : -tx.amount;
        } else {
          totalPaid2 += (tx.type == TransactionType.income) ? tx.amount : -tx.amount;
        }
      }
      final totalPaid = totalPaid2;
      final amountDue = widget.bill.amount - totalPaid;

      PaymentStatus newStatus;
      if (amountDue <= 0) {
        newStatus = PaymentStatus.paid;
      } else if (totalPaid > 0 && amountDue > 0) {
        newStatus = PaymentStatus.partial;
      } else {
        newStatus = PaymentStatus.unpaid;
      }
      // Persist occurrence-level status instead of editing top-level Bill
      await DatabaseService.setBillOccurrenceStatus(widget.bill.id, widget.occurrenceDate, newStatus == PaymentStatus.paid, newStatus);

      if (mounted) {
        // Notify dashboard/calendar to refresh immediately
        DatabaseService.billsVersion.value++;
        DatabaseService.transactionsVersion.value++;
        // Show confirmation and close screen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Payment saved successfully'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
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

            // Save Payment Button - Clickable Text
            Center(
              child: SizedBox(
                width: 180,
                height: 48,
                child: ElevatedButton(
                  onPressed: _handlePay,
                  style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Save Payment'),
                ),
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
    // Calculate total amount paid from payment history
    final totalPaid = _paymentHistory.fold<double>(
      0.0,
      (sum, tx) => sum + tx.amount,
    );
    // Calculate amount due (remaining balance)
    final amountDue = widget.bill.amount - totalPaid;

    // Get payee name if available
    String billName = widget.bill.description ?? 'Bill';
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

    // Payment status display removed here; the displayed status below is
    // computed from the actual payments for the bill occurrence so the
    // dashboard reflects the same computed state.

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top status row removed per UI change request. Status is shown
            // further down and dashboard/bill state is updated from the
            // computed status below when payments change.
            const SizedBox(height: 8),
            Row(
              children: [
                if (category != null)
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: category.color.withAlpha(0x33),
                    child: Icon(
                      category.icon,
                      color: category.color,
                      size: 24,
                    ),
                  )
                else
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey.withAlpha(0x33),
                    child: const Icon(
                      Icons.help,
                      color: Colors.grey,
                      size: 24,
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        billName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        category?.name ?? 'Uncategorized',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // Name/Description
            _buildDetailRow('Name:', billName),
            const SizedBox(height: 8),
            
            // Category
            _buildDetailRow('Category:', category?.name ?? 'Uncategorized'),
            const SizedBox(height: 8),
            
            // Original Amount
            _buildDetailRow(
              'Original Amount:', 
              NumberFormat.currency(symbol: '\$').format(widget.bill.amount),
            ),
            const SizedBox(height: 8),
            
            // Amount Paid
            _buildDetailRow(
              'Amount Paid:', 
              NumberFormat.currency(symbol: '\$').format(totalPaid),
              valueColor: totalPaid > 0 ? AppTheme.incomeGreen : null,
            ),
            const SizedBox(height: 8),
            
            // Amount Due
            _buildDetailRow(
              'Amount Due:', 
              NumberFormat.currency(symbol: '\$').format(amountDue > 0 ? amountDue : 0),
              valueColor: amountDue > 0 ? AppTheme.expenseRed : AppTheme.incomeGreen,
              valueBold: true,
            ),
            const SizedBox(height: 8),
            
            const Divider(height: 16),
            const SizedBox(height: 8),
            
            // Due Date
            _buildDetailRow('Due Date:', DateFormat.yMMMd().format(widget.occurrenceDate)),
            const SizedBox(height: 8),
            
            // Type
            _buildDetailRow('Type:', widget.bill.type == BillType.expense ? 'Expense' : widget.bill.type == BillType.income ? 'Income' : 'Transfer'),
            const SizedBox(height: 8),
            
            // Status
            _buildDetailRow(
              'Status:', 
              amountDue <= 0.01 ? 'Paid' : (totalPaid > 0 ? 'Partially Paid' : 'Unpaid'),
              valueColor: amountDue <= 0.01 ? AppTheme.incomeGreen : (totalPaid > 0 ? Colors.orange : AppTheme.expenseRed),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentHistoryCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _paymentHistory.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No payment history available',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
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
                          final acct = DatabaseService.getAccountById(tx.accountId!);
                          if (acct != null) subtitleText = acct.name;
                        }
                        // Prepare a user-visible note by stripping internal markers and pair tokens
                        String displayNote = '';
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
                              final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
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
                                final editResult = await navigator.push<bool?> (
                                  MaterialPageRoute(
                                    // Allow editing date/description when opening the
                                    // transaction editor from the Pay Bill screen so
                                    // user changes persist on both sides.
                                    builder: (_) => AddTransactionScreen(existingTransaction: tx, preserveDescriptionAndDate: false),
                                  ),
                                );
                                if (!mounted) return;
                                if (editResult == true) {
                                  // Always re-hide the payment after editing
                                  await DatabaseService.addHiddenTransactionId(tx.id);
                                  setState(() {
                                    _loadPaymentHistory();
                                  });
                                  // Recalculate and persist bill payment status after an edited payment
                                  try {
                                    final allTransactions = DatabaseService.getAllTransactions();
                                    final occDateStr = DateFormat('MM/dd/yyyy').format(widget.occurrenceDate);
                                    final relatedPayments = allTransactions.where((t) =>
                                      t.billId == widget.bill.id && (
                                        (t.occurrenceDate != null
                                            ? (t.occurrenceDate!.year == widget.occurrenceDate.year && t.occurrenceDate!.month == widget.occurrenceDate.month && t.occurrenceDate!.day == widget.occurrenceDate.day)
                                            : ((t.date.year == widget.occurrenceDate.year && t.date.month == widget.occurrenceDate.month && t.date.day == widget.occurrenceDate.day) || t.description.contains(occDateStr))
                                          )
                                        )
                                      ).toList();
                                    final totalPaid = relatedPayments.fold<double>(0.0, (sum, tx) => sum + tx.amount);
                                    final amountDue = widget.bill.amount - totalPaid;
                                    PaymentStatus newStatus;
                                    if (amountDue <= 0) {
                                      newStatus = PaymentStatus.paid;
                                    } else if (totalPaid > 0 && amountDue > 0) {
                                      newStatus = PaymentStatus.partial;
                                    } else {
                                      newStatus = PaymentStatus.unpaid;
                                    }
                                    final updatedBill = widget.bill.copyWith(
                                      isPaid: newStatus == PaymentStatus.paid,
                                      paymentStatus: newStatus,
                                    );
                                    await DatabaseService.updateBill(updatedBill);
                                    DatabaseService.billsVersion.value++;
                                  } catch (_) {}
                                }
                              } else if (result == 'delete') {
                                if (!mounted) return;
                                final confirm = await showDialog<bool>(
                                  context: navigator.context,
                                  builder: (dialogCtx) => AlertDialog(
                                    title: const Text('Delete Payment'),
                                    content: const Text('Are you sure you want to delete this payment? This action cannot be undone.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(dialogCtx).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(dialogCtx).pop(true),
                                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  try {
                                    // Revert the transaction effect on the linked account balance (if any)
                                    final accId = tx.accountId;
                                    if (accId != null) {
                                      final acc = DatabaseService.getAccountById(accId);
                                      if (acc != null) {
                                        final effect = tx.type == TransactionType.income ? tx.amount : -tx.amount;
                                        final updatedAcc = acc.copyWith(balance: acc.balance - effect);
                                        await DatabaseService.updateAccount(updatedAcc);
                                      }
                                    }
                                  } catch (_) {
                                    // ignore failures reverting balance but still proceed with deletion
                                  }

                                  // Remove from hidden list (if present) and delete the transaction
                                  try {
                                    await DatabaseService.removeHiddenTransactionId(tx.id);
                                  } catch (_) {}
                                  await DatabaseService.deleteTransaction(tx.id);
                                  if (!mounted) return;
                                  setState(() {
                                    _loadPaymentHistory();
                                  });
                                  // Recalculate and persist bill payment status after deletion
                                    try {
                                    final allTransactions = DatabaseService.getAllTransactions();
                                    final occDateStr = DateFormat('MM/dd/yyyy').format(widget.occurrenceDate);
                                    final relatedPayments = allTransactions.where((t) =>
                                      t.billId == widget.bill.id && (
                                        (t.occurrenceDate != null
                                          ? (t.occurrenceDate!.year == widget.occurrenceDate.year && t.occurrenceDate!.month == widget.occurrenceDate.month && t.occurrenceDate!.day == widget.occurrenceDate.day)
                                          : ((t.date.year == widget.occurrenceDate.year && t.date.month == widget.occurrenceDate.month && t.date.day == widget.occurrenceDate.day) || t.description.contains(occDateStr))
                                        )
                                      )
                                    ).toList();
                                    final totalPaid = relatedPayments.fold<double>(0.0, (sum, tx) => sum + tx.amount);
                                    final amountDue = widget.bill.amount - totalPaid;
                                    PaymentStatus newStatus;
                                    if (amountDue <= 0) {
                                      newStatus = PaymentStatus.paid;
                                    } else if (totalPaid > 0 && amountDue > 0) {
                                      newStatus = PaymentStatus.partial;
                                    } else {
                                      newStatus = PaymentStatus.unpaid;
                                    }
                                    final updatedBill = widget.bill.copyWith(
                                      isPaid: newStatus == PaymentStatus.paid,
                                      paymentStatus: newStatus,
                                    );
                                    await DatabaseService.updateBill(updatedBill);
                                    DatabaseService.billsVersion.value++;
                                  } catch (_) {}

                                  messenger.showSnackBar(
                                    SnackBar(content: const Text('Payment deleted'), backgroundColor: Colors.blueGrey[400]),
                                  );
                                }
                              }
                            },
                            child: Card(
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          DateFormat('MM/dd/yyyy').format(tx.date),
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        if (subtitleText.isNotEmpty)
                                          Text(
                                            subtitleText,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Colors.grey[600],
                                                ),
                                          ),
                                        // Note is shown under the amount column now (right side)
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          NumberFormat.currency(symbol: '\$').format(tx.amount),
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: tx.type == TransactionType.income
                                                    ? AppTheme.incomeGreen
                                                    : AppTheme.expenseRed,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        if (displayNote.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          SizedBox(
                                            width: 160,
                                            child: Text(
                                              displayNote,
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: Colors.grey[700],
                                                  ),
                                              textAlign: TextAlign.right,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
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
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount Field
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                // Allow only digits and decimal point; block currency symbols or letters
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Amount',
                // Use a plain dollar sign prefix so the input value remains parseable
                prefixText: '\$ ',
                border: const OutlineInputBorder(),
                // Show a nicely formatted currency hint for the original bill amount
                hintText: NumberFormat.currency(symbol: '\$').format(widget.bill.amount),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calculate),
                  onPressed: () async {
                    final result = await showModalBottomSheet<double?> (
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => FractionallySizedBox(
                        heightFactor: 0.6,
                        child: _CalculatorSheet(initialValue: _amountController.text),
                      ),
                    );
                    if (result != null) {
                      setState(() {
                        _amountController.text = result.toStringAsFixed(2);
                      });
                    }
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter an amount';
                }
                final cleaned = value.replaceAll(RegExp(r'[^0-9\.]'), '');
                final amount = double.tryParse(cleaned);
                if (amount == null || amount <= 0) {
                  return 'Please enter a valid amount';
                }
                return null;
              },
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
                    child: Text('Split Categories', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _useSplits = !_useSplits;
                      if (!_useSplits) _splits = [];
                    });
                  },
                  child: Text(_useSplits ? 'Disable' : 'Enable', style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                ),
              ],
            ),
            if (_useSplits)
              SplitsEditor(
                initialSplits: _splits,
                transactionAmount: double.tryParse(_amountController.text),
                onChanged: (s) => _splits = s,
                categoryTypeFilter: widget.bill.type == BillType.income ? CategoryType.income : CategoryType.expense,
              ),


            // Payment Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Payment Date'),
              trailing: Text(
                DateFormat.yMMMd().format(_paymentDate),
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
            ),
            const Divider(),

            // Account Selector
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('Pay From Account'),
              subtitle: Text(
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
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  builder: (context) => ListView(
                    shrinkWrap: true,
                    children: _accounts.map((account) {
                              return ListTile(
                                leading: Icon(account.type == AccountType.bank
                                    ? Icons.account_balance
                                    : account.type == AccountType.card
                                        ? Icons.credit_card
                                        : Icons.money),
                                title: Text(account.name),
                                // Amounts removed from the account list per UI request
                                selected: _selectedAccountId == account.id,
                                onTap: () => Navigator.pop(context, account.id),
                              );
                    }).toList(),
                  ),
                );
                if (selected != null) {
                  setState(() => _selectedAccountId = selected);
                }
              },
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Notes Field
            TextFormField(
              controller: _notesController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Payment for ${widget.bill.description ?? "bill"}',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            // Refund toggle: record this payment as an income (refund) which
            // will be treated as reducing the paid total for expense bills.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Refund (money received)'),
              subtitle: const Text('Record this as income (refund) instead of a payment'),
              value: _isRefund,
              onChanged: (v) => setState(() => _isRefund = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor, bool valueBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
              ),
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
    if (_expression.isNotEmpty) setState(() => _expression = _expression.substring(0, _expression.length - 1));
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
                Expanded(child: Text(_expression, style: const TextStyle(fontSize: 24))),
                IconButton(onPressed: _backspace, icon: const Icon(Icons.backspace))
              ],
            ),
          ),
          if (eval != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text(eval.toStringAsFixed(2), style: const TextStyle(fontSize: 20)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              childAspectRatio: 1.6,
              padding: const EdgeInsets.all(12),
              children: [
                '7','8','9','/',
                '4','5','6','*',
                '1','2','3','-',
                '.','0','=','+',
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
                    child: Text(label, style: const TextStyle(fontSize: 18)),
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
