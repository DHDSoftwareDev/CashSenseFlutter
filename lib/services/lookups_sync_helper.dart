import '../models/category.dart';
import 'aws_api_service.dart';
import 'lookups_api.dart';
import 'lookups_local_store.dart';
import 'lookups_repository.dart';

class LookupsSyncHelper {
  static LookupsRepository? _repo;

  static LookupsRepository _repository() {
    _repo ??= LookupsRepository(
      api: LookupsApi(
        baseUrl: AwsApiService.baseUrl,
        authHeadersBuilder: () async {
          final token = await AwsApiService.getIdToken();
          if (token.isEmpty) return <String, String>{};
          return <String, String>{'Authorization': 'Bearer $token'};
        },
      ),
      localStore: SettingsLookupsLocalStore(),
    );
    return _repo!;
  }

  static String? _toHexColor(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('#')) return raw;
    final parsed = int.tryParse(raw);
    if (parsed == null) return null;
    final hex = parsed.toRadixString(16).toUpperCase().padLeft(8, '0');
    return '#$hex';
  }

  static Future<void> syncCategory(Category category) async {
    await _repository().createOrUpdate(
      type: 'category',
      id: category.id,
      name: category.name,
      color: _toHexColor(category.colorValue),
      icon: category.image ?? category.iconCodePoint,
      isIncome: category.type == CategoryType.income,
    );
  }

  static Future<void> syncPayeeOrPayer(Map<String, dynamic> item) async {
    final type = (item['type'] ?? '').toString().toLowerCase();
    if (type != 'payee' && type != 'payer') return;

    await _repository().createOrUpdate(
      type: type,
      id: (item['id'] ?? '').toString(),
      name: (item['name'] ?? '').toString(),
      color: _toHexColor(item['color']?.toString()),
      icon: item['icon']?.toString(),
      sortOrder: (item['sortOrder'] as int?) ?? 0,
    );
  }
}
