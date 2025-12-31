import 'package:intl/intl.dart';

/// Small currency formatting helpers used across the app.
///
/// Use `formatCurrency(amount)` or the extension `1234.5.toCurrency()` to
/// produce strings like "$1,234.50" for display.

String formatCurrency(num? amount) {
  final v = amount ?? 0;
  final fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$');
  return fmt.format(v);
}

extension CurrencyFormatting on num {
  String toCurrency() => NumberFormat.currency(locale: 'en_US', symbol: '\$').format(this);
}
