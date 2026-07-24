import 'dart:convert';

/// Utilities for transaction splits.
List<Map<String, dynamic>> parseSplitsJson(String? jsonStr) {
  if (jsonStr == null || jsonStr.trim().isEmpty) return [];
  try {
    final data = json.decode(jsonStr);
    if (data is List) {
      return data
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
  } catch (_) {}
  return [];
}

double sumSplits(List<Map<String, dynamic>> splits) {
  return splits.fold<double>(0.0, (s, e) {
    final amt = e['amount'];
    if (amt is num) return s + amt.toDouble();
    if (amt is String) return s + (double.tryParse(amt) ?? 0.0);
    return s;
  });
}

bool validateSplitsEqualAmount(
  List<Map<String, dynamic>> splits,
  double total, {
  double tolerance = 0.01,
}) {
  final sum = sumSplits(splits);
  return (sum - total).abs() <= tolerance;
}

bool validateSplitCategories(List<Map<String, dynamic>> splits) {
  return splits.isNotEmpty &&
      splits.every((split) {
        final categoryId = split['categoryId']?.toString().trim() ?? '';
        final amount = split['amount'];
        final parsedAmount = amount is num
            ? amount.toDouble()
            : double.tryParse(amount?.toString() ?? '');
        return categoryId.isNotEmpty &&
            parsedAmount != null &&
            parsedAmount > 0;
      });
}

/// Returns the category amounts represented by a transaction.
///
/// Valid split data replaces the primary category allocation. Invalid or
/// legacy split data falls back to the transaction's primary category so a
/// malformed payload cannot make money disappear from reports.
Map<String, double> categoryAllocations({
  required String primaryCategoryId,
  required double total,
  String? splitsJson,
}) {
  final splits = parseSplitsJson(splitsJson);
  if (validateSplitCategories(splits) &&
      validateSplitsEqualAmount(splits, total)) {
    final allocations = <String, double>{};
    for (final split in splits) {
      final categoryId = split['categoryId'].toString().trim();
      final rawAmount = split['amount'];
      final amount = rawAmount is num
          ? rawAmount.toDouble()
          : double.parse(rawAmount.toString());
      allocations[categoryId] = (allocations[categoryId] ?? 0) + amount;
    }
    return allocations;
  }
  return {primaryCategoryId.trim(): total};
}

bool transactionUsesCategory({
  required String primaryCategoryId,
  required double total,
  required String categoryId,
  String? splitsJson,
}) {
  return categoryAllocations(
    primaryCategoryId: primaryCategoryId,
    total: total,
    splitsJson: splitsJson,
  ).containsKey(categoryId.trim());
}
