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
    final cachedCategories = await repository.getLocalByType('category');
    final cachedPayees = await repository.getLocalByType('payee');
    final cachedPayers = await repository.getLocalByType('payer');

    final categories = <String, LookupItem>{
      for (final item in cachedCategories) item.id: item,
    };
    final payees = <String, LookupItem>{
      for (final item in cachedPayees) item.id: item,
    };
    final payers = <String, LookupItem>{
      for (final item in cachedPayers) item.id: item,
    };

    // Backup/restore hydrates the primary local database, not the legacy
    // lookups cache. Merge that data so restored labels appear immediately.
    final restoredAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final category in DatabaseService.getAllCategories()) {
      categories[category.id] = LookupItem(
        id: category.id,
        type: 'category',
        name: category.name,
        color: category.colorValue,
        icon: category.image ?? category.iconCodePoint,
        sortOrder: 0,
        isDeleted: false,
        createdAt: restoredAt,
        updatedAt: restoredAt,
      );
    }

    for (final contact in DatabaseService.getAllPayees()) {
      final id = (contact['id'] ?? '').toString().trim();
      final name = (contact['name'] ?? '').toString().trim();
      final type = (contact['type'] ?? '').toString().trim().toLowerCase();
      if (id.isEmpty || name.isEmpty || (type != 'payee' && type != 'payer')) {
        continue;
      }

      final item = LookupItem(
        id: id,
        type: type,
        name: name,
        color: contact['color']?.toString(),
        icon: contact['icon']?.toString(),
        categoryId: contact['categoryId']?.toString(),
        sortOrder: int.tryParse((contact['sortOrder'] ?? '0').toString()) ?? 0,
        isDeleted: false,
        createdAt: restoredAt,
        updatedAt: restoredAt,
      );
      if (type == 'payee') {
        payees[id] = item;
      } else {
        payers[id] = item;
      }
    }

    categoriesById = categories;
    payeesById = payees;
    payersById = payers;
    notifyListeners();
  }

  Future<void> syncRemote() async {
    if (!CloudSyncPolicy.syncUserFinanceDataToAws) {
      // Remote finance APIs are intentionally disabled. A premium restore may
      // just have updated Hive, so refresh the display maps from local data.
      await loadFromLocal();
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
