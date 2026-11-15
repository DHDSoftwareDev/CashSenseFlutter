/// Compile-time billing routing. Production remains the default.
class BillingBackendConfig {
  static const String environment = String.fromEnvironment(
    'CASH_SENSE_BILLING_ENVIRONMENT',
    defaultValue: 'production',
  );
  static const String _stagingUrl = String.fromEnvironment(
    'CASH_SENSE_BILLING_STAGING_URL',
  );

  static bool get isStaging {
    if (environment != 'production' && environment != 'staging') {
      throw StateError('Unknown CashSense billing environment.');
    }
    return environment == 'staging';
  }

  static String baseUrl(String productionUrl) => resolveBaseUrl(
    environment: environment,
    stagingUrl: _stagingUrl,
    productionUrl: productionUrl,
  );

  static String resolveBaseUrl({
    required String environment,
    required String stagingUrl,
    required String productionUrl,
  }) {
    if (environment != 'production' && environment != 'staging') {
      throw StateError('Unknown CashSense billing environment.');
    }
    if (environment == 'production') return productionUrl.trim();
    final value = stagingUrl.trim();
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.port != 443 ||
        !RegExp(r'^[a-z0-9]+\.execute-api\.us-east-1\.amazonaws\.com$')
            .hasMatch(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw StateError('Set the staging HTTP API URL returned by create_api.py.');
    }
    final normalized = value.replaceFirst(RegExp(r'/+$'), '');
    if (normalized == productionUrl.trim().replaceFirst(RegExp(r'/+$'), '')) {
      throw StateError('Staging billing must use a separate API endpoint.');
    }
    return normalized;
  }
}
