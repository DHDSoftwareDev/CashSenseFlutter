import 'dart:convert';
import 'package:http/http.dart' as http;

class BillPushSyncService {
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://api.yourdomain.com',
  );

  static Future<void> syncBills(
    String userId,
    List<Map<String, dynamic>> bills,
  ) async {
    await http.post(
      Uri.parse('$baseUrl/api/users/$userId/bills/sync'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'bills': bills}),
    );
  }

  static Future<void> markBillPaid(String userId, String billId) async {
    await http.post(
      Uri.parse('$baseUrl/api/users/$userId/bills/$billId/paid'),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
