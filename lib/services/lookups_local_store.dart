import '../models/lookup_item.dart';
import 'database_service.dart';
import 'lookups_repository.dart';

class SettingsLookupsLocalStore implements LookupsLocalStore {
  static String _keyForType(String type) => 'lookups:$type';

  @override
  Future<void> saveAll(String type, List<LookupItem> items) async {
    final payload = items.map((x) => x.toJson()).toList();
    await DatabaseService.setSetting(_keyForType(type), payload);
  }

  @override
  Future<List<LookupItem>> getAll(String type) async {
    try {
      final raw = DatabaseService.getSetting<dynamic>(_keyForType(type), <dynamic>[]);
      if (raw is! List) return <LookupItem>[];
      return raw
          .whereType<Map>()
          .map((x) => LookupItem.fromJson(Map<String, dynamic>.from(x)))
          .toList();
    } catch (_) {
      return <LookupItem>[];
    }
  }

  @override
  Future<void> upsertOne(LookupItem item) async {
    final current = await getAll(item.type);
    final idx = current.indexWhere((x) => x.id == item.id);
    if (idx == -1) {
      current.add(item);
    } else {
      current[idx] = item;
    }
    await saveAll(item.type, current);
  }

  @override
  Future<void> deleteOne(String type, String id) async {
    final current = await getAll(type);
    current.removeWhere((x) => x.id == id);
    await saveAll(type, current);
  }
}
