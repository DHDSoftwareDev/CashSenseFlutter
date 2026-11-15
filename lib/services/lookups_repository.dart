import 'account_operations.dart';
import '../models/lookup_item.dart';
import 'lookups_api.dart';

abstract class LookupsLocalStore {
  Future<void> saveAll(String type, List<LookupItem> items);
  Future<List<LookupItem>> getAll(String type);
  Future<void> upsertOne(LookupItem item);
  Future<void> deleteOne(String type, String id);
}

class LookupsRepository {
  final LookupsApi api;
  final LookupsLocalStore localStore;

  LookupsRepository({required this.api, required this.localStore});

  Future<List<LookupItem>> syncType(String type) {
    return AccountOperations.run(() async {
    final remote = await api.fetchByType(type);
    await localStore.saveAll(type, remote);
    return remote;
      });
  }

  Future<void> syncAll() {
    return AccountOperations.run(() async {
    await syncType('category');
    await syncType('payee');
    await syncType('payer');
      });
  }

  Future<List<LookupItem>> getLocalByType(String type) {
    return localStore.getAll(type);
  }

  Future<LookupItem> createOrUpdate({
    required String type,
    required String id,
    required String name,
    String? color,
    String? icon,
    String? categoryId,
    bool? isIncome,
    int sortOrder = 0,
  }) {
    return AccountOperations.run(() async {
    final saved = await api.upsert(
      type: type,
      id: id,
      name: name,
      color: color,
      icon: icon,
      categoryId: categoryId,
      isIncome: isIncome,
      sortOrder: sortOrder,
    );

    final toStore = categoryId != null && saved.categoryId == null
        ? saved.copyWith(categoryId: categoryId)
        : saved;
    await localStore.upsertOne(toStore);
    return toStore;
      });
  }

  Future<void> delete({required String type, required String id}) {
    return AccountOperations.run(() async {
    await api.delete(type: type, id: id);
    await localStore.deleteOne(type, id);
      });
  }
}
