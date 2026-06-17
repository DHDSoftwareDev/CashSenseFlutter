import 'package:flutter/foundation.dart';

import '../models/lookup_item.dart';
import 'cloud_sync_policy.dart';
import 'database_service.dart';
import 'lookups_repository.dart';

class LookupsState extends ChangeNotifier {
  final LookupsRepository repository;

  Map<String, LookupItem> categoriesById = {};
  Map<String, LookupItem> payeesById = {};
  Map<String, LookupItem> payersById = {};

  LookupsState(this.repository);

  bool _looksLikeOpaqueId(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (uuid.hasMatch(v)) return true;
    final longToken = RegExp(r'^[A-Za-z0-9_-]{16,}$');
    return longToken.hasMatch(v);
  }

  String _sanitizeCategoryLabel(String? value) {
    final label = (value ?? '').trim();
    if (label.isEmpty) return '';
    final normalized = label.toLowerCase();
    if (normalized == 'unknown' || normalized == 'unknown category') return '';
    if (_looksLikeOpaqueId(label)) return '';
    return label;
  }

  Future<void> loadFromLocal() async {
    final categories = await repository.getLocalByType('category');
    final payees = await repository.getLocalByType('payee');
    final payers = await repository.getLocalByType('payer');

    categoriesById = {for (final x in categories) x.id: x};
    payeesById = {for (final x in payees) x.id: x};
    payersById = {for (final x in payers) x.id: x};
    notifyListeners();
  }

  Future<void> syncRemote() async {
    if (!CloudSyncPolicy.syncUserFinanceDataToAws) {
      return;
    }

    final plan = DatabaseService.subscriptionVersion.value;
    if (plan == 'Free') {
      return;
    }

    final categories = await repository.syncType('category');
    final payees = await repository.syncType('payee');
    final payers = await repository.syncType('payer');

    categoriesById = {for (final x in categories) x.id: x};
    payeesById = {for (final x in payees) x.id: x};
    payersById = {for (final x in payers) x.id: x};
    notifyListeners();
  }

  String categoryName(String? id, {String? fallbackName}) {
    final resolved = categoriesById[id ?? '']?.name;
    final sanitizedResolved = _sanitizeCategoryLabel(resolved);
    if (sanitizedResolved.isNotEmpty) return sanitizedResolved;

    final sanitizedFallback = _sanitizeCategoryLabel(fallbackName);
    if (sanitizedFallback.isNotEmpty) return sanitizedFallback;

    return '';
  }

  String payeeName(String? id, {String? fallbackName}) {
    if (id == null || id.isEmpty) return fallbackName ?? '';
    return payeesById[id]?.name ?? fallbackName ?? id;
  }

  String payerName(String? id, {String? fallbackName}) {
    if (id == null || id.isEmpty) return fallbackName ?? '';
    return payersById[id]?.name ?? fallbackName ?? id;
  }
}
