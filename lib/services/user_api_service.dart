import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/cashsense_user.dart';
import 'aws_api_service.dart';
import 'http_service.dart';
import 'user_auth_service.dart';

class CashSenseUserApi {
  final String baseUrl;

  CashSenseUserApi({required this.baseUrl});

  Future<CashSenseUser> getCurrentUser({required String idToken}) async {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$normalizedBase/users/me');

    final res = await HttpService.execute(
      () => http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
      ),
      maxAttempts: 2,
      retryOnFailure: true,
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to load user: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final userJson = decoded['user'] as Map<String, dynamic>?;

    if (userJson == null) {
      throw Exception('Missing user object in response');
    }

    return CashSenseUser.fromJson(userJson);
  }
}

class UserApiService {
  static String get _baseUrl => (dotenv.env['API_BASE_URL'] ?? '').trim();

  static Future<CashSenseUser> fetchCurrentUser() async {
    if (_baseUrl.isEmpty) {
      throw StateError('AWS API base URL not configured');
    }

    final token = await AwsApiService.getIdToken();
    if (token.isEmpty) {
      throw StateError('Missing ID token. User may not be signed in yet.');
    }

    final api = CashSenseUserApi(baseUrl: _baseUrl);
    final user = await api.getCurrentUser(idToken: token);

    await UserAuthService.saveUserInfo(
      userId: user.userId,
      email: user.email,
      displayName: user.name,
    );

    return user;
  }
}
