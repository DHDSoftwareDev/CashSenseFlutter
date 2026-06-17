import 'dart:convert';

import 'package:http/http.dart' as http;

import 'services/http_service.dart';

class NotificationSchedulesApi {
  NotificationSchedulesApi({
    required this.baseUrl, // e.g. https://xxxx.execute-api.us-east-1.amazonaws.com/prod
    required this.getIdToken, // your Cognito idToken provider
  });

  final String baseUrl;
  final Future<String> Function() getIdToken;

  Future<Map<String, dynamic>> createSchedule({
    required String runAtUtcIso,
    required String timeZone,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    required String dedupeKey,
  }) async {
    final token = await getIdToken();
    final uri = Uri.parse('$baseUrl/notification-schedules');

    final res = await HttpService.execute(
      () => http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'runAt': runAtUtcIso,
          'timeZone': timeZone,
          'title': title,
          'body': body,
          'data': data,
          'dedupeKey': dedupeKey,
        }),
      ),
      maxAttempts: 2,
      retryOnFailure: true,
    );

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('createSchedule failed: ${res.statusCode} $decoded');
    }
    return decoded;
  }

  Future<void> deleteSchedule({required String scheduleId}) async {
    final token = await getIdToken();
    final uri = Uri.parse('$baseUrl/notification-schedules/$scheduleId');

    final res = await HttpService.execute(
      () => http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
      maxAttempts: 2,
      retryOnFailure: true,
    );

    if (res.statusCode != 200) {
      throw Exception('deleteSchedule failed: ${res.statusCode} ${res.body}');
    }
  }
}
