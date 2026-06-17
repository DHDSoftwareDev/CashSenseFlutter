import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

class HttpService {
  static const Duration requestTimeout = Duration(seconds: 12);
  static const Duration _baseRetryDelay = Duration(milliseconds: 400);

  static Future<http.Response> execute(
    Future<http.Response> Function() request, {
    int maxAttempts = 1,
    bool retryOnFailure = false,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await request().timeout(requestTimeout);
        if (_shouldRetryStatus(response.statusCode) &&
            attempt < maxAttempts &&
            retryOnFailure) {
          await Future<void>.delayed(_retryDelayForAttempt(attempt));
          continue;
        }
        return response;
      } catch (e) {
        lastError = e;
        final canRetry =
            attempt < maxAttempts &&
            _isTransientError(e) &&
            retryOnFailure;
        if (!canRetry) rethrow;
        await Future<void>.delayed(_retryDelayForAttempt(attempt));
      }
    }

    throw lastError ?? StateError('HTTP request failed without error details');
  }

  static bool _shouldRetryStatus(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  static bool _isTransientError(Object error) {
    return error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException;
  }

  static Duration _retryDelayForAttempt(int attempt) {
    return Duration(
      milliseconds: _baseRetryDelay.inMilliseconds * attempt,
    );
  }
}
