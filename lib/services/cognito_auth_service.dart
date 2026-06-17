// lib/services/cognito_auth_service.dart
// ignore_for_file: unused_local_variable, unused_import, unused_element

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth/flutter_web_auth.dart';

import 'http_service.dart';

/// Helper to perform Cognito OAuth flows (e.g. Sign in with Apple)
class CognitoAuthService {
  // Host (no scheme) used with `Uri.https`.
  final String domainHost = 'us-east-1_i8OdXtL1u.auth.us-east-1.amazoncognito.com';
  final String userPoolId = 'us-east-1_i8OdXtL1u';
  final String clientId = '2fep4tchr2g6olsbs9nj7nd4u4';
  final String redirectUri = 'myapp://callback';

  /// Initiate the hosted UI /authorize request using Cognito and Apple as
  /// the identity provider. Opens the system browser and waits for the
  /// redirect to the app URI scheme, extracts the `code` and exchanges it
  /// for tokens.
  // Apple hosted UI sign-in removed. This helper previously opened the
  // Cognito hosted UI for Sign-in with Apple and exchanged the returned
  // authorization code for tokens. Functionality was removed to keep
  // the app limited to username/password authentication.

  /// Exchange authorization code for tokens at the Cognito `/oauth2/token` endpoint.
  Future<void> _exchangeCodeForTokens(String code) async {
    final tokenUrl = Uri.https(domainHost, '/oauth2/token');

    final resp = await HttpService.execute(
      () => http.post(
        tokenUrl,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'code': code,
          'redirect_uri': redirectUri,
        },
      ),
    );

    if (resp.statusCode != 200) {
      throw Exception('Token exchange failed (${resp.statusCode}): ${resp.body}');
    }

    final Map<String, dynamic> data = json.decode(resp.body);

    // Example: data contains access_token, id_token, refresh_token, expires_in
    // Tokens are returned in `data` for callers to handle as needed.

    // TODO: persist tokens securely (e.g. secure_storage) or send to backend
    // This implementation leaves token handling to the caller / app.
    return;
  }
}

final cognitoAuthService = CognitoAuthService();
