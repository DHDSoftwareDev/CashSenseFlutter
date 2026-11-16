import 'package:flutter/services.dart';

class CashSenseRefundTest {
  static const _channel = MethodChannel('cashsense/sandbox_refund');

  static Future<List<Map<String, String>>> transactions(String owner) async {
    final rows = await _channel.invokeListMethod<dynamic>('transactions', {'owner': owner});
    return (rows ?? []).map((row) => Map<String, String>.from(row as Map)).toList();
  }

  static Future<String> request(String owner, String transactionId) async {
    return await _channel.invokeMethod<String>('request', {
      'owner': owner, 'transactionId': transactionId,
    }) ?? 'unknown';
  }
}
