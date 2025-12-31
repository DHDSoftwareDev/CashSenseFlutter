import 'dart:convert';

/// Utilities for transaction splits.
List<Map<String, dynamic>> parseSplitsJson(String? jsonStr) {
  if (jsonStr == null || jsonStr.trim().isEmpty) return [];
  try {
    final data = json.decode(jsonStr);
    if (data is List) {
      return data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
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

bool validateSplitsEqualAmount(List<Map<String, dynamic>> splits, double total, {double tolerance = 0.01}) {
  final sum = sumSplits(splits);
  return (sum - total).abs() <= tolerance;
}
