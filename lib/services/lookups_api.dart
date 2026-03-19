import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/lookup_item.dart';

class LookupsApi {
  final String baseUrl;
  final Future<Map<String, String>> Function() authHeadersBuilder;

  LookupsApi({
    required this.baseUrl,
    required this.authHeadersBuilder,
  });

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Future<List<LookupItem>> fetchByType(String type) async {
    final headers = await authHeadersBuilder();

    final response = await http.get(
      _uri('/lookups', {'type': type}),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load $type lookups: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (decoded['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(LookupItem.fromJson)
        .toList();

    return items;
  }

  Future<LookupItem> upsert({
    required String type,
    required String id,
    required String name,
    String? color,
    String? icon,
    int sortOrder = 0,
  }) async {
    final headers = await authHeadersBuilder();

    final response = await http.post(
      _uri('/lookups'),
      headers: {
        ...headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': type,
        'id': id,
        'name': name,
        'color': color,
        'icon': icon,
        'sortOrder': sortOrder,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to save lookup: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return LookupItem.fromJson(decoded['item'] as Map<String, dynamic>);
  }

  Future<void> delete({
    required String type,
    required String id,
  }) async {
    final headers = await authHeadersBuilder();

    final request = http.Request('DELETE', _uri('/lookups'));
    request.headers.addAll({
      ...headers,
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode({
      'type': type,
      'id': id,
    });

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception('Failed to delete lookup: ${response.body}');
    }
  }
}
