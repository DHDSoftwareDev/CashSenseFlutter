import 'package:flutter/material.dart';
import '../services/database_service.dart';

class _CardItem {
  final String id;
  final String label;
  final String? description;
  const _CardItem(this.id, this.label, [this.description]);
}

class ManageCardsScreen extends StatelessWidget {
  const ManageCardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ManageCardsBody();
  }
}

class _ManageCardsBody extends StatefulWidget {
  const _ManageCardsBody();

  @override
  State<_ManageCardsBody> createState() => _ManageCardsBodyState();
}

class _ManageCardsBodyState extends State<_ManageCardsBody> {
  static const List<_CardItem> _availableCards = [
    _CardItem('summary_totals', 'Summary Totals', 'Income / Expenses / Net'),
    _CardItem('expenses_pie', 'Expenses (by Category)'),
    _CardItem('income_pie', 'Income (by Category)'),
    _CardItem('payee_pie', 'Payees'),
    _CardItem('payer_pie', 'Payers'),
    _CardItem('payee_payer_net', 'Payee vs Payer Net'),
    _CardItem('expense_income_net', 'Expense / Income Net'),
    _CardItem('monthly_trend', '6-Month Trend'),
  ];

  late Set<String> _visible;

  @override
  void initState() {
    super.initState();
    final saved = DatabaseService.getSetting<List<dynamic>>('reportsVisibleCards', null);
    if (saved == null) {
      _visible = _availableCards.map((c) => c.id).toSet();
    } else {
      _visible = saved.map((e) => e.toString()).toSet();
      // Ensure defaults for any missing card ids
      for (final c in _availableCards) {
        if (!_visible.contains(c.id)) {
          // leave hidden unless explicitly present in saved list
        }
      }
    }
  }

  Future<void> _setVisible(String id, bool visible) async {
    setState(() {
      if (visible) {
        _visible.add(id);
      } else {
        _visible.remove(id);
      }
    });
    // Persist the visible list
    await DatabaseService.setSetting('reportsVisibleCards', _visible.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Cards'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text('Choose which cards should be visible on the Reports screen.'),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _availableCards.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final c = _availableCards[i];
                  final isVisible = _visible.contains(c.id);
                  return SwitchListTile(
                    title: Text(c.label),
                    subtitle: c.description != null ? Text(c.description!) : null,
                    value: isVisible,
                    onChanged: (v) => _setVisible(c.id, v),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
