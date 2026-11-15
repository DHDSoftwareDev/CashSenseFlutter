// ignore_for_file: avoid_relative_lib_imports, avoid_print
import '../lib/services/backup_payload_policy.dart';

Map<String, dynamic> fixture() => {
  'version': '1.1.0',
  'accounts': [{'id': 'a', 'name': 'Test', 'type': 'cash', 'balance': 5}],
  'bills': [], 'transactions': [], 'categories': [],
  'payees': [], 'payers': [],
  'settings': {'initialBalance:a': 5, 'subscriptionPlan': 'Lifetime',
    'subscriptionModeOverride': 'Developer', 'accountOrder': ['a']},
  'bill_occurrence_status': <String, dynamic>{},
};

void main() {
  var passed = 0;
  void check(bool condition, String label) {
    if (!condition) throw StateError('FAIL: $label');
    passed++;
    print('PASS: $label');
  }
  BackupPayloadPolicy.validate(fixture());
  check(true, 'Valid current backup accepted');
  final filtered = BackupPayloadPolicy.financialSettings(fixture()['settings']);
  check(!filtered.containsKey('subscriptionPlan'), 'Paid plan excluded');
  check(!filtered.containsKey('subscriptionModeOverride'), 'Local override excluded');
  check(filtered['initialBalance:a'] == 5, 'Opening balance preserved');
  check(filtered.containsKey('accountOrder'), 'Account order preserved');
  final cases = <String, void Function(Map<String, dynamic>)>{
    'Unsupported version': (m) => m['version'] = '0.0.0',
    'Missing accounts': (m) => m.remove('accounts'),
    'Malformed record': (m) => m['transactions'] = ['bad'],
    'Missing ID': (m) => m['accounts'] = [{'name': 'Test'}],
    'Duplicate ID': (m) => m['accounts'] = [{'id': 'a'}, {'id': 'a'}],
    'Missing opening balance': (m) => m['settings'] = {'accountOrder': []},
    'Missing payer section': (m) => m.remove('payers'),
    'Invalid bill statuses': (m) => m['bill_occurrence_status'] = [],
  };
  for (final entry in cases.entries) {
    final data = fixture();
    entry.value(data);
    var rejected = false;
    try { BackupPayloadPolicy.validate(data); } on FormatException { rejected = true; }
    check(rejected, '${entry.key} rejected');
  }
  print('$passed checks passed');
}
