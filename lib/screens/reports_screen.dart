// ignore_for_file: unused_field, prefer_final_fields, unused_element, use_super_parameters, deprecated_member_use, use_build_context_synchronously, curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/report_details_list.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import 'report_transactions_screen.dart';
import '../theme/app_theme.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../models/bill.dart';
import '../utils/root_scaffold.dart';
import '../widgets/banner_ad_widget.dart';
import 'manage_cards_screen.dart';

class _PieSlice {
  final String label;
  final double value;
  final Color color;
  _PieSlice(this.label, this.value, this.color);
}

// Simple horizontal bar chart used to replace pie charts when there are many items.
// The horizontal bar chart widget was removed per UI request. We previously
// rendered a compact horizontal bar chart when there were many items, but the
// requirement is to only show the scrollable details list. The implementation
// is retained in git history if needed later.

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Future<void> _refreshReports() async {
    _loadCategories();
    _loadPayees();
    setState(() {});
  }
  
  // Extract a normalized payee/payer name from a transaction description.
  // This was previously a local helper inside a single build method but is
  // needed across multiple report builders, so keep it as a private
  // instance method on the state class.
  String extractPayeeName(String desc) {
    String name = desc.trim();
    if (name.toLowerCase().startsWith('payment for ')) {
      name = name.substring('payment for '.length).trim();
    }
    final dateRegex = RegExp(r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})$');
    name = name.replaceAll(dateRegex, '').trim();
    return name;
  }

  String _formatPeriodLabel(DateTime start, DateTime end) {
    // Month of
    final lastDayOfStartMonth = DateTime(start.year, start.month + 1, 1).subtract(const Duration(days: 1));
    if (start.day == 1 && end.year == lastDayOfStartMonth.year && end.month == lastDayOfStartMonth.month && end.day == lastDayOfStartMonth.day) {
      return 'Month of ${DateFormat.yMMMM().format(start)}';
    }

    // Week of (assume 7-day range)
    if (end.difference(start).inDays == 6) {
      return 'Week of ${DateFormat.yMMMd().format(start)}';
    }

    // Year
    if (start.month == 1 && start.day == 1 && end.month == 12 && end.day == 31 && start.year == end.year) {
      return 'Year ${start.year}';
    }

    // Fallback to explicit range
    return '${DateFormat.yMMMd().format(start)} — ${DateFormat.yMMMd().format(end)}';
  }

  void _openTransactionsForLabel(String title, String label, DateTime start, DateTime end, {TransactionType? type, String? filterOverride}) {
    String filterType = 'category';
    if (filterOverride != null && filterOverride.isNotEmpty) {
      filterType = filterOverride;
    } else {
      final t = title.toLowerCase();
      if (t.contains('payee')) filterType = 'payee';
      else if (t.contains('payer')) filterType = 'payer';
      else filterType = 'category';
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => ReportTransactionsScreen(filterType: filterType, label: label, start: start, end: end, type: type)));
  }
  Widget _buildCategoryPieChartCard({
    required BuildContext context,
    required String title,
    required TransactionType type,
    required DateTime start,
    required DateTime end,
  }) {
  List<Transaction> txs = _transactionsExcludingTransfersRange(start, end)
    .where((t) => t.type == type)
    .toList();
    final transferCategory = _categories.firstWhere(
      (c) => c.name.trim().toLowerCase() == 'transfer',
      orElse: () => Category(
        id: '__no_transfer__',
        name: '',
        iconCodePoint: '',
        colorValue: '0xFF888888',
        isDefault: false,
        type: type == TransactionType.income ? CategoryType.income : CategoryType.expense,
      ),
    );
    if (transferCategory.id != '__no_transfer__') {
      txs = txs.where((t) => t.categoryId != transferCategory.id).toList();
    }
    // Only filter if a filter is selected
    if (_selectedCategoryIds.isNotEmpty) {
      txs = txs.where((t) => _selectedCategoryIds.contains(t.categoryId)).toList();
    }
    if (_selectedPayeeIds.isNotEmpty) {
      if (_showPayers && type == TransactionType.income) {
        txs = txs.where((t) {
          if (t.payerId != null && _selectedPayeeIds.contains(t.payerId)) return true;
          for (final id in _selectedPayeeIds) {
            final payer = _payees.firstWhere((p) => p['id'] == id, orElse: () => <String, dynamic>{});
            final name = (payer['name'] ?? '').toString().trim();
            if (name.isNotEmpty && t.description.contains(name)) return true;
          }
          return false;
        }).toList();
      } else if (!_showPayers && type == TransactionType.expense) {
        txs = txs.where((t) {
          if (t.payeeId != null && _selectedPayeeIds.contains(t.payeeId)) return true;
          for (final id in _selectedPayeeIds) {
            final payee = _payees.firstWhere((p) => p['id'] == id, orElse: () => <String, dynamic>{});
            final name = (payee['name'] ?? '').toString().trim();
            if (name.isNotEmpty && t.description.contains(name)) return true;
          }
          return false;
        }).toList();
      }
      // If neither, show all
    }
    final Map<String, double> categoryTotals = {};
    for (final t in txs) {
      categoryTotals[t.categoryId] = (categoryTotals[t.categoryId] ?? 0) + t.amount;
    }
    final total = categoryTotals.values.fold(0.0, (a, b) => a + b);
    // Group by the final display label so categories that resolve to the same
    // name (for example via fallback matching) are aggregated onto one slice.
    final Map<String, double> grouped = {};
    final Map<String, Color> groupedColor = {};
    for (final e in categoryTotals.entries) {
      // Try to match by category ID, then by name, fallback to 'Unknown'
      Category cat = _categories.firstWhere(
        (c) => c.id == e.key,
        orElse: () {
          final match = _categories.where((c) => c.name.trim().toLowerCase() == e.key.toString().trim().toLowerCase());
          return match.isNotEmpty
              ? match.first
              : Category(
                  id: e.key,
                  name: 'Unknown',
                  iconCodePoint: '',
                  colorValue: '0xFF888888',
                  isDefault: false,
                  type: type == TransactionType.income ? CategoryType.income : CategoryType.expense,
                );
        },
      );
  String label = cat.name;
  // Omit any categories that are named 'transfer' to avoid showing
  // transfers as 'Unknown' or otherwise in report cards.
  if (label.trim().toLowerCase().contains('transfer')) continue;
      if (label == 'Unknown') {
        // Only match categories by categoryId or description (do not use notes)
        final txMatch = txs.where((t) => (t.categoryId == e.key) || (t.description.trim() == e.key));
              if (txMatch.isNotEmpty) {
          final tx = txMatch.first;
          if (tx.billId != null && tx.billId!.isNotEmpty) {
            final bill = DatabaseService.getAllBills().firstWhere(
              (b) => b.id == tx.billId,
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
            if (bill.description != null && bill.description!.isNotEmpty) {
              label = bill.description!;
            } else {
              // Prefer transaction description; if empty, fall back to 'Unknown'
              // Normalize payment-style descriptions to the underlying
              // payee/payer name by stripping the 'Payment for' prefix and
              // any trailing date.
              label = tx.description.isNotEmpty ? extractPayeeName(tx.description) : 'Unknown';
            }
          } else {
            label = tx.description.isNotEmpty ? extractPayeeName(tx.description) : 'Unknown';
          }
        }
      }
      final color = _parseCategoryColor(cat);
      grouped[label] = (grouped[label] ?? 0) + e.value;
      groupedColor.putIfAbsent(label, () => color);
    }
    final List<_PieSlice> slices = grouped.entries.map((g) => _PieSlice(g.key, g.value, groupedColor[g.key] ?? Colors.grey)).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _currencyFormat.format(
                    _computeTotalForPeriodByCategoryFilter(start, end, type)
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: type == TransactionType.expense
                        ? AppTheme.expenseRed
                        : AppTheme.incomeGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _formatPeriodLabel(start, end),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            // Removed horizontal bar chart per UI request — show only the
            // scrollable details list. Keep similar vertical space so cards
            // maintain consistent height.
            SizedBox(
              height: 200,
              child: slices.isEmpty
                  ? const Center(child: Text('No data'))
                  : ReportDetailsList(
                      slices: slices,
                      total: total,
                      onRowTap: (s) => _openTransactionsForLabel(title, s.label, start, end, type: type),
                    ),
            ),
            const SizedBox(height: 8),
            if (slices.length > 6)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) {
                        return SafeArea(
                          child: SizedBox(
                            height: MediaQuery.of(ctx).size.height * 0.75,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: ReportDetailsList(
                                      slices: slices,
                                      total: total,
                                      onRowTap: (s) => _openTransactionsForLabel(title, s.label, start, end, type: type),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  child: const Text('See more'),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
  // Pie chart for payees (expenses)
  Widget _buildPayeePieChartCard({
    required BuildContext context,
    required List<Map<String, dynamic>> payees,
    required Set<String> selectedPayeeIds,
    required List<Category> categories,
    required DateTime start,
    required DateTime end,
  }) {
  // Exclude any payee records whose name is 'transfer' from report cards
  final visiblePayees = payees.where((p) => ((p['name'] ?? '').toString().trim().toLowerCase() != 'transfer')).toList();

  List<Transaction> txs = _transactionsExcludingTransfersRange(start, end)
    .where((t) => t.type == TransactionType.expense)
    .toList();
    // Using class-level helper extractPayeeName() for name extraction.
    if (selectedPayeeIds.isNotEmpty) {
      txs = txs.where((t) {
        final extractedName = extractPayeeName(t.description);
        // Match by payeeId or exact extracted name only (do not use notes)
        if (selectedPayeeIds.contains(t.payeeId)) return true;
        for (final id in selectedPayeeIds) {
          final payee = visiblePayees.firstWhere((p) => p['id'] == id, orElse: () => <String, dynamic>{});
          final name = (payee['name'] ?? '').toString().trim();
          if (name.isNotEmpty && (extractedName == name)) {
            return true;
          }
        }
        return false;
      }).toList();
    }
    final transferCategory = categories.firstWhere(
      (c) => c.name.trim().toLowerCase() == 'transfer',
      orElse: () => Category(id: '__no_transfer__', name: '', iconCodePoint: '', colorValue: '0xFF888888', isDefault: false, type: CategoryType.expense),
    );
    if (transferCategory.id != '__no_transfer__') {
      txs = txs.where((t) => t.categoryId != transferCategory.id).toList();
    }
    final Map<String, double> payeeTotals = {};
    for (final t in txs) {
      String? payeeId = t.payeeId;
      // Extract payee name from description for better matching
      final extractedName = extractPayeeName(t.description);
      // Try exact match first
      if (payeeId == null || payeeId.isEmpty) {
        for (final p in visiblePayees) {
          final name = (p['name'] ?? '').toString().trim();
          if (name.isNotEmpty && extractedName == name) {
            payeeId = p['id'];
            break;
          }
        }
      }
      // If transaction is linked to a bill, check if bill description matches payee name
      if ((payeeId == null || payeeId.isEmpty) && t.billId != null && t.billId!.isNotEmpty) {
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
        if (bill.description != null && bill.description!.isNotEmpty) {
          for (final p in visiblePayees) {
            final name = (p['name'] ?? '').toString().trim();
            if (name.isNotEmpty && bill.description!.trim() == name) {
              payeeId = p['id'];
              break;
            }
          }
        }
      }
      // Fallback: contains logic for legacy support — prefer the most specific match
      if (payeeId == null || payeeId.isEmpty) {
        final matches = <Map<String, dynamic>>[];
        final descLower = t.description.toLowerCase();
        for (final p in visiblePayees) {
          final name = (p['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final lname = name.toLowerCase();
          if (descLower.contains(lname)) {
            matches.add(p);
          }
        }
        if (matches.isNotEmpty) {
          // Prefer longest name (most specific)
          matches.sort((a, b) => b['name'].toString().length.compareTo(a['name'].toString().length));
          payeeId = matches.first['id'];
        }
      }
      payeeTotals[payeeId ?? extractedName] = (payeeTotals[payeeId ?? extractedName] ?? 0) + t.amount;
    }
    final total = payeeTotals.values.fold(0.0, (a, b) => a + b);
    // Group payee entries by display name so multiple payee records with the
    // same name are combined onto the same row.
    final Map<String, double> grouped = {};
    final Map<String, Color> groupedColor = {};
    for (final e in payeeTotals.entries) {
        Map<String, dynamic>? payee = visiblePayees.where((p) => p['id'] == e.key).cast<Map<String, dynamic>>().firstWhere(
          (p) => true,
          orElse: () {
            final match = visiblePayees.where((p) => (p['name'] ?? '').toString().trim().toLowerCase() == e.key.toString().trim().toLowerCase());
            return match.isNotEmpty ? match.first : <String, dynamic>{};
          },
        );
  String label = payee['name'] ?? 'Unknown';
  // Omit any payee entries containing 'transfer' which may otherwise
  // appear due to fallback matching from descriptions/bills.
  if (label.trim().toLowerCase().contains('transfer')) continue;
        if (payee['payerName'] != null && payee['payerName'].toString().isNotEmpty) {
          label = '${payee['name']} - ${payee['payerName']}';
        }
        if (label == 'Unknown') {
          final txMatchList = txs.where((t) => (t.payeeId == e.key) || ((t.payeeId == null || (t.payeeId?.isEmpty ?? true)) && (t.description.trim() == e.key))).toList();
          if (txMatchList.isNotEmpty) {
            // If all matching transactions are transfers, skip this entry.
            if (txMatchList.every((t) => _isTransferLike(t))) continue;
            // Prefer a non-transfer transaction when choosing a label.
            final tx = txMatchList.firstWhere((t) => !_isTransferLike(t));
            if (tx.billId != null && tx.billId!.isNotEmpty) {
              final bill = DatabaseService.getAllBills().firstWhere(
                (b) => b.id == tx.billId,
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
              if (bill.description != null && bill.description!.isNotEmpty) {
                label = bill.description!;
              } else {
                label = tx.description.isNotEmpty ? extractPayeeName(tx.description) : (tx.note ?? 'Unknown');
              }
            } else {
              label = tx.description.isNotEmpty ? extractPayeeName(tx.description) : (tx.note ?? 'Unknown');
            }
          }
        }
        Color color = AppTheme.expenseRed;
        if (payee['color'] != null) {
          try {
            color = Color(int.parse(payee['color']));
          } catch (_) {
            color = AppTheme.expenseRed;
          }
        }
        grouped[label] = (grouped[label] ?? 0) + e.value;
        groupedColor.putIfAbsent(label, () => color);
    }
    final List<_PieSlice> slices = grouped.entries.map((g) => _PieSlice(g.key, g.value, groupedColor[g.key] ?? AppTheme.expenseRed)).toList();
  return _buildPieChartCardGeneric(context: context, title: 'Payee', slices: slices, total: total, start: start, end: end);
  }
  // Returns the color for a given category, using its color property or a fallback
  Color _parseCategoryColor(Category category) {
    try {
      return category.color;
    } catch (_) {
      return Colors.grey;
    }
  }

  // Detect if a transaction is a transfer by category, description, or note.
  bool _isTransferLike(Transaction t) {
    final desc = t.description.toLowerCase();
    final note = (t.note ?? '').toLowerCase();
    if (desc.contains('transfer')) return true;
    if (note.contains('transfer')) return true;
    if (desc.startsWith('__transfer_manual__') || desc.startsWith('__transfer_bill__')) return true;
    try {
      final cat = _categories.firstWhere((c) => c.id == t.categoryId, orElse: () => Category(id: '', name: '', iconCodePoint: '', colorValue: '0xFF888888', isDefault: false, type: CategoryType.expense));
      if (cat.name.trim().toLowerCase() == 'transfer') return true;
    } catch (_) {}
    return false;
  }
  // Track whether payee or payer filter is active in the UI
  bool _showPayers = false;
  bool _showPayees = false;
  // Fallback color palette for categories
  static const List<Color> _fallbackPalette = [
    Color(0xFFEF5350), // Red
    Color(0xFFAB47BC), // Purple
    Color(0xFF5C6BC0), // Indigo
    Color(0xFF29B6F6), // Blue
    Color(0xFF66BB6A), // Green
    Color(0xFFFFCA28), // Amber
    Color(0xFFFF7043), // Deep Orange
    Color(0xFF8D6E63), // Brown
    Color(0xFF78909C), // Blue Grey
    Color(0xFFD4E157), // Lime
    Color(0xFF26A69A), // Teal
    Color(0xFFEC407A), // Pink
  ];

  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$');
  String _selectedPeriod = 'This Month';
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  // When true, the custom mode represents a 6-month window starting at
  // _customSixMonthStart (first day of selected month). This allows users
  // to pick which 6-month period the monthly trend should display.
  bool _useCustomSixMonth = false;
  DateTime? _customSixMonthStart;

  // Selected category ids for filtering (empty = all)
  final Set<String> _selectedCategoryIds = {};
  // Selected payee ids for filtering (empty = all)
  final Set<String> _selectedPayeeIds = {};

  // Cached categories for the selector
  List<Category> _categories = [];
  // Cached payees for the selector
  List<Map<String, dynamic>> _payees = [];

  // Listeners
  VoidCallback? _categoriesListener;
  VoidCallback? _payeesListener;
  VoidCallback? _subscriptionListener;

  void _loadCategories() async {
    final cats = DatabaseService.getAllCategories();
    setState(() {
      _categories = cats;
    });
  }

  void _loadPayees() async {
    final payees = DatabaseService.getAllPayees();
    setState(() {
      _payees = payees;
    });
  }

  // Helper: get transactions in range but exclude any that are categorized as 'Transfer'
  List<Transaction> _transactionsExcludingTransfersRange(DateTime start, DateTime end) {
    final allTxs = DatabaseService.getTransactionsByDateRange(start, end).toList();
    final transferCategory = _categories.firstWhere(
      (c) => c.name.trim().toLowerCase() == 'transfer',
      orElse: () => Category(
        id: '__no_transfer__',
        name: '',
        iconCodePoint: '',
        colorValue: '0xFF888888',
        isDefault: false,
        type: CategoryType.expense,
      ),
    );
    List<Transaction> filtered = allTxs;
    if (transferCategory.id != '__no_transfer__') {
      filtered = filtered.where((t) => t.categoryId != transferCategory.id).toList();
    }
    // Additionally exclude transactions whose description or note contain
    // the word 'transfer' (case-insensitive) or legacy transfer markers.
    filtered = filtered.where((t) {
      final desc = t.description.toLowerCase();
      final note = (t.note ?? '').toLowerCase();
      if (desc.contains('transfer')) return false;
      if (note.contains('transfer')) return false;
      if (desc.startsWith('__transfer_manual__') || desc.startsWith('__transfer_bill__')) return false;
      return true;
    }).toList();
    return filtered;
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadPayees();

    _categoriesListener = () {
      _loadCategories();
    };
    DatabaseService.categoriesVersion.addListener(_categoriesListener!);

    _payeesListener = () {
      _loadPayees();
    };
    DatabaseService.payeesVersion.addListener(_payeesListener!);
  }

  @override
  void dispose() {
    if (_categoriesListener != null) {
      DatabaseService.categoriesVersion.removeListener(_categoriesListener!);
    }
    if (_payeesListener != null) {
      DatabaseService.payeesVersion.removeListener(_payeesListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSubscriber = DatabaseService.subscriptionVersion.value != 'Free';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: openRootDrawer,
        ),
        title: const Text('Reports'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
                if (value == 'ManageCards') {
                // Navigate to the Manage Cards screen and refresh on return
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageCardsScreen()));
                // Rebuild to pick up any visibility changes
                if (mounted) setState(() {});
                return;
              }
              if (value == 'Custom') {
                if (!isSubscriber) return;
                // Let the user choose between an exact date range or selecting
                // a 6-month window anchored at a chosen month.
                final choice = await showModalBottomSheet<String?>(
                  context: context,
                  builder: (ctx) {
                    return SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: const Text('Custom Date Range for Income and Expenses'),
                            subtitle: Text(
                              'Pick a start and end date to show the details for the custom dates.',
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                            ),
                            onTap: () => Navigator.of(ctx).pop('range'),
                          ),
                          ListTile(
                            title: const Text('6-month Trend Date Range'),
                            subtitle: Text(
                              'Select a month to show that month and the next 5 months.',
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                            ),
                            onTap: () => Navigator.of(ctx).pop('sixmonth'),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  },
                );
                if (choice == 'range') {
                  final now = DateTime.now();
                  final first = DateTime(now.year - 5);
                  final last = DateTime(now.year + 5);
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: first,
                    lastDate: last,
                    initialDateRange: _customStartDate != null && _customEndDate != null
                        ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
                        : DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
                  );
                  if (!mounted) return;
                  if (picked != null) {
                    setState(() {
                      _customStartDate = picked.start;
                      _customEndDate = picked.end;
                      _useCustomSixMonth = false;
                      _customSixMonthStart = null;
                      _selectedPeriod = 'Custom';
                    });
                  }
                } else if (choice == 'sixmonth') {
                  // Let the user pick any date — we'll use its month as the anchor.
                  final now = DateTime.now();
                  final first = DateTime(now.year - 10);
                  final last = DateTime(now.year + 10);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _customSixMonthStart ?? now,
                    firstDate: first,
                    lastDate: last,
                    helpText: 'Pick the month to start the 6-month window',
                    cancelText: 'Cancel',
                    confirmText: 'Select',
                  );
                  if (!mounted) return;
                  if (picked != null) {
                    final anchor = DateTime(picked.year, picked.month, 1);
                    setState(() {
                      // Only update the six-month anchor. Do NOT set the
                      // global _customStartDate/_customEndDate so other cards
                      // that use the custom date range are not affected.
                      _customSixMonthStart = anchor;
                      _useCustomSixMonth = true;
                      _selectedPeriod = 'Custom';
                    });
                  }
                }
              } else {
                setState(() {
                  _selectedPeriod = value;
                });
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'ManageCards', child: Text('Manage Cards')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'This Week', child: Text('This Week')),
              const PopupMenuItem(value: 'This Month', child: Text('This Month')),
              const PopupMenuItem(value: 'This Year', child: Text('This Year')),
              if (isSubscriber)
                const PopupMenuItem(value: 'Custom', child: Text('Custom Date')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshReports,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCategoryFilterSection(),
                const SizedBox(height: 8),
                _buildPayeeFilterSection(),
                const SizedBox(height: 12),
                _buildSummaryCards(),
                const SizedBox(height: 24),
                BannerAdWidget(),
              ],
            ),
          ),
        ),
      ),
    );
  }

// Pie chart for payers (income)
Widget _buildPayerPieChartCard({
  required BuildContext context,
  required List<Map<String, dynamic>> payees,
  required Set<String> selectedPayeeIds,
  required List<Category> categories,
  required DateTime start,
  required DateTime end,
}) {
  // Exclude any payee/payer records whose name is 'transfer' from report cards
  final visiblePayees = payees.where((p) => ((p['name'] ?? '').toString().trim().toLowerCase() != 'transfer')).toList();

  List<Transaction> txs = _transactionsExcludingTransfersRange(start, end)
    .where((t) => t.type == TransactionType.income)
    .toList();
        if (_selectedPayeeIds.isNotEmpty) {
          txs = txs.where((t) {
            final extractedName = extractPayeeName(t.description);
            // Match by payeeId or exact extracted name only (do not use notes)
            if (_selectedPayeeIds.contains(t.payeeId)) return true;
            for (final id in _selectedPayeeIds) {
              final payee = visiblePayees.firstWhere((p) => p['id'] == id, orElse: () => <String, dynamic>{});
              final name = (payee['name'] ?? '').toString().trim();
              if (name.isNotEmpty && (extractedName == name)) {
                return true;
              }
            }
            return false;
          }).toList();
    }
  final transferCategory = categories.firstWhere(
    (c) => c.name.trim().toLowerCase() == 'transfer',
    orElse: () => Category(id: '__no_transfer__', name: '', iconCodePoint: '', colorValue: '0xFF888888', isDefault: false, type: CategoryType.income),
  );
  if (transferCategory.id != '__no_transfer__') {
    txs = txs.where((t) => t.categoryId != transferCategory.id).toList();
  }
  final Map<String, double> payerTotals = {};
    for (final t in txs) {
    String? payerId = t.payerId;
    // If transaction is linked to a bill, check if bill description matches a payer name
    if ((payerId == null || payerId.isEmpty) && t.billId != null && t.billId!.isNotEmpty) {
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
      if (bill.description != null && bill.description!.isNotEmpty) {
        for (final p in visiblePayees) {
          final name = (p['name'] ?? '').toString().trim();
          if (name.isNotEmpty && bill.description!.trim() == name) {
            payerId = p['id'];
            break;
          }
        }
      }
    }
    // If still no payerId, try to match by name in description only (not notes)
    if (payerId == null || payerId.isEmpty) {
      for (final p in visiblePayees) {
        final name = (p['name'] ?? '').toString().trim();
        if (name.isNotEmpty && t.description.contains(name)) {
          payerId = p['id'];
          break;
        }
      }
    }
    payerTotals[payerId ?? ''] = (payerTotals[payerId ?? ''] ?? 0) + t.amount;
  }
  final total = payerTotals.values.fold(0.0, (a, b) => a + b);
  // Group entries by display name so multiple payer records with the same
  // name are combined onto the same row.
  final Map<String, double> grouped = {};
  final Map<String, Color> groupedColor = {};
  for (final e in payerTotals.entries) {
    Map<String, dynamic>? payer = visiblePayees.where((p) => p['id'] == e.key).cast<Map<String, dynamic>>().firstWhere(
      (p) => true,
      orElse: () {
        final match = visiblePayees.where((p) => (p['name'] ?? '').toString().trim().toLowerCase() == e.key.toString().trim().toLowerCase());
        return match.isNotEmpty ? match.first : <String, dynamic>{};
      },
    );
  String label = payer['name'] ?? 'Unknown';
  // Omit any payer entries containing 'transfer' to keep reports clean.
  if (label.trim().toLowerCase().contains('transfer')) continue;
    if (payer['payeeName'] != null && payer['payeeName'].toString().isNotEmpty) {
      label = '${payer['payeeName']} - ${payer['name']}';
    }
    if (label == 'Unknown') {
      final txMatchList = txs.where((t) => (t.payerId == e.key) || ((t.payerId == null || (t.payerId?.isEmpty ?? true)) && ((t.description.trim() == e.key) || (t.note?.trim() == e.key)))).toList();
      if (txMatchList.isNotEmpty) {
        // If all matching transactions are transfers, skip this entry.
        if (txMatchList.every((t) => _isTransferLike(t))) continue;
        final tx = txMatchList.firstWhere((t) => !_isTransferLike(t));
        if (tx.billId != null && tx.billId!.isNotEmpty) {
          final bill = DatabaseService.getAllBills().firstWhere(
            (b) => b.id == tx.billId,
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
          if (bill.description != null && bill.description!.isNotEmpty) {
            label = bill.description!;
          } else {
            label = tx.description.isNotEmpty ? extractPayeeName(tx.description) : (tx.note ?? 'Unknown');
          }
        } else {
          label = tx.description.isNotEmpty ? extractPayeeName(tx.description) : (tx.note ?? 'Unknown');
        }
      }
    }
    Color color = AppTheme.incomeGreen;
    if (payer['color'] != null) {
      try {
        color = Color(int.parse(payer['color']));
      } catch (_) {
        color = AppTheme.incomeGreen;
      }
    }
    grouped[label] = (grouped[label] ?? 0) + e.value;
    groupedColor.putIfAbsent(label, () => color);
  }
  final List<_PieSlice> slices = grouped.entries.map((g) => _PieSlice(g.key, g.value, groupedColor[g.key] ?? AppTheme.incomeGreen)).toList();
  return _buildPieChartCardGeneric(context: context, title: 'Payer', slices: slices, total: total, start: start, end: end);
}

// Card that shows net amount for names that exist both as a payee and a payer
Widget _buildPayeePayerNetCard({
  required BuildContext context,
  required DateTime start,
  required DateTime end,
}) {
  // Get transactions in range excluding transfers
  final txs = _transactionsExcludingTransfersRange(start, end);

  // Build map of name -> list of payee/payer entries, excluding any named 'transfer'
  // Determine names that appear as BOTH a payee and a payer (explicit lists only).
  final payeeNames = <String>{};
  final payerNames = <String>{};
  for (final p in _payees) {
    final name = ((p['name'] ?? '') as String).toString().trim();
    if (name.isEmpty) continue;
    final lname = name.toLowerCase();
    if (lname == 'transfer') continue;
    final type = (p['type'] as String?)?.toLowerCase() ?? '';
    if (type == 'payee') payeeNames.add(name);
    if (type == 'payer') payerNames.add(name);
  }

  // Only consider names that are present in both lists
  final commonNames = payeeNames.intersection(payerNames);

  final List<Map<String, dynamic>> results = [];

  for (final name in commonNames) {
    final items = _payees.where((p) => ((p['name'] ?? '').toString().trim() == name)).toList();

  // Collect ids for matching (from the explicit payee/payer records)
  final payeeIds = items.where((p) => (p['type'] as String?)?.toLowerCase() == 'payee').map((p) => p['id'] as String?).whereType<String>().toSet();
  final payerIds = items.where((p) => (p['type'] as String?)?.toLowerCase() == 'payer').map((p) => p['id'] as String?).whereType<String>().toSet();

    double totalIncome = 0.0;
    double totalExpense = 0.0;

    for (final t in txs) {
      // Loose substring fallback: count the transaction when either the
      // explicit ID matches OR the transaction description/note contains
      // the normalized name. This allows legacy transactions like
      // "Payment for Bill Name" to be associated with the name.
      final desc = t.description.toLowerCase();
      final lname = name.toLowerCase();

      if (t.type == TransactionType.income) {
        // Match by explicit payerId OR description only (do not use note)
        if ((t.payerId != null && payerIds.contains(t.payerId)) || desc.contains(lname)) {
          totalIncome += t.amount;
        }
      } else if (t.type == TransactionType.expense) {
        // Match by explicit payeeId OR description only (do not use note)
        if ((t.payeeId != null && payeeIds.contains(t.payeeId)) || desc.contains(lname)) {
          totalExpense += t.amount;
        }
      }
    }

    final net = totalIncome - totalExpense;
    // Only include names that had activity on BOTH sides (income and expense)
    // for the selected period — this ensures the Payee vs Payer card only
    // shows entries that actually act as both a payee and a payer during
    // the timeframe the user selected.
    if ((totalIncome - 0.0).abs() > 0.0 && (totalExpense - 0.0).abs() > 0.0) {
      results.add({'name': name, 'income': totalIncome, 'expense': totalExpense, 'net': net});
    }
  }

  // Sort by absolute net descending
  results.sort((a, b) => b['net'].abs().compareTo(a['net'].abs()));

  final overallNet = results.fold<double>(0, (s, r) => s + (r['net'] as double));

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('Payee vs Payer Net Totals', style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text(_currencyFormat.format(overallNet), style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 6),
          Text(_formatPeriodLabel(start, end), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 12),
          SizedBox(
            // keep a reasonable fixed inline height and let the inner list scroll
            height: results.isEmpty ? 60 : 200,
            child: results.isEmpty
                ? const Center(child: Text('No matching payee/payer names'))
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx2, i) {
                      final r = results[i];
                      final net = r['net'] as double;
                      final color = net >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed;
                      final sumAbsAll = results.fold<double>(0, (s, it) => s + ((it['net'] as double).abs()));
                      final percentAll = sumAbsAll > 0 ? ((net.abs() / sumAbsAll) * 100) : 0.0;
                      return InkWell(
                        onTap: () => _openTransactionsForLabel('Payee vs Payer', r['name'] as String, start, end, filterOverride: 'both'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Expanded(child: Text(r['name'] as String, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 10),
                              Text(_currencyFormat.format(net), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w400, color: color)),
                              const SizedBox(width: 10),
                              Text('${percentAll.toStringAsFixed(1)}%', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (results.length > 6)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) {
                      return SafeArea(
                        child: SizedBox(
                          height: MediaQuery.of(ctx).size.height * 0.75,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Payee vs Payer Net Totals (All)', style: Theme.of(ctx).textTheme.titleLarge),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: results.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (ctx2, i) {
                                      final r = results[i];
                                      final net = r['net'] as double;
                                      final color = net >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed;
                                      final sumAbsAll = results.fold<double>(0, (s, it) => s + ((it['net'] as double).abs()));
                                      final percentAll = sumAbsAll > 0 ? ((net.abs() / sumAbsAll) * 100) : 0.0;
                                      return InkWell(
                                        onTap: () => _openTransactionsForLabel('Payee vs Payer', r['name'] as String, start, end, filterOverride: 'both'),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                              const SizedBox(width: 6),
                                              Expanded(child: Text(r['name'] as String, style: Theme.of(ctx2).textTheme.bodySmall)),
                                              const SizedBox(width: 10),
                                              Text(_currencyFormat.format(net), style: Theme.of(ctx2).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w400, color: color)),
                                              const SizedBox(width: 10),
                                              Text('${percentAll.toStringAsFixed(1)}%', style: Theme.of(ctx2).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                child: const Text('See more'),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

// Card that shows net totals broken down by category (expense vs income)
Widget _buildExpenseIncomeNetCard({
  required BuildContext context,
  required DateTime start,
  required DateTime end,
}) {
  // Get transactions in range and exclude transfers
  final allTxs = _transactionsExcludingTransfersRange(start, end).toList();
  final transferCategory = _categories.firstWhere(
    (c) => c.name.trim().toLowerCase() == 'transfer',
    orElse: () => Category(
      id: '__no_transfer__',
      name: '',
      iconCodePoint: '',
      colorValue: '0xFF888888',
      isDefault: false,
      type: CategoryType.expense,
    ),
  );
  final txs = (transferCategory.id != '__no_transfer__')
      ? allTxs.where((t) => t.categoryId != transferCategory.id).toList()
      : allTxs;

  // Map category name -> totals
  final Map<String, double> incomeTotals = {};
  final Map<String, double> expenseTotals = {};

  for (final t in txs) {
    String catName = 'Unknown';
    try {
      final cat = _categories.firstWhere((c) => c.id == t.categoryId);
      catName = cat.name;
    } catch (_) {
      catName = 'Unknown';
    }

    if (t.type == TransactionType.income) {
      incomeTotals[catName] = (incomeTotals[catName] ?? 0) + t.amount;
    } else if (t.type == TransactionType.expense) {
      expenseTotals[catName] = (expenseTotals[catName] ?? 0) + t.amount;
    }
  }

  // Build results list — only include category names that appear in BOTH
  // income and expense (behaves like Payee vs Payer net totals card).
  final Set<String> categoryNames = incomeTotals.keys.toSet().intersection(expenseTotals.keys.toSet());
  final List<Map<String, dynamic>> results = [];
  for (final name in categoryNames) {
    final inc = incomeTotals[name] ?? 0.0;
    final exp = expenseTotals[name] ?? 0.0;
    final net = inc - exp;
    // Omit categories containing 'transfer'
    if (name.trim().toLowerCase().contains('transfer')) continue;
    // Only include categories that have activity on BOTH sides (income
    // and expense). Previously we included a category if either side had
    // activity; the user requested to show items only when they appear in
    // both lists.
    if ((inc - 0.0).abs() > 0.0 && (exp - 0.0).abs() > 0.0) {
      results.add({'name': name, 'income': inc, 'expense': exp, 'net': net});
    }
  }

  // Sort by absolute net descending
  results.sort((a, b) => b['net'].abs().compareTo(a['net'].abs()));

  final overallNet = results.fold<double>(0, (s, r) => s + (r['net'] as double));

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('Expense vs Income Net Totals', style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(_currencyFormat.format(overallNet), style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 6),
          Text(_formatPeriodLabel(start, end), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 12),
          SizedBox(
            // keep a reasonable fixed inline height and let the inner list scroll
            height: results.isEmpty ? 60 : 200,
            child: results.isEmpty
                ? const Center(child: Text('No category activity'))
        : ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final r = results[idx];
                      final net = (r['net'] as double);
                      final color = net >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed;

                      final sumAbs = results.fold<double>(0, (s, it) => s + ((it['net'] as double).abs()));
                      final percent = sumAbs > 0 ? ((net.abs() / sumAbs) * 100) : 0.0;

                      return InkWell(
                        onTap: () => _openTransactionsForLabel('Category', r['name'] as String, start, end, filterOverride: 'category_both'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Expanded(child: Text(r['name'] as String, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 10),
                              Text(_currencyFormat.format(net), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w400, color: color)),
                              const SizedBox(width: 10),
                              Text('${percent.toStringAsFixed(1)}%', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (results.length > 6)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) {
                      return SafeArea(
                        child: SizedBox(
                          height: MediaQuery.of(ctx).size.height * 0.75,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Expense vs Income Net Totals (All)', style: Theme.of(ctx).textTheme.titleLarge),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: results.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (ctx2, i) {
                                      final r = results[i];
                                      final net = r['net'] as double;
                                      final color = net >= 0 ? AppTheme.incomeGreen : AppTheme.expenseRed;
                                      final sumAbsAll = results.fold<double>(0, (s, it) => s + ((it['net'] as double).abs()));
                                      final percentAll = sumAbsAll > 0 ? ((net.abs() / sumAbsAll) * 100) : 0.0;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                            const SizedBox(width: 6),
                                            Expanded(child: Text(r['name'] as String, style: Theme.of(ctx2).textTheme.bodySmall)),
                                            const SizedBox(width: 10),
                                            Text(_currencyFormat.format(net), style: Theme.of(ctx2).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w400, color: color)),
                                            const SizedBox(width: 10),
                                            Text('${percentAll.toStringAsFixed(1)}%', style: Theme.of(ctx2).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                child: const Text('See more'),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

// Generic pie chart card for payee/payer
Widget _buildPieChartCardGeneric({
  required BuildContext context,
  required String title,
  required List<_PieSlice> slices,
  required double total,
  required DateTime start,
  required DateTime end,
}) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _currencyFormat.format(total),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: title == 'Payee'
                      ? AppTheme.expenseRed
                      : title == 'Payer'
                          ? AppTheme.incomeGreen
                          : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            // show period label under the title so users know what period the card covers
            // Call the local helper directly to ensure custom ranges that match
            // an entire month are rendered as "Month of <Month Year>".
            _formatPeriodLabel(start, end),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: slices.isEmpty
                ? const Center(child: Text('No data'))
                : ReportDetailsList(
                    slices: slices,
                    total: total,
                    onRowTap: (s) => _openTransactionsForLabel(
                      title,
                      s.label,
                      start,
                      end,
                      type: title == 'Payee'
                          ? TransactionType.expense
                          : title == 'Payer'
                              ? TransactionType.income
                              : null,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          if (slices.length > 6)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) {
                      return SafeArea(
                        child: SizedBox(
                          height: MediaQuery.of(ctx).size.height * 0.75,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                                const SizedBox(height: 12),
                                Expanded(
                                    child: ReportDetailsList(
                                    slices: slices,
                                    total: total,
                                    onRowTap: (s) => _openTransactionsForLabel(
                                      title,
                                      s.label,
                                      start,
                                      end,
                                      type: title == 'Payee'
                                          ? TransactionType.expense
                                          : title == 'Payer'
                                              ? TransactionType.income
                                              : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                child: const Text('See more'),
              ),
            ),
          const SizedBox(height: 24),
          // Total line removed for payee/payer cards
        ],
      ),
    ),
  );
}

  Widget _buildSummaryCards() {
    // Determine period start/end based on the selected period
    final now = DateTime.now();
    DateTime start;
    DateTime end;

    if (_selectedPeriod == 'This Week') {
      final weekday = now.weekday;
      start = DateTime(now.year, now.month, now.day).subtract(Duration(days: weekday - 1));
      end = start.add(const Duration(days: 6));
    } else if (_selectedPeriod == 'This Year') {
      start = DateTime(now.year, 1, 1);
      end = DateTime(now.year, 12, 31);
    } else if (_selectedPeriod == 'Custom' && _customStartDate != null && _customEndDate != null) {
      start = _customStartDate!;
      end = _customEndDate!;
    } else {
      // Default to this month
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 1).subtract(const Duration(days: 1));
    }

  // Determine visible cards
  final savedVisible = DatabaseService.getSetting<List<dynamic>>('reportsVisibleCards', null);
  final visibleSet = (savedVisible == null)
      ? <String>{
          'summary_totals',
          'expenses_pie',
          'income_pie',
          'payee_pie',
          'payer_pie',
          'payee_payer_net',
          'expense_income_net',
          'monthly_trend',
        }
      : savedVisible.map((e) => e.toString()).toSet();

  // Always show full totals for summary cards, ignoring filters, but exclude transfers
  final filteredTxs = _transactionsExcludingTransfersRange(start, end);
  final totalIncome = filteredTxs
    .where((t) => t.type == TransactionType.income)
    .fold<double>(0, (sum, t) => sum + t.amount);
  final totalExpense = filteredTxs
    .where((t) => t.type == TransactionType.expense)
    .fold<double>(0, (sum, t) => sum + t.amount);
  final net = totalIncome - totalExpense;
  final children = <Widget>[];

    if (visibleSet.contains('summary_totals')) {
      children.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('Income', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          _currencyFormat.format(totalIncome),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppTheme.incomeGreen),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('Expenses', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          _currencyFormat.format(totalExpense),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppTheme.expenseRed),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('Net', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(_currencyFormat.format(net),
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                ],
            ),
          ),
        ),
      );
      children.add(const SizedBox(height: 12));
    }
    // Build the PageView children dynamically based on visibility
    final pageChildren = <Widget>[];
    if (visibleSet.contains('expenses_pie')) {
      pageChildren.add(_buildCategoryPieChartCard(
        context: context,
        title: 'Expenses',
        type: TransactionType.expense,
        start: start,
        end: end,
      ));
    }
    if (visibleSet.contains('income_pie')) {
      pageChildren.add(_buildCategoryPieChartCard(
        context: context,
        title: 'Income',
        type: TransactionType.income,
        start: start,
        end: end,
      ));
    }
    if (visibleSet.contains('payee_pie')) {
      pageChildren.add(_buildPayeePieChartCard(
        context: context,
        payees: _payees,
        selectedPayeeIds: _selectedPayeeIds,
        categories: _categories,
        start: start,
        end: end,
      ));
    }
    if (visibleSet.contains('payer_pie')) {
      pageChildren.add(_buildPayerPieChartCard(
        context: context,
        payees: _payees,
        selectedPayeeIds: _selectedPayeeIds,
        categories: _categories,
        start: start,
        end: end,
      ));
    }
    if (visibleSet.contains('payee_payer_net')) {
      pageChildren.add(_buildPayeePayerNetCard(context: context, start: start, end: end));
    }
    if (visibleSet.contains('expense_income_net')) {
      pageChildren.add(_buildExpenseIncomeNetCard(context: context, start: start, end: end));
    }

    if (pageChildren.isNotEmpty) {
      final screenHeight = MediaQuery.of(context).size.height;
      children.add(
        SizedBox(
           height: screenHeight * 0.45, // ~45% of screen height
          child: PageView(children: pageChildren),
        ),
      );
      children.add(const SizedBox(height: 14));
    }

    if (visibleSet.contains('monthly_trend')) {
      children.add(_buildMonthlyTrendChart());
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);

  }

  Widget _buildMonthlyTrendChart() {
    // Get last 6 months of data
    final now = DateTime.now();
    final months = <String>[];
    final incomeData = <double>[];
    final expenseData = <double>[];

    // Get transfer category id (case-insensitive)
    final transferCategory = _categories.firstWhere(
      (c) => c.name.trim().toLowerCase() == 'transfer',
      orElse: () => Category(
        id: '__no_transfer__',
        name: '',
        iconCodePoint: '',
        colorValue: '0xFF888888',
        isDefault: false,
        type: CategoryType.expense,
      ),
    );

  // If the user selected a custom 6-month window, use that anchor. Otherwise
  // default to current month + previous 5 months (current month ends at 'now').
  if (_selectedPeriod == 'Custom' && _useCustomSixMonth && _customSixMonthStart != null) {
    final anchor = _customSixMonthStart!; // first day of selected month
    for (int i = 0; i < 6; i++) {
    final month = DateTime(anchor.year, anchor.month + i, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 1).subtract(const Duration(days: 1));

    months.add(DateFormat.MMM().format(month));

    // Get transactions for the month (start..endOfMonth)
    final monthTxs = DatabaseService.getTransactionsByDateRange(month, endOfMonth);
    // Exclude transfers
    final filteredTxs = (transferCategory.id != '__no_transfer__')
      ? monthTxs.where((t) => t.categoryId != transferCategory.id).toList()
      : monthTxs;
    final monthIncome =
      filteredTxs.where((t) => t.type == TransactionType.income).fold<double>(0, (s, t) => s + t.amount);
    final monthExpense =
      filteredTxs.where((t) => t.type == TransactionType.expense).fold<double>(0, (s, t) => s + t.amount);
    incomeData.add(monthIncome);
    expenseData.add(monthExpense);
    }
  } else {
    // Ensure the chart always shows the current month plus the previous 5 months.
    // Use the first day of the current month as the anchor so the set is stable
    // immediately when the 1st of the month arrives. For the current month we
    // only include data up to 'now' so the chart reflects up-to-date values.
    final currentMonthStart = DateTime(now.year, now.month, 1);
    for (int i = 5; i >= 0; i--) {
    final month = DateTime(currentMonthStart.year, currentMonthStart.month - i, 1);
    // For past months use the month end; for the current month use today so
    // the chart updates as soon as the new month begins.
    final endOfMonth = (i == 0)
      ? now
      : DateTime(month.year, month.month + 1, 1).subtract(const Duration(days: 1));

    months.add(DateFormat.MMM().format(month));

    // Get transactions for the month (start..endOfMonth)
    final monthTxs = DatabaseService.getTransactionsByDateRange(month, endOfMonth);
      // Exclude transfers
    final filteredTxs = (transferCategory.id != '__no_transfer__')
      ? monthTxs.where((t) => t.categoryId != transferCategory.id).toList()
      : monthTxs;
    final monthIncome =
      filteredTxs.where((t) => t.type == TransactionType.income).fold<double>(0, (s, t) => s + t.amount);
    final monthExpense =
      filteredTxs.where((t) => t.type == TransactionType.expense).fold<double>(0, (s, t) => s + t.amount);
    incomeData.add(monthIncome);
    expenseData.add(monthExpense);
    }
  }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('6-Month Trend', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(enabled: false),
                  minY: _computeMinYForBarChart(incomeData, expenseData),
                  maxY: _computeMaxYForBarChart(incomeData, expenseData),
                  barGroups: List.generate(months.length, (index) {
                    final income = incomeData[index];
                    final expense = expenseData[index];
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: income,
                          color: AppTheme.incomeGreen,
                          width: 8,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        BarChartRodData(
                          toY: expense,
                          color: Theme.of(context).colorScheme.error,
                          width: 8,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                      barsSpace: 4,
                    );
                  }),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i >= 0 && i < months.length) {
                            return Text(months[i], style: Theme.of(context).textTheme.bodySmall);
                          }
                          return const Text('');
                        },
                        reservedSize: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Builder(builder: (context) {
              final totalIncome = incomeData.fold<double>(0, (s, v) => s + v);
              final totalExpense = expenseData.fold<double>(0, (s, v) => s + v);
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem('Income', AppTheme.incomeGreen,
                      subtitle: _currencyFormat.format(totalIncome)),
                  const SizedBox(width: 24),
                  _buildLegendItem('Expenses', AppTheme.expenseRed,
                      subtitle: _currencyFormat.format(totalExpense)),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, {String? subtitle}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            if (subtitle != null)
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12)),
          ],
        ),
      ],
    );
  }

  double _computeMaxYForBarChart(List<double> income, List<double> expense) {
    double maxVal = 0;
    for (final v in income) {
      if (v > maxVal) maxVal = v;
    }
    for (final v in expense) {
      if (v > maxVal) maxVal = v;
    }
    if (maxVal <= 0) return 10.0;
    // Add 15% headroom so tallest bar isn't flush with the top
    return (maxVal * 1.15).ceilToDouble();
  }

  double _computeMinYForBarChart(List<double> income, List<double> expense) {
    double minVal = 0;
    for (final v in income) {
      if (v < minVal) minVal = v;
    }
    for (final v in expense) {
      if (v < minVal) minVal = v;
    }
    if (minVal >= 0) return 0.0;
    // Add 15% padding below the lowest negative value
    return (minVal * 1.15).floorToDouble();
  }

  /// Build a dropdown-like ListTile that opens a modal to multi-select categories.
  Widget _buildCategoryFilterSection() {
  final isSubscriber = DatabaseService.subscriptionVersion.value != 'Free';
    if (!isSubscriber) {
      return Card(
        color: Colors.blueGrey[50],
        child: ListTile(
          title: Text('Filter by Categories', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.blueGrey[900])),
          subtitle: const Text('Subscribe to use category filters', style: TextStyle(color: Colors.blueGrey)),
          trailing: const Icon(Icons.lock, color: Colors.blueGrey),
        ),
      );
    }
    if (_categories.isEmpty) return const SizedBox.shrink();

    String subtitle;
    if (_selectedCategoryIds.isEmpty) {
      subtitle = 'All categories';
    } else if (_selectedCategoryIds.length == 1) {
      final id = _selectedCategoryIds.first;
      subtitle =
          _categories.firstWhere((c) => c.id == id, orElse: () => _categories.first).name;
    } else {
      subtitle = '${_selectedCategoryIds.length} selected';
    }

    return Card(
      child: ListTile(
        title: Text('Filter by Categories', style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedCategoryIds.isNotEmpty)
              IconButton(
                tooltip: 'Clear categories',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  setState(() {
                    _selectedCategoryIds.clear();
                  });
                },
              ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
        onTap: () async {
          bool changed = false;
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) {
              final tempSelected = Set<String>.from(_selectedCategoryIds);
              var showIncome = false;
              return StatefulBuilder(
                builder: (context, sb) {
                  void saveAndClose() {
                    setState(() {
                      _selectedCategoryIds
                        ..clear()
                        ..addAll(tempSelected);
                    });
                    changed = true;
                    Navigator.of(ctx).pop();
                  }
                  void clearAndClose() {
                    setState(() {
                      _selectedCategoryIds.clear();
                    });
                    changed = true;
                    Navigator.of(ctx).pop();
                  }
                  return FractionallySizedBox(
                    heightFactor: 0.75,
                    child: Column(
                      children: [
                        AppBar(
                          automaticallyImplyLeading: false,
                          title: const Text('Select categories'),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          actions: [
                            IconButton(
                              tooltip: 'Clear selection',
                              icon: const Icon(Icons.clear),
                              onPressed: clearAndClose,
                            ),
                          ],
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Expenses'),
                                    selected: !showIncome,
                                    onSelected: (s) {
                                      sb(() {
                                        showIncome = false;
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('Income'),
                                    selected: showIncome,
                                    onSelected: (s) {
                                      sb(() {
                                        showIncome = true;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: clearAndClose,
                                  icon: const Icon(Icons.clear, size: 18),
                                  label: const Text('Clear selection'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _categories
                                .where((c) => showIncome
                                    ? c.type == CategoryType.income
                                    : c.type == CategoryType.expense)
                                .length,
                            itemBuilder: (context, index) {
                              final filtered = _categories
                                  .where((c) => showIncome
                                      ? c.type == CategoryType.income
                                      : c.type == CategoryType.expense)
                                  .toList();
                              final c = filtered[index];
                              final selected = tempSelected.contains(c.id);
                              return CheckboxListTile(
                                title: Text(c.name),
                                value: selected,
                                onChanged: (v) {
                                  sb(() {
                                    if (v == true) {
                                      tempSelected.add(c.id);
                                    } else {
                                      tempSelected.remove(c.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                  },
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextButton(
                                  onPressed: saveAndClose,
                                  child: const Text('Done'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
          if (changed) setState(() {});
        },
      ),
    );
  }

  /// Payee/Payer selector below categories. Multi-select to mirror categories.
  Widget _buildPayeeFilterSection() {
  final isSubscriber = DatabaseService.subscriptionVersion.value != 'Free';
    if (!isSubscriber) {
      return Card(
        color: Colors.blueGrey[50],
        child: ListTile(
          title: Text('Filter by Payee/Payer', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.blueGrey[900])),
          subtitle: const Text('Subscribe to use payee filters', style: TextStyle(color: Colors.blueGrey)),
          trailing: const Icon(Icons.lock, color: Colors.blueGrey),
        ),
      );
    }
    // Compute subtitle
    String subtitle;
    if (_payees.isEmpty) {
      subtitle = 'No payees';
    } else if (_selectedPayeeIds.isEmpty) {
      subtitle = _showPayers ? 'All payers' : 'All payees';
    } else if (_selectedPayeeIds.length == 1) {
      final id = _selectedPayeeIds.first;
      final found = _payees.firstWhere(
        (p) => p['id'] == id && p['type'] == (_showPayers ? 'payer' : 'payee'),
        orElse: () => <String, dynamic>{},
      );
      subtitle = (found['name'] ?? 'Unknown') as String;
    } else {
      subtitle = '${_selectedPayeeIds.length} selected';
    }

    return Card(
      child: ListTile(
        title: Text('Filter by Payee/Payer', style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedPayeeIds.isNotEmpty)
              IconButton(
                tooltip: 'Clear payees',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  setState(() {
                    _selectedPayeeIds.clear();
                  });
                },
              ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
        onTap: () async {
          bool changed = false;
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) {
              final tempSelected = Set<String>.from(_selectedPayeeIds);
              bool showPayers = _showPayers;
              return StatefulBuilder(
                builder: (context, sb) {
                  void saveAndClose() {
                    setState(() {
                      _selectedPayeeIds
                        ..clear()
                        ..addAll(tempSelected);
                      _showPayers = showPayers;
                    });
                    changed = true;
                    Navigator.of(ctx).pop();
                  }
                  void clearAndClose() {
                    setState(() {
                      _selectedPayeeIds.clear();
                    });
                    changed = true;
                    Navigator.of(ctx).pop();
                  }
                  return FractionallySizedBox(
                    heightFactor: 0.75,
                    child: Column(
                      children: [
                        AppBar(
                          automaticallyImplyLeading: false,
                          title: const Text('Select payees/payers'),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          actions: [
                            IconButton(
                              tooltip: 'Clear selection',
                              icon: const Icon(Icons.clear),
                              onPressed: clearAndClose,
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Payees'),
                                    selected: !showPayers,
                                    onSelected: (s) {
                                      sb(() {
                                        showPayers = false;
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('Payers'),
                                    selected: showPayers,
                                    onSelected: (s) {
                                      sb(() {
                                        showPayers = true;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: clearAndClose,
                                  icon: const Icon(Icons.clear, size: 18),
                                  label: const Text('Clear selection'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _payees
                                .where((p) => (p['type'] as String?) == (showPayers ? 'payer' : 'payee'))
                                .length,
                            itemBuilder: (context, index) {
                              final filtered = _payees
                                  .where((p) => (p['type'] as String?) == (showPayers ? 'payer' : 'payee'))
                                  .toList();
                              final p = filtered[index];
                              final id = p['id'] as String?;
                              final name = p['name'] as String? ?? 'Unknown';
                              final selected = id != null && tempSelected.contains(id);
                              return CheckboxListTile(
                                title: Text(name),
                                value: selected,
                                onChanged: id == null
                                    ? null
                                    : (v) {
                                        sb(() {
                                          if (v == true) {
                                            tempSelected.add(id);
                                          } else {
                                            tempSelected.remove(id);
                                          }
                                        });
                                    },
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                  },
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextButton(
                                  onPressed: saveAndClose,
                                  child: const Text('Done'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
          if (changed) setState(() {});
        },
      ),
    );
  }

  double _computeTotalForPeriodByCategoryFilter(
      DateTime start, DateTime end, TransactionType type) {
  final txs = _transactionsExcludingTransfersRange(start, end).where((t) => t.type == type);

    // Exclude transfers (category name 'Transfer', case-insensitive)
    final transferCategory = _categories.firstWhere(
      (c) => c.name.trim().toLowerCase() == 'transfer',
      orElse: () => Category(
        id: '__no_transfer__',
        name: '',
        iconCodePoint: '',
        colorValue: '0xFF888888',
        isDefault: false,
        type: type == TransactionType.income ? CategoryType.income : CategoryType.expense,
      ),
    );
    var filtered = txs;
    if (transferCategory.id != '__no_transfer__') {
      filtered = filtered.where((t) => t.categoryId != transferCategory.id);
    }

    // Apply category filter if any
    if (_selectedCategoryIds.isNotEmpty) {
      filtered = filtered.where((t) => _selectedCategoryIds.contains(t.categoryId));
    }

    // Apply payee/payer filter if any
    if (_selectedPayeeIds.isNotEmpty) {
      if (_showPayers && type == TransactionType.income) {
        filtered = filtered.where((t) {
          // Match by payerId or by description containing selected payer name
          if (t.payerId != null && _selectedPayeeIds.contains(t.payerId)) return true;
          for (final id in _selectedPayeeIds) {
            final payer = _payees.firstWhere((p) => p['id'] == id, orElse: () => <String, dynamic>{});
            final name = (payer['name'] ?? '').toString().trim();
            if (name.isNotEmpty && t.description.contains(name)) return true;
          }
          return false;
        });
      } else if (!_showPayers && type == TransactionType.expense) {
        filtered = filtered.where((t) {
          // Match by payeeId or by description containing selected payee name
          if (t.payeeId != null && _selectedPayeeIds.contains(t.payeeId)) return true;
          for (final id in _selectedPayeeIds) {
            final payee = _payees.firstWhere((p) => p['id'] == id, orElse: () => <String, dynamic>{});
            final name = (payee['name'] ?? '').toString().trim();
            if (name.isNotEmpty && t.description.contains(name)) return true;
          }
          return false;
        });
      } else {
        filtered = filtered.where((t) => false);
      }
    }

    return filtered.fold(0.0, (sum, t) => sum + t.amount);
  }
}
