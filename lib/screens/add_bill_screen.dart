// ignore_for_file: deprecated_member_use, no_leading_underscores_for_local_identifiers, curly_braces_in_flow_control_structures, unused_import

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/bill.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/account.dart';
import '../models/reminder_offset.dart';
import '../services/database_service.dart';
import '../services/bill_reminder_service.dart';
import '../services/lookups_sync_helper.dart';
import '../widgets/bill_reminder_picker.dart';
import '../widgets/app_color_picker.dart';
import 'package:uuid/uuid.dart';

Category? _findCategoryById(Iterable<Category> categories, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final category in categories) {
    if (category.id == id) return category;
  }
  return null;
}

class AddBillScreen extends StatefulWidget {
  final Bill? existingBill;
  final bool isDuplicate;

  const AddBillScreen({super.key, this.existingBill, this.isDuplicate = false});

  @override
  State<AddBillScreen> createState() => _AddBillScreenState();
}

// Top-level category selector sheet widget with search and add
class _CategorySelectorSheet extends StatefulWidget {
  final List<Category> categories;
  final String? initialSelectedId;
  final BillType billType;

  const _CategorySelectorSheet({required this.categories, this.initialSelectedId, required this.billType});

  @override
  State<_CategorySelectorSheet> createState() => _CategorySelectorSheetState();
}

class _CategorySelectorSheetState extends State<_CategorySelectorSheet> {
  late List<Category> _all;
  late List<Category> _filtered;
  String _query = '';
  String? _selectedId;
  VoidCallback? _categoriesListener;

  @override
  void initState() {
    super.initState();
    _all = List<Category>.from(widget.categories)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _filtered = _all;
    _selectedId = widget.initialSelectedId;
    _categoriesListener = () {
      setState(() {
        _all = DatabaseService
            .getAllCategories()
            .where((c) => c.type == (widget.billType == BillType.income ? CategoryType.income : CategoryType.expense))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _filtered = _all.where((c) => c.name.toLowerCase().contains(_query)).toList();
      });
    };
    DatabaseService.categoriesVersion.addListener(_categoriesListener!);
  }

  @override
  void dispose() {
    if (_categoriesListener != null) {
      DatabaseService.categoriesVersion.removeListener(_categoriesListener!);
    }
    super.dispose();
  }

  void _onSearch(String q) {
    setState(() {
      _query = q.toLowerCase();
      _filtered = _all.where((c) => c.name.toLowerCase().contains(_query)).toList();
    });
  }

  Future<void> _addCategory() async {
    final nameCtrl = TextEditingController();
    Color selectedColor = const Color(0xFF607D8B);
    final result = await showDialog<Category?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Center(child: Text('Add Category')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showAppColorPicker(
                      context: ctx,
                      initialColor: selectedColor,
                      title: 'Pick Category Color',
                    );
                    if (picked != null) setState(() => selectedColor = picked);
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
                      const Text('Category Color'),
                      const SizedBox(width: 8),
                      const Icon(Icons.color_lens_outlined, size: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final catType = widget.billType == BillType.income ? CategoryType.income : CategoryType.expense;
                final newCat = Category(
                  name: name,
                  iconCodePoint: '0xe85d',
                  colorValue: selectedColor.value.toString(),
                  type: catType,
                );
                Navigator.pop(ctx, newCat);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final newCatId = await DatabaseService.addCategory(result);
        try {
          await LookupsSyncHelper.syncCategory(result.copyWith(id: newCatId));
        } catch (_) {}
        if (!mounted) return;
        _all = DatabaseService
            .getAllCategories()
            .where((c) => c.type == result.type)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        setState(() {
          _filtered = _all.where((c) => c.name.toLowerCase().contains(_query)).toList();
          _selectedId = newCatId;
        });
        if (!mounted) return;
        Navigator.pop(context, newCatId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to save category: $e'),
            backgroundColor: Colors.blueGrey[400],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Category'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _addCategory)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search categories'),
              onChanged: _onSearch,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (context, idx) {
                final c = _filtered[idx];
                return ListTile(
                  leading: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: c.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(c.name),
                  trailing: _selectedId == c.id ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, c.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Top-level payee selector sheet widget
class _PayeeSelectorSheet extends StatefulWidget {
  final List<Map<String, dynamic>> payees;
  final String? initialSelectedId;
  final BillType billType;

  const _PayeeSelectorSheet({required this.payees, this.initialSelectedId, required this.billType});

  @override
  State<_PayeeSelectorSheet> createState() => _PayeeSelectorSheetState();
}

class _PayeeSelectorSheetState extends State<_PayeeSelectorSheet> {
  late List<Map<String, dynamic>> _all;
  late List<Map<String, dynamic>> _filtered;
  String _query = '';
  String? _selectedId;
  VoidCallback? _categoriesListener;

  @override
  void initState() {
    super.initState();
    _all = List<Map<String, dynamic>>.from(widget.payees)
      ..sort((a, b) {
        final an = (a['name'] ?? '').toString().toLowerCase();
        final bn = (b['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });
    _filtered = _all;
    _selectedId = widget.initialSelectedId;
    _categoriesListener = () {
      if (!mounted) return;
      setState(() {});
    };
    DatabaseService.categoriesVersion.addListener(_categoriesListener!);
  }

  @override
  void dispose() {
    if (_categoriesListener != null) {
      DatabaseService.categoriesVersion.removeListener(_categoriesListener!);
    }
    super.dispose();
  }

  void _onSearch(String q) {
    setState(() {
      _query = q.toLowerCase();
      _filtered = _all.where((p) => (p['name'] as String).toLowerCase().contains(_query)).toList();
    });
  }

  Future<void> _addPayee() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final _nameController = TextEditingController();
        String? _categoryId;
        // Use a StatefulBuilder to update dropdowns inside the dialog
        return StatefulBuilder(builder: (ctx, setState) {
          // Fetch categories here so the list is fresh after adding a new one
          final categories = DatabaseService.getAllCategories();
          final filteredCats = categories.where((c) => widget.billType == BillType.income ? c.type == CategoryType.income : c.type == CategoryType.expense).toList();
          return AlertDialog(
            title: Center(child: Text(
              widget.billType == BillType.income ? 'Add Payer' : 'Add Payee',
            )),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _nameController, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: const Text('Select category'),
                    subtitle: Text(
                      _categoryId == null
                          ? 'None'
                          : (_findCategoryById(filteredCats, _categoryId)?.name ?? 'None'),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () async {
                      final selected = await showModalBottomSheet<String?> (
                        context: ctx,
                        isScrollControlled: true,
                        builder: (_) => FractionallySizedBox(
                          heightFactor: 0.85,
                          child: _CategorySelectorSheet(categories: filteredCats, initialSelectedId: _categoryId, billType: widget.billType),
                        ),
                      );
                      if (selected != null) setState(() => _categoryId = selected);
                    },
                  ),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  final name = _nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx, {
                    'name': name,
                    'categoryId': _categoryId,
                  });
                },
                child: const Text('Add'),
              ),
            ],
          );
        });
      },
    );

    if (result != null) {
      final type = widget.billType == BillType.income ? 'payer' : 'payee';
      final newPayee = {
        'id': const Uuid().v4(),
        'name': result['name'],
        'type': type,
        'categoryId': result['categoryId'],
      };
      await DatabaseService.addPayee(newPayee);
      try {
        await LookupsSyncHelper.syncPayeeOrPayer(newPayee);
      } catch (_) {}
      // If the widget was disposed while waiting, stop before touching context/state
      if (!mounted) return;
      // Refresh the full list from settings
      _all = DatabaseService.getAllPayees()
        ..sort((a, b) {
          final an = (a['name'] ?? '').toString().toLowerCase();
          final bn = (b['name'] ?? '').toString().toLowerCase();
          return an.compareTo(bn);
        });
      setState(() {
        _filtered = _all.where((p) => (p['name'] as String).toLowerCase().contains(_query)).toList();
        _selectedId = newPayee['id'] as String;
      });
      if (!mounted) return;
      // Return the new id to the caller (close sheet)
      Navigator.pop(context, _selectedId);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine if this is an expense or income entry by checking all payees' category type
    String titleText = widget.billType == BillType.expense
        ? 'Select Payee'
        : widget.billType == BillType.income
            ? 'Select Payer'
            : '';
    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _addPayee)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
              onChanged: _onSearch,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (context, idx) {
                final p = _filtered[idx];
                String? categoryName;
                if (p['categoryId'] != null && p['categoryId'].toString().isNotEmpty) {
                  final cat = DatabaseService.getCategoryById(p['categoryId']);
                  categoryName = cat?.name;
                }
                return ListTile(
                  title: Text(p['name'] as String),
                  subtitle: Text(categoryName ?? ''),
                  trailing: _selectedId == p['id'] ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, p['id'] as String),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Top-level calculator bottom sheet widget
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
              children: [
                TextButton(onPressed: _clear, child: const Text('Clear')),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
                    final value = _evaluate();
                    if (value != null) Navigator.of(context).pop(value);
                  },
                  child: const Text('Accept'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBillScreenState extends State<AddBillScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;
  bool _didUserEditNotes = false;
  String _initialNotes = '';

  // New: bill type (expense/income/transfer)
  BillType _billType = BillType.expense;

  DateTime _dueDate = DateTime.now();
  Recurrence _recurrence = Recurrence.none;
  List<int>? _customDays;
  DateTime? _recurrenceEndDate;
  bool _recurrenceForever = true;
  // recurrence interval (every N days/weeks/months/years)
  int _recurrenceInterval = 1;
  // selected weekdays for weekly recurrence (1=Mon .. 7=Sun)
  List<int>? _recurrenceWeekdays = [];
  String? _selectedPayeeId;
  String? _selectedAccountId;
  // Transfer-specific accounts
  String? _fromAccountId;
  String? _toAccountId;
  bool _remindersEnabled = false;

  List<ReminderOffset> _selectedReminders = [
    const ReminderOffset(daysBefore: 7, hour: 9, minute: 0),
    const ReminderOffset(daysBefore: 1, hour: 9, minute: 0),
  ];

  static const List<ReminderOffset> _defaultReminders = [
    ReminderOffset(daysBefore: 7, hour: 9, minute: 0),
    ReminderOffset(daysBefore: 1, hour: 9, minute: 0),
  ];
  

  List<Map<String, dynamic>> _payees = [];
  List accountList = [];
  List<Category> _categories = [];
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadLookups();
    _loadExistingBillData();
  }

  void _loadExistingBillData() {
    final bill = widget.existingBill;
    if (bill != null) {
      _amountController.text = bill.amount.toString();
      _initialNotes = _extractEditableNotes(bill);
      _notesController.text = _initialNotes;
      _dueDate = bill.dueDate;
      _recurrence = bill.recurrence;
      _customDays = bill.customDays;
      _recurrenceEndDate = bill.recurrenceEndDate;
      _recurrenceForever = bill.recurrenceEndDate == null;
      _recurrenceInterval = bill.recurrenceInterval <= 0 ? 1 : bill.recurrenceInterval;
      _recurrenceWeekdays = bill.recurrenceWeekdays ?? [];
      _selectedCategoryId = bill.categoryId;
      _billType = bill.type;
      _fromAccountId = bill.fromAccountId;
      _toAccountId = bill.toAccountId;
      _selectedPayeeId = bill.payeeId;
      _selectedAccountId = bill.accountId;
      _loadBillReminders(bill.toJson());
  // preserve existing reminder setting but do not expose toggle in UI
    }
  }

  void _loadBillReminders(Map<String, dynamic> billData) {
    final rawOffsets = billData['reminderOffsets'] as List?;

    final parsed = rawOffsets == null
        ? <ReminderOffset>[]
        : rawOffsets
            .whereType<Map>()
            .map((e) => ReminderOffset.fromJson(Map<String, dynamic>.from(e)))
            .toList();

    if (parsed.isEmpty) {
      _selectedReminders = List<ReminderOffset>.from(_defaultReminders);
      _remindersEnabled = false;
      return;
    }

    _selectedReminders = parsed;
    _remindersEnabled = true;
  }

  void _loadLookups() {
    _payees = DatabaseService.getAllPayees();
    accountList = DatabaseService.getAllAccounts();
    _categories = DatabaseService.getAllCategories();
  }

  String _extractEditableNotes(Bill bill) {
    final raw = (bill.description ?? '').trim();
    if (raw.isEmpty) return '';

    final lowerRaw = raw.toLowerCase();

    // Never treat contact labels as notes.
    final contactNames = _payees
        .map((p) => (p['name'] ?? '').toString().trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (contactNames.contains(lowerRaw)) {
      return '';
    }

    if (lowerRaw.startsWith('payee:') || lowerRaw.startsWith('payer:')) {
      return '';
    }

    if (bill.payeeId != null && bill.payeeId!.isNotEmpty) {
      final payee = _payees.firstWhere(
        (p) => p['id'] == bill.payeeId,
        orElse: () => const <String, dynamic>{},
      );
      final payeeName = (payee['name'] ?? '').toString().trim();
      if (payeeName.isNotEmpty && lowerRaw == payeeName.toLowerCase()) {
        return '';
      }
    }

    if (bill.type == BillType.transfer) {
      final fromName = (bill.fromAccountId != null && bill.fromAccountId!.isNotEmpty)
          ? DatabaseService.getAccountById(bill.fromAccountId!)?.name
          : null;
      final toName = (bill.toAccountId != null && bill.toAccountId!.isNotEmpty)
          ? DatabaseService.getAccountById(bill.toAccountId!)?.name
          : null;
      if (fromName != null && toName != null) {
        final generated = 'transfer from $fromName to $toName'.toLowerCase();
        if (lowerRaw == generated) {
          return '';
        }
      }
    }

    return raw;
  }

  List<Map<String, dynamic>> get _visiblePayees {
    if (_billType == BillType.expense) {
      return _payees.where((p) => (p['type'] as String?) == 'payee').toList();
    } else if (_billType == BillType.income) {
      return _payees.where((p) => (p['type'] as String?) == 'payer').toList();
    }
    return _payees;
  }

  List<Category> get _visibleCategories {
    if (_billType == BillType.expense) {
      return _categories.where((c) => c.type == CategoryType.expense).toList();
    } else if (_billType == BillType.income) {
      return _categories.where((c) => c.type == CategoryType.income).toList();
    }
    return _categories;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(widget.isDuplicate
            ? 'Duplicate Bill'
            : (widget.existingBill != null ? 'Edit Bill' : 'Add Bill')),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildTypeToggle(),
            const SizedBox(height: 12),
            _buildAmountField(),
            const SizedBox(height: 16),
            if (_billType == BillType.transfer) ...[
              _buildFromAccountSelector(),
              const SizedBox(height: 12),
              _buildToAccountSelector(),
            ] else ...[
              _buildPayeeSelector(),
              const SizedBox(height: 12),
              _buildCategorySelector(),
              const SizedBox(height: 12),
              _buildAccountSelector(),
            ],
            const SizedBox(height: 8),
            _buildDueDateSelector(),
            const SizedBox(height: 16),
            _buildRecurrenceField(),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                title: const Text('Enable reminders'),
                subtitle: Text(_remindersEnabled ? 'On' : 'Off'),
                value: _remindersEnabled,
                onChanged: (value) {
                  setState(() {
                    _remindersEnabled = value;
                    if (_remindersEnabled && _selectedReminders.isEmpty) {
                      _selectedReminders = List<ReminderOffset>.from(_defaultReminders);
                    }
                  });
                },
              ),
            ),
            if (_remindersEnabled) ...[
              const SizedBox(height: 12),
              BillReminderPicker(
                initialValue: _selectedReminders,
                onChanged: (value) {
                  setState(() {
                    _selectedReminders = value;
                  });
                },
              ),
            ],
            const SizedBox(height: 12),
            _buildNotesField(),
            const SizedBox(height: 16),
            const SizedBox(height: 32),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeToggle() {
    return Card(
      child: ListTile(
        title: Center(
          child: ToggleButtons(
            isSelected: [
              _billType == BillType.expense,
              _billType == BillType.income,
            ],
            onPressed: (index) {
              setState(() {
                _billType = BillType.values[index];
                _selectedPayeeId = null;
                _selectedCategoryId = null;
                // clear account selections when switching types
                _selectedAccountId = null;
                _fromAccountId = null;
                _toAccountId = null;
                _notesController.clear();
                _didUserEditNotes = true;
              });
            },
            children: const [
              Padding(padding: EdgeInsets.symmetric(horizontal:16), child: Text('Expense')),
              Padding(padding: EdgeInsets.symmetric(horizontal:16), child: Text('Income')),
            ],
          ),
        ),
        // trailing arrow removed to display toggle without chevron
        onTap: () {
          // No-op tap so it visually behaves like other list tiles. Tapping keeps current selection.
        },
      ),
    );
  }

  Widget _buildAmountField() {
    return TextFormField(
      controller: _amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Amount',
        prefixText: '\$ ',
        hintText: '0.00',
        prefixStyle: TextStyle(
          color: _billType == BillType.income
              ? AppTheme.incomeGreen
              : (_billType == BillType.expense ? AppTheme.expenseRed : null),
        ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.calculate),
          onPressed: () async {
            final result = await showModalBottomSheet<double?>(
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
        if (value == null || value.isEmpty) return 'Please enter an amount';
        final v = double.tryParse(value);
        if (v == null || v <= 0) return 'Please enter a valid amount';
        return null;
      },
    );
  }




  Widget _buildDueDateSelector() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.calendar_today),
        title: const Text('Due Date'),
        subtitle: Text(DateFormat.yMMMd().format(_dueDate)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: _selectDueDate,
      ),
    );
  }

  Future<void> _selectDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && picked != _dueDate) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  // _buildRecurrenceSelector removed in favor of _buildRecurrenceField

  Widget _buildRecurrenceField() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.repeat),
        title: const Text('Recurrence'),
        subtitle: Text(_recurrenceSummary()),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final result = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) {
              Recurrence temp = _recurrence;
              bool tempForever = _recurrenceForever;
              DateTime? tempEnd = _recurrenceEndDate;
              // local temp copies so modal changes don't apply until Save
              int tempInterval = _recurrenceInterval;
              final Set<int> tempWeekdays = {...?_recurrenceWeekdays};
              final Set<int> tempCustomDays = {...?_customDays};
              bool showInlineDays = false;

              return StatefulBuilder(builder: (ctx, setState) {
                return Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(title: const Text('Select recurrence')),
                      RadioListTile<Recurrence>(value: Recurrence.none, groupValue: temp, title: const Text('None'), onChanged: (v) => setState(() => temp = v!)),
                      RadioListTile<Recurrence>(value: Recurrence.daily, groupValue: temp, title: const Text('Daily'), onChanged: (v) => setState(() => temp = v!)),
                      RadioListTile<Recurrence>(value: Recurrence.weekly, groupValue: temp, title: const Text('Weekly'), onChanged: (v) => setState(() => temp = v!)),
                      RadioListTile<Recurrence>(value: Recurrence.monthly, groupValue: temp, title: const Text('Monthly'), onChanged: (v) => setState(() => temp = v!)),
                      RadioListTile<Recurrence>(value: Recurrence.yearly, groupValue: temp, title: const Text('Yearly'), onChanged: (v) => setState(() => temp = v!)),
                      // Custom option removed
                      // Interval controls for standard recurrence types
                      if (temp == Recurrence.daily || temp == Recurrence.weekly || temp == Recurrence.monthly || temp == Recurrence.yearly)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                          child: Row(
                            children: [
                              const Text('Every'),
                              const SizedBox(width: 8),
                              IconButton(onPressed: () => setState(() { if (tempInterval > 1) tempInterval -= 1; }), icon: const Icon(Icons.remove_circle_outline)),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(6)), child: Text('$tempInterval')),
                              IconButton(onPressed: () => setState(() => tempInterval += 1), icon: const Icon(Icons.add_circle_outline)),
                              const SizedBox(width: 8),
                              Text(_pluralForRecurrenceUnit(temp, tempInterval)),
                            ],
                          ),
                        ),

                      // Weekday picker when weekly selected
                      if (temp == Recurrence.weekly)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                          child: Wrap(
                            spacing: 6,
                            children: List.generate(7, (i) {
                              final day = i + 1; // 1..7
                              final names = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
                              final sel = tempWeekdays.contains(day);
                              return ChoiceChip(
                                label: Text(names[i]),
                                selected: sel,
                                onSelected: (v) => setState(() => v ? tempWeekdays.add(day) : tempWeekdays.remove(day)),
                              );
                            }),
                          ),
                        ),
                      // Monthly custom-days inline dropdown when monthly selected
                      if (temp == Recurrence.monthly)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('Days:'),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      tempCustomDays.isEmpty ? 'Select days' : (tempCustomDays.toList()..sort()).join(', '),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(showInlineDays ? Icons.arrow_drop_up : Icons.arrow_drop_down),
                                    onPressed: () => setState(() => showInlineDays = !showInlineDays),
                                  ),
                                ],
                              ),
                              if (showInlineDays)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      ...List.generate(31, (i) {
                                        final day = i + 1;
                                        final sel = tempCustomDays.contains(day);
                                        return FilterChip(
                                          label: Text(day.toString(), style: const TextStyle(fontSize: 12)),
                                          selected: sel,
                                          onSelected: (v) => setState(() {
                                            if (v) tempCustomDays.add(day); else tempCustomDays.remove(day);
                                          }),
                                          selectedColor: Theme.of(context).colorScheme.primary,
                                        );
                                      }),
                                      FilterChip(
                                        label: const Text('Last day', style: TextStyle(fontSize: 12)),
                                        selected: tempCustomDays.contains(99),
                                        onSelected: (v) => setState(() {
                                          if (v) tempCustomDays.add(99); else tempCustomDays.remove(99);
                                        }),
                                        selectedColor: Theme.of(context).colorScheme.primary,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.event),
                            const SizedBox(width: 12),
                            const Text('End'),
                            const Spacer(),
                            Text(tempForever ? 'Forever' : (tempEnd == null ? 'Select date' : DateFormat.yMMMd().format(tempEnd!))),
                            const SizedBox(width: 8),
                            TextButton(onPressed: () => setState(() => tempForever = !tempForever), child: Text(tempForever ? 'End date' : 'Make forever')),
                            if (!tempForever)
                              IconButton(onPressed: () async {
                                final picked = await showDatePicker(context: ctx, initialDate: tempEnd ?? DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
                                if (picked != null) setState(() => tempEnd = picked);
                              }, icon: const Icon(Icons.calendar_today)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          const SizedBox(width: 16),
                          TextButton(
                            onPressed: () {
                              // commit
                              setState(() {});
                              _recurrence = temp;
                              _recurrenceForever = tempForever;
                              _recurrenceEndDate = tempForever ? null : tempEnd;
                              _recurrenceInterval = tempInterval;
                              // if weekly, persist selected weekdays (or null if none selected, which means use due date weekday)
                              _recurrenceWeekdays = (temp == Recurrence.weekly && tempWeekdays.isEmpty) ? null : (tempWeekdays.toList()..sort());
                              // if monthly, persist selected days (or null if none selected, which means use due date)
                              if (temp == Recurrence.monthly) {
                                _customDays = tempCustomDays.isEmpty ? null : (tempCustomDays.toList()..sort());
                              } else {
                                _customDays = null;
                              }
                              Navigator.pop(ctx, true);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              });
            },
          );
          if (result == true) setState(() {});
        },
      ),
    );
  }

  String _recurrenceSummary() {
    final interval = _recurrenceInterval <= 0 ? 1 : _recurrenceInterval;
    switch (_recurrence) {
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
      default:
        // For any other (legacy) recurrence values, fallback to a generic label
  final s = _recurrence.toString().split('.').last;
  return s.isEmpty ? s : (s[0].toUpperCase() + s.substring(1).toLowerCase());
    }
  }

  String _pluralForRecurrenceUnit(Recurrence r, int interval) {
    final unit = switch (r) {
      Recurrence.daily => 'day',
      Recurrence.weekly => 'week',
      Recurrence.monthly => 'month',
      Recurrence.yearly => 'year',
      _ => 'period',
    };
    return interval == 1 ? unit : '${unit}s';
  }

  // recurrence end date selection is handled inside the recurrence modal

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      textCapitalization: TextCapitalization.sentences,
      maxLines: 3,
      onChanged: (_) {
        if (!_didUserEditNotes) {
          setState(() => _didUserEditNotes = true);
        }
      },
      decoration: const InputDecoration(
        labelText: 'Notes',
        hintText: 'Optional notes about this bill',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildPayeeSelector() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person),
        title: Text(_billType == BillType.income ? 'Payer' : 'Payee'),
        subtitle: Text(
          _selectedPayeeId == null
              ? (_billType == BillType.income ? 'Select payer' : 'Select payee')
              : (_payees.firstWhere((p) => p['id'] == _selectedPayeeId, orElse: () => {'name': 'Unknown'})['name'] as String),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.85,
              child: _PayeeSelectorSheet(
                payees: _visiblePayees,
                initialSelectedId: _selectedPayeeId,
                billType: _billType,
              ),
            ),
          );
          if (selected != null) {
            // Refresh payees from storage so newly added payees are present
            final updatedPayees = DatabaseService.getAllPayees();
            setState(() {
              _payees = updatedPayees;
              _selectedPayeeId = selected;
            });

            // Ensure our categories list is up-to-date so the category lookup
            // used by the UI can find newly created categories.
            final updatedCategories = DatabaseService.getAllCategories();
            try {
              final p = _payees.firstWhere((p) => p['id'] == selected, orElse: () => <String, dynamic>{});
              if (p.containsKey('categoryId') && p['categoryId'] != null) {
                setState(() {
                  _categories = updatedCategories;
                  _selectedCategoryId = p['categoryId'] as String?;
                });
              } else {
                // Update categories list even if payee has no category
                setState(() {
                  _categories = updatedCategories;
                });
              }
            } catch (_) {
              setState(() {
                _categories = updatedCategories;
              });
            }
          }
        },
      ),
    );
  }

  Widget _buildAccountSelector() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet),
        title: const Text('Account'),
        subtitle: Text(_selectedAccountId == null
            ? 'Select'
            : (() {
                try {
                  final found = accountList.firstWhere((a) => a is Account ? a.id == _selectedAccountId : (a['id'] == _selectedAccountId));
                  if (found is Account) return found.name;
                  if (found is Map && found.containsKey('name')) return found['name'] as String;
                } catch (_) {}
                return 'Unknown';
              }()) ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(builder: (ctx2, setState2) {
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Select Account'),
                    backgroundColor: Theme.of(ctx2).colorScheme.primary,
                    foregroundColor: Colors.white,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          // Prevent free users from creating more than 3 accounts
                          final plan = DatabaseService.subscriptionVersion.value;
                          final accounts = DatabaseService.getAllAccounts();
                          if (plan == 'Free' && accounts.length >= 3) {
                            await showDialog(
                              context: ctx2,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Account Limit Reached'),
                                content: const Text('Free users can create up to 3 accounts. Subscribe for unlimited accounts.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK')),
                                ],
                              ),
                            );
                            return;
                          }
                          // Show add account dialog
                          final nameCtrl = TextEditingController();
                          final institutionCtrl = TextEditingController();
                          final accNumCtrl = TextEditingController();
                          final cardNumCtrl = TextEditingController();
                          AccountType selectedType = AccountType.cash;
                          final balCtrl = TextEditingController(text: '0.0');
                          final availCtrl = TextEditingController(text: '0.0');
                          String? customType;
                          final res = await showDialog<Account?>(
                            context: ctx2,
                            builder: (dctx) => StatefulBuilder(builder: (dctx, dset) {
                              return AlertDialog(
                                title: const Center(child: Text('Add Account')),
                                content: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // allow choosing enum type and adding a custom type string
                                      Row(children: [
                                        const Text('Type:'),
                                        const SizedBox(width: 12),
                                        DropdownButton<String>(
                                          value: customType ?? selectedType.name,
                                          onChanged: (v) {
                                            if (v == null) return;
                                            // If matches enum, set selectedType, else set customType
                                            final match = AccountType.values.firstWhere(
                                              (t) => t.name.toLowerCase() == v.toLowerCase(),
                                              orElse: () => AccountType.cash,
                                            );
                                            if (AccountType.values.map((t) => t.name.toLowerCase()).contains(v.toLowerCase())) {
                                              dset(() {
                                                selectedType = match;
                                                customType = null;
                                              });
                                            } else {
                                              dset(() => customType = v);
                                            }
                                          },
                                          items: ([...AccountType.values.map((t) => t.name), ...DatabaseService.getAllCustomAccountTypes()])
                                            .toSet()
                                            .map((type) => DropdownMenuItem(
                                              value: type,
                                              child: Text(type.isNotEmpty ? type[0].toUpperCase() + type.substring(1) : type),
                                            ))
                                            .toList(),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline),
                                          tooltip: 'Add custom type',
                                          onPressed: () async {
                                            final textCtrl = TextEditingController();
                                            final res = await showDialog<String?>(
                                              context: dctx,
                                              builder: (tctx) => AlertDialog(
                                                title: const Text('Add account type'),
                                                content: TextField(controller: textCtrl, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Type name')),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(tctx), child: const Text('Cancel')),
                                                  TextButton(onPressed: () {
                                                    final v = textCtrl.text.trim();
                                                    if (v.isEmpty) return;
                                                    Navigator.pop(tctx, v);
                                                  }, child: const Text('Add')),
                                                ],
                                              ),
                                            );
                                            if (res != null) dset(() => customType = res);
                                          },
                                        ),
                                        if (customType != null) Padding(padding: const EdgeInsets.only(left:8.0), child: Text('($customType)', style: const TextStyle(fontStyle: FontStyle.italic))),
                                      ]),
                                      const SizedBox(height: 8),
                                      TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Account')),
                                      const SizedBox(height: 8),
                                      TextField(controller: institutionCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Institution')),
                                      const SizedBox(height: 8),
                                      TextField(controller: accNumCtrl, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(labelText: 'Account number')),
                                      const SizedBox(height: 8),
                                      TextField(controller: cardNumCtrl, decoration: const InputDecoration(labelText: 'Card number')),
                                      const SizedBox(height: 8),
                                      const SizedBox(height: 8),
                                      TextField(controller: balCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Initial balance')),
                                      const SizedBox(height: 8),
                                      TextField(controller: availCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Available balance')),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                                    TextButton(onPressed: () {
                                    final name = nameCtrl.text.trim();
                                    if (name.isEmpty) return;
                                    final institution = institutionCtrl.text.trim();
                                    final accNum = accNumCtrl.text.trim().isEmpty ? null : accNumCtrl.text.trim();
                                    final cardNum = cardNumCtrl.text.trim().isEmpty ? null : cardNumCtrl.text.trim();
                                    final bal = double.tryParse(balCtrl.text) ?? 0.0;
                                    final avail = double.tryParse(availCtrl.text);
                                    // Add custom type to database if provided
                                    if (customType != null && customType!.isNotEmpty) {
                                      DatabaseService.addCustomAccountType(customType!);
                                    }
                                    final acc = Account(name: name, type: selectedType, institution: institution.isEmpty ? null : institution, accountNumber: accNum, cardNumber: cardNum, balance: bal, availableBalance: avail, customType: customType);
                                    Navigator.pop(dctx, acc);
                                  }, child: const Text('Add')),
                                ],
                              );
                            }),
                          );

                          if (res != null) {
                            await DatabaseService.addAccount(res);
                            // Refresh parent account list and modal UI
                            final updated = DatabaseService.getAllAccounts();
                            setState2(() {});
                            setState(() {
                              accountList = updated;
                              _selectedAccountId = res.id;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  body: ListView.builder(
                    itemCount: accountList.length,
                    itemBuilder: (context, idx) {
                      final a = accountList[idx];
                      return ListTile(
                        title: Text((a is Account) ? a.name : (a['name'] as String)),
                        onTap: () => Navigator.pop(context, (a is Account) ? a.id : (a['id'] as String)),
                      );
                    },
                  ),
                );
              }),
            ),
          );
          if (selected != null) setState(() => _selectedAccountId = selected);
        },
      ),
    );
  }

  Widget _buildFromAccountSelector() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.arrow_forward),
        title: const Text('From'),
        subtitle: Text(_fromAccountId == null ? 'Select from' : (() {
              try {
                final found = accountList.firstWhere((a) => a is Account ? a.id == _fromAccountId : (a['id'] == _fromAccountId));
                if (found is Account) return found.name;
                if (found is Map && found.containsKey('name')) return found['name'] as String;
              } catch (_) {}
              return 'Unknown';
            }())),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(builder: (ctx2, setState2) {
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Select Account'),
                    backgroundColor: Theme.of(ctx2).colorScheme.primary,
                    foregroundColor: Colors.white,
                    actions: [
                      IconButton(icon: const Icon(Icons.add), onPressed: () async {
                        // delegate to same add flow as account selector
                        final nameCtrl = TextEditingController();
                        final institutionCtrl = TextEditingController();
                        final accNumCtrl = TextEditingController();
                        final cardNumCtrl = TextEditingController();
                        AccountType selectedType = AccountType.cash;
                        final balCtrl = TextEditingController(text: '0.0');
                        final availCtrl = TextEditingController(text: '0.0');
                        String? customType;
                          final res = await showDialog<Account?>(
                          context: ctx2,
                          builder: (dctx) => StatefulBuilder(builder: (dctx, dset) {
                            return AlertDialog(
                              title: const Center(child: Text('Add Account')),
                                content: SingleChildScrollView(
                                  child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(children: [
                                      const Text('Type:'),
                                      const SizedBox(width: 12),
                                      DropdownButton<AccountType>(
                                        value: selectedType,
                                        onChanged: (v) { if (v != null) dset(() => selectedType = v); },
                                        items: AccountType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline),
                                        tooltip: 'Add custom type',
                                        onPressed: () async {
                                          final textCtrl = TextEditingController();
                                          final res = await showDialog<String?>(
                                            context: dctx,
                                            builder: (tctx) => AlertDialog(
                                              title: const Text('Add account type'),
                                              content: TextField(controller: textCtrl, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Type name')),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(tctx), child: const Text('Cancel')),
                                                TextButton(onPressed: () {
                                                  final v = textCtrl.text.trim();
                                                  if (v.isEmpty) return;
                                                  Navigator.pop(tctx, v);
                                                }, child: const Text('Add')),
                                              ],
                                            ),
                                          );
                                          if (res != null) dset(() => customType = res);
                                        },
                                      ),
                                      if (customType != null) Padding(padding: const EdgeInsets.only(left:8.0), child: Text('($customType)', style: const TextStyle(fontStyle: FontStyle.italic))),
                                    ]),
                                    const SizedBox(height: 8),
                                      TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Account')),
                                    const SizedBox(height: 8),
                                      TextField(controller: institutionCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Institution')),
                                    const SizedBox(height: 8),
                                      TextField(controller: accNumCtrl, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(labelText: 'Account number')),
                                    const SizedBox(height: 8),
                                    TextField(controller: cardNumCtrl, decoration: const InputDecoration(labelText: 'Card number')),
                                    const SizedBox(height: 8),
                                    const SizedBox(height: 8),
                                    TextField(controller: balCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Initial balance')),
                                    const SizedBox(height: 8),
                                      TextField(controller: availCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Available balance')),
                                    ],
                                  ),
                                ),
                                actions: [
                                TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                                TextButton(onPressed: () {
                                  final name = nameCtrl.text.trim();
                                  if (name.isEmpty) return;
                                  final institution = institutionCtrl.text.trim();
                                  final accNum = accNumCtrl.text.trim().isEmpty ? null : accNumCtrl.text.trim();
                                  final cardNum = cardNumCtrl.text.trim().isEmpty ? null : cardNumCtrl.text.trim();
                                  final bal = double.tryParse(balCtrl.text) ?? 0.0;
                                  final avail = double.tryParse(availCtrl.text);
                                  // Add custom type to database if provided
                                  if (customType != null && customType!.isNotEmpty) {
                                    DatabaseService.addCustomAccountType(customType!);
                                  }
                                  final acc = Account(name: name, type: selectedType, institution: institution.isEmpty ? null : institution, accountNumber: accNum, cardNumber: cardNum, balance: bal, availableBalance: avail, customType: customType);
                                  Navigator.pop(dctx, acc);
                                }, child: const Text('Add')),
                              ],
                            );
                          }),
                        );

                        if (res != null) {
                          await DatabaseService.addAccount(res);
                          final updated = DatabaseService.getAllAccounts();
                          setState2(() {});
                          setState(() {
                            accountList = updated;
                            _fromAccountId = res.id;
                          });
                        }
                      }),
                    ],
                  ),
                  body: ListView.builder(
                    itemCount: accountList.length,
                    itemBuilder: (context, idx) {
                      final a = accountList[idx];
                      return ListTile(
                        title: Text((a is Account) ? a.name : (a['name'] as String)),
                        onTap: () => Navigator.pop(context, (a is Account) ? a.id : (a['id'] as String)),
                      );
                    },
                  ),
                );
              }),
            ),
          );
          if (selected != null) setState(() => _fromAccountId = selected);
        },
      ),
    );
  }

  Widget _buildToAccountSelector() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.call_received),
        title: const Text('To'),
        subtitle: Text(_toAccountId == null ? 'Select to' : (() {
              try {
                final found = accountList.firstWhere((a) => a is Account ? a.id == _toAccountId : (a['id'] == _toAccountId));
                if (found is Account) return found.name;
                if (found is Map && found.containsKey('name')) return found['name'] as String;
              } catch (_) {}
              return 'Unknown';
            }())),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => FractionallySizedBox(
              heightFactor: 0.85,
              child: StatefulBuilder(builder: (ctx2, setState2) {
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('Select Account'),
                    backgroundColor: Theme.of(ctx2).colorScheme.primary,
                    foregroundColor: Colors.white,
                    actions: [
                      IconButton(icon: const Icon(Icons.add), onPressed: () async {
                        final nameCtrl = TextEditingController();
                        final institutionCtrl = TextEditingController();
                        final accNumCtrl = TextEditingController();
                        final cardNumCtrl = TextEditingController();
                        AccountType selectedType = AccountType.cash;
                        final balCtrl = TextEditingController(text: '0.0');
                        final availCtrl = TextEditingController(text: '0.0');
                        String? customType;
                          final res = await showDialog<Account?>(
                          context: ctx2,
                          builder: (dctx) => StatefulBuilder(builder: (dctx, dset) {
                            return AlertDialog(
                              title: const Center(child: Text('Add Account')),
                                content: SingleChildScrollView(
                                  child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(children: [
                                      const Text('Type:'),
                                      const SizedBox(width: 12),
                                      DropdownButton<AccountType>(
                                        value: selectedType,
                                        onChanged: (v) { if (v != null) dset(() => selectedType = v); },
                                        items: AccountType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline),
                                        tooltip: 'Add custom type',
                                        onPressed: () async {
                                          final textCtrl = TextEditingController();
                                          final res = await showDialog<String?>(
                                            context: dctx,
                                            builder: (tctx) => AlertDialog(
                                              title: const Text('Add account type'),
                                              content: TextField(controller: textCtrl, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Type name')),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(tctx), child: const Text('Cancel')),
                                                TextButton(onPressed: () {
                                                  final v = textCtrl.text.trim();
                                                  if (v.isEmpty) return;
                                                  Navigator.pop(tctx, v);
                                                }, child: const Text('Add')),
                                              ],
                                            ),
                                          );
                                          if (res != null) dset(() => customType = res);
                                        },
                                      ),
                                      if (customType != null) Padding(padding: const EdgeInsets.only(left:8.0), child: Text('($customType)', style: const TextStyle(fontStyle: FontStyle.italic))),
                                    ]),
                                    const SizedBox(height: 8),
                                      TextField(controller: nameCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Account')),
                                    const SizedBox(height: 8),
                                      TextField(controller: institutionCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.organizationName], decoration: const InputDecoration(labelText: 'Institution')),
                                    const SizedBox(height: 8),
                                      TextField(controller: accNumCtrl, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(labelText: 'Account number')),
                                    const SizedBox(height: 8),
                                    TextField(controller: cardNumCtrl, decoration: const InputDecoration(labelText: 'Card number')),
                                    const SizedBox(height: 8),
                                    const SizedBox(height: 8),
                                    TextField(controller: balCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Initial balance')),
                                    const SizedBox(height: 8),
                                      TextField(controller: availCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Available balance')),
                                    ],
                                  ),
                                ),
                                actions: [
                                TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                                TextButton(onPressed: () {
                                  final name = nameCtrl.text.trim();
                                  if (name.isEmpty) return;
                                  final institution = institutionCtrl.text.trim();
                                  final accNum = accNumCtrl.text.trim().isEmpty ? null : accNumCtrl.text.trim();
                                  final cardNum = cardNumCtrl.text.trim().isEmpty ? null : cardNumCtrl.text.trim();
                                  final bal = double.tryParse(balCtrl.text) ?? 0.0;
                                  final avail = double.tryParse(availCtrl.text);
                                  // Add custom type to database if provided
                                  if (customType != null && customType!.isNotEmpty) {
                                    DatabaseService.addCustomAccountType(customType!);
                                  }
                                  final acc = Account(name: name, type: selectedType, institution: institution.isEmpty ? null : institution, accountNumber: accNum, cardNumber: cardNum, balance: bal, availableBalance: avail, customType: customType);
                                  Navigator.pop(dctx, acc);
                                }, child: const Text('Add')),
                              ],
                            );
                          }),
                        );

                        if (res != null) {
                          await DatabaseService.addAccount(res);
                          final updated = DatabaseService.getAllAccounts();
                          setState2(() {});
                          setState(() {
                            accountList = updated;
                            _toAccountId = res.id;
                          });
                        }
                      })
                    ],
                  ),
                  body: ListView.builder(
                    itemCount: accountList.length,
                    itemBuilder: (context, idx) {
                      final a = accountList[idx];
                      return ListTile(
                        title: Text((a is Account) ? a.name : (a['name'] as String)),
                        onTap: () => Navigator.pop(context, (a is Account) ? a.id : (a['id'] as String)),
                      );
                    },
                  ),
                );
              }),
            ),
          );
          if (selected != null) setState(() => _toAccountId = selected);
        },
      ),
    );
  }
  
  Widget _buildCategorySelector() {
    final categoryForDisplay = _findCategoryById(_categories, _selectedCategoryId);

    return Card(
      child: ListTile(
        leading: categoryForDisplay == null
            ? const Icon(Icons.label)
            : Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: categoryForDisplay.color,
                  shape: BoxShape.circle,
                ),
              ),
        title: const Text('Category'),
        subtitle: Text(
          _selectedCategoryId == null
              ? 'Select'
              : (categoryForDisplay?.name ?? 'Select'),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          final selected = await showModalBottomSheet<String?>(
            context: context,
            isScrollControlled: true,
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.85,
              child: _CategorySelectorSheet(
                categories: _visibleCategories,
                initialSelectedId: _selectedCategoryId,
                billType: _billType,
              ),
            ),
          );
          if (selected != null) {
            // refresh categories from storage in case new were added
            final updated = DatabaseService.getAllCategories();
            setState(() {
              _categories = updated;
              _selectedCategoryId = selected;
            });
          }
        },
      ),
    );
  }
  // Reminder toggle intentionally removed. Reminder state remains on the
  // Bill model but is not editable from the Add/Edit screen.

  Widget _buildSaveButton() {
    // Render a centered elevated Save button for better affordance.
    return Center(
      child: SizedBox(
        width: 180,
        height: 48,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _saveBill,
          style: ElevatedButton.styleFrom(
            textStyle: const TextStyle(fontSize: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _isSaving
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Saving...'),
                  ],
                )
              : const Text('Save Bill'),
        ),
      ),
    );
  }

  void _refreshBillReminders() {
    BillReminderService().refreshAllReminders().catchError((e) {
      debugPrint('Reminder refresh failed after bill save: $e');
    });
  }

  Future<void> _saveBill() async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid amount'), backgroundColor: Colors.blueGrey[400]),
      );
      return;
    }

    // Enforce category selection for expense/income bills
    if ((_billType == BillType.expense || _billType == BillType.income) && _selectedCategoryId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select a category'), backgroundColor: Colors.blueGrey[400]),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    final normalizedDueDate = DateTime(_dueDate.year, _dueDate.month, _dueDate.day);
    final normalizedRecurrence = _recurrence;
    final normalizedRecurrenceEndDate = normalizedRecurrence == Recurrence.none
      ? null
      : (_recurrenceForever
        ? null
        : (_recurrenceEndDate == null
          ? null
          : DateTime(
            _recurrenceEndDate!.year,
            _recurrenceEndDate!.month,
            _recurrenceEndDate!.day,
            )));
    final List<int>? normalizedRecurrenceWeekdays = normalizedRecurrence == Recurrence.weekly
      ? ((_recurrenceWeekdays == null || _recurrenceWeekdays!.isEmpty)
        ? null
        : (_recurrenceWeekdays!.toSet().toList()..sort()))
      : null;
    final List<int>? normalizedCustomDays = normalizedRecurrence == Recurrence.monthly
        ? ((_customDays == null || _customDays!.isEmpty)
        ? <int>[normalizedDueDate.day]
            : (_customDays!.toSet().toList()..sort()))
        : null;
    // Default: persist a Bill (existing behavior)
    final Bill bill;
    final notes = _notesController.text.trim();
    final isCreateFlow = widget.existingBill == null || widget.isDuplicate;
    final existingNotes = _initialNotes;
    String? description;
    if (isCreateFlow) {
      // For new/duplicate bills, only persist notes explicitly entered in this flow.
      description = (_didUserEditNotes && notes.isNotEmpty) ? notes : null;
    } else {
      // For edits, preserve current notes unless the user intentionally changed them.
      if (_didUserEditNotes) {
        description = notes.isEmpty ? null : notes;
      } else {
        description = existingNotes.isEmpty ? null : existingNotes;
      }
    }
    if (widget.existingBill != null) {
      // Updating existing bill
      bill = widget.existingBill!.copyWith(
        amount: amount,
        description: description,
        dueDate: normalizedDueDate,
        recurrence: normalizedRecurrence,
        customDays: normalizedCustomDays,
        recurrenceEndDate: normalizedRecurrenceEndDate,
        recurrenceInterval: _recurrenceInterval,
        recurrenceWeekdays: normalizedRecurrenceWeekdays,
        categoryId: _selectedCategoryId,
        type: _billType,
        fromAccountId: _billType == BillType.transfer ? _fromAccountId : null,
        toAccountId: _billType == BillType.transfer ? _toAccountId : null,
        payeeId: _selectedPayeeId,
        accountId: _selectedAccountId,
        // leave reminderEnabled unchanged when editing here
      );
    } else {
      // Creating new bill
      bill = Bill(
        amount: amount,
        description: description,
        dueDate: normalizedDueDate,
        recurrence: normalizedRecurrence,
        customDays: normalizedCustomDays,
        recurrenceEndDate: normalizedRecurrenceEndDate,
        recurrenceInterval: _recurrenceInterval,
        recurrenceWeekdays: normalizedRecurrenceWeekdays,
        categoryId: _selectedCategoryId,
        type: _billType,
        fromAccountId: _billType == BillType.transfer ? _fromAccountId : null,
        toAccountId: _billType == BillType.transfer ? _toAccountId : null,
        payeeId: _selectedPayeeId,
        accountId: _selectedAccountId,
        isPaid: false,
        // do not set reminderEnabled here; use Bill default (false)
      );
    }

    try {
      if (widget.existingBill != null && !widget.isDuplicate) {
        await DatabaseService.updateBill(
          bill,
          reminderOffsets: _remindersEnabled ? _selectedReminders : const <ReminderOffset>[],
        );

        final previousBill = widget.existingBill!;
        final oldDueDate = DateTime(
          previousBill.dueDate.year,
          previousBill.dueDate.month,
          previousBill.dueDate.day,
        );
        final newDueDate = DateTime(
          bill.dueDate.year,
          bill.dueDate.month,
          bill.dueDate.day,
        );

        // Preserve payment history linkage when editing a one-time bill's due date.
        if (previousBill.recurrence == Recurrence.none &&
            bill.recurrence == Recurrence.none &&
            oldDueDate != newDueDate) {
          final oldDateToken = DateFormat('MM/dd/yyyy').format(oldDueDate);
          final relatedTx = DatabaseService.getAllTransactions()
              .where((t) => t.billId == bill.id)
              .toList();

          for (final tx in relatedTx) {
            final txDateOnly = DateTime(tx.date.year, tx.date.month, tx.date.day);
            final txOccurrenceOnly = tx.occurrenceDate == null
                ? null
                : DateTime(
                    tx.occurrenceDate!.year,
                    tx.occurrenceDate!.month,
                    tx.occurrenceDate!.day,
                  );
            final hasLegacyDateLink =
                tx.description.contains(oldDateToken) ||
                (tx.paymentFor ?? '').contains(oldDateToken);

            final shouldRemap =
                (txOccurrenceOnly != null && txOccurrenceOnly == oldDueDate) ||
                (txOccurrenceOnly == null && (txDateOnly == oldDueDate || hasLegacyDateLink));

            if (!shouldRemap) continue;

            await DatabaseService.updateTransaction(
              tx.copyWith(
                occurrenceDate: newDueDate,
                updatedAt: DateTime.now(),
              ),
            );
          }
        }

        // Bill amount/recurrence edits can invalidate cached per-occurrence
        // payment statuses (e.g., previously paid now becomes partial/unpaid).
        // Clear cached statuses first, then rebuild from related payments below.
        await DatabaseService.clearBillOccurrenceStatusesForBill(bill.id);
        
        // If this is an edit of an existing bill, and there are already
        // recorded payments for this bill (partial or otherwise), keep
        // those payments visible by removing them from the hidden list.
        // This ensures users see payments they've already made after
        // changing the bill amount.
        final allTx = DatabaseService.getAllTransactions();
        final related = allTx.where((t) => t.billId == bill.id).toList();
        if (related.isNotEmpty) {
          for (final tx in related) {
            try {
              await DatabaseService.removeHiddenTransactionId(tx.id);
            } catch (_) {}
          }
        }
        // Persist per-occurrence statuses for any occurrence dates that have
        // related payments. This ensures the dashboard/calendar will use the
        // persisted status (which includes these payments) instead of
        // recomputing totals that may exclude hidden transaction markers.
        try {
          final allTx = DatabaseService.getAllTransactions();
          // Build a set of occurrence dates present in related transactions
          final occDates = <DateTime>{};
          for (final tx in related) {
            if (tx.occurrenceDate != null) {
              occDates.add(DateTime(tx.occurrenceDate!.year, tx.occurrenceDate!.month, tx.occurrenceDate!.day));
            } else {
              occDates.add(DateTime(tx.date.year, tx.date.month, tx.date.day));
            }
          }

          for (final occ in occDates) {
            final occDateStr = DateFormat('MM/dd/yyyy').format(occ);
            double totalPaid = 0.0;
            for (final t in allTx) {
              if (t.billId != bill.id) continue;
              if (t.occurrenceDate != null) {
                if (t.occurrenceDate!.year == occ.year && t.occurrenceDate!.month == occ.month && t.occurrenceDate!.day == occ.day) {
                  if (bill.type == BillType.expense) {
                    totalPaid += (t.type == TransactionType.expense) ? t.amount : -t.amount;
                  } else {
                    totalPaid += (t.type == TransactionType.income) ? t.amount : -t.amount;
                  }
                }
              } else if (t.date.year == occ.year && t.date.month == occ.month && t.date.day == occ.day) {
                if (bill.type == BillType.expense) {
                  totalPaid += (t.type == TransactionType.expense) ? t.amount : -t.amount;
                } else {
                  totalPaid += (t.type == TransactionType.income) ? t.amount : -t.amount;
                }
              } else if (t.description.contains(occDateStr)) {
                if (bill.type == BillType.expense) {
                  totalPaid += (t.type == TransactionType.expense) ? t.amount : -t.amount;
                } else {
                  totalPaid += (t.type == TransactionType.income) ? t.amount : -t.amount;
                }
              }
            }

            PaymentStatus newStatus;
            if (totalPaid <= 0) {
              newStatus = PaymentStatus.unpaid;
            } else if (totalPaid >= (bill.amount - 0.01)) {
              newStatus = PaymentStatus.paid;
            } else {
              newStatus = PaymentStatus.partial;
            }
            await DatabaseService.setBillOccurrenceStatus(bill.id, occ, newStatus == PaymentStatus.paid, newStatus);
          }
        } catch (_) {}
      } else {
        await DatabaseService.addBill(
          bill,
          reminderOffsets: _remindersEnabled ? _selectedReminders : const <ReminderOffset>[],
        );
      }
      // Ensure listeners get a definitive notification (defensive) so
      // UI like the dashboard/calendar always refreshes when notes are
      // removed or other bill fields change.
      try {
        DatabaseService.billsVersion.value++;
      } catch (_) {}
      _refreshBillReminders();
      
      // Bills are now displayed via the recurring system (getBillOccurrencesBetween)
      // which handles both one-time and recurring bills, preventing duplicates
      
      if (mounted) {
        // When saving a duplicated bill (used for "Only this occurrence" edits)
        // return the created bill id so callers (e.g. dashboard) can migrate
        // existing payments to the new occurrence-specific bill. For regular
        // saves return `true` to preserve existing call sites.
        if (widget.isDuplicate) {
          Navigator.pop(context, bill.id);
        } else {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving bill: $e'), backgroundColor: Colors.blueGrey[400]),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}
