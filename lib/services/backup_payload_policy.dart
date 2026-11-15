class BackupPayloadPolicy {
  static Map<String, dynamic> financialSettings(Map<String, dynamic> settings) {
    return Map<String, dynamic>.fromEntries(settings.entries.where((entry) =>
        entry.key.startsWith('initialBalance:') ||
        const {'accountOrder', 'customAccountTypes',
          'hiddenFromCalendarTransactions', 'billRecurrenceEndOverrides'}
            .contains(entry.key)));
  }

  static void validate(Map<String, dynamic> data) {
    if (data['version'] != '1.1.0') {
      throw const FormatException('Unsupported backup version. Original data was kept.');
    }
    for (final section in ['accounts', 'bills', 'transactions', 'categories']) {
      final records = data[section];
      if (records is! List) throw FormatException('Missing $section list.');
      final ids = <String>{};
      for (final record in records) {
        if (record is! Map) throw FormatException('Invalid $section record.');
        final id = section == 'accounts'
            ? (record['accountId'] ?? record['id']) : record['id'];
        if (id is! String || id.trim().isEmpty || !ids.add(id)) {
          throw FormatException('Missing or duplicate $section ID.');
        }
      }
    }
    for (final section in ['payees', 'payers']) {
      final records = data[section];
      if (records is! List || records.any((item) => item is! Map)) {
        throw FormatException('Missing or invalid $section list.');
      }
    }
    final settings = data['settings'];
    if (settings is! Map || settings.isEmpty) {
      throw const FormatException('Missing financial settings.');
    }
    for (final account in data['accounts'] as List) {
      final id = account['accountId'] ?? account['id'];
      final balance = settings['initialBalance:$id'];
      if (balance is! num || !balance.isFinite) {
        throw const FormatException('Missing or invalid opening balance.');
      }
    }
    if (data['bill_occurrence_status'] is! Map) {
      throw const FormatException('Missing bill occurrence status section.');
    }
  }
}
