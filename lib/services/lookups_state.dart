import 'package:flutter/foundation.dart';

import '../models/lookup_item.dart';
import 'lookups_repository.dart';

class LookupsState extends ChangeNotifier {
  final LookupsRepository repository;

  Map<String, LookupItem> categoriesById = {};
  Map<String, LookupItem> payeesById = {};
  Map<String, LookupItem> payersById = {};

  LookupsState(this.repository);

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
    final categories = await repository.syncType('category');
    final payees = await repository.syncType('payee');
    final payers = await repository.syncType('payer');

    categoriesById = {for (final x in categories) x.id: x};
    payeesById = {for (final x in payees) x.id: x};
    payersById = {for (final x in payers) x.id: x};
    notifyListeners();
  }

  String categoryName(String? id, {String? fallbackName}) {
    if (id == null || id.isEmpty) return fallbackName ?? '';
    return categoriesById[id]?.name ?? fallbackName ?? id;
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
