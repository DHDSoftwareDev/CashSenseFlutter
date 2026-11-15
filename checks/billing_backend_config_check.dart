// ignore_for_file: avoid_relative_lib_imports, avoid_print
// Standalone tests; run with: dart checks/billing_backend_config_check.dart
import '../lib/services/billing_backend_config.dart';

void main() {
  var passed = 0;
  const production = 'https://prod123.execute-api.us-east-1.amazonaws.com/Prod';
  const staging = 'https://stage123.execute-api.us-east-1.amazonaws.com';
  String resolve(String environment, String stagingUrl, [String prod = production]) =>
      BillingBackendConfig.resolveBaseUrl(environment: environment,
          stagingUrl: stagingUrl, productionUrl: prod);
  void expectEqual(Object? actual, Object? expected) {
    if (actual != expected) throw StateError('Expected $expected; got $actual');
    passed++;
  }
  void expectBlocked(String mode, String url, [String prod = production]) {
    try { resolve(mode, url, prod); } on StateError { passed++; return; }
    throw StateError('Expected configuration rejection: $mode $url');
  }
  expectEqual(resolve('production', ''), production);
  expectEqual(resolve('production', staging), production);
  expectEqual(resolve('staging', staging), staging);
  expectEqual(resolve('staging', '$staging/'), staging);
  expectBlocked('test', staging);
  expectBlocked('staging', '');
  expectBlocked('staging', 'http://stage123.execute-api.us-east-1.amazonaws.com');
  expectBlocked('staging', 'https://example.com');
  expectBlocked('staging', '$staging?test=1');
  expectBlocked('staging', '$staging#fragment');
  expectBlocked('staging', '$staging/Prod');
  expectBlocked('staging', 'https://stage123.execute-api.us-east-1.amazonaws.com:444');
  expectBlocked('staging', 'https://user@stage123.execute-api.us-east-1.amazonaws.com');
  expectBlocked('staging', staging, staging);
  expectBlocked('staging', '$staging/', staging);
  print('PASS $passed billing URL configuration checks');
}
