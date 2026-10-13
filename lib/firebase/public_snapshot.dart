import 'dart:convert';

import '../domain/manager.dart';

// The private canonical document is never fetched by staff devices.
String publicSnapshot(String canonical) {
  final data = Manager.decode(canonical);
  for (final table in [
    'debts',
    'payments',
    'ledger',
    'payroll',
    'closings',
    'audit',
    'commands',
  ]) {
    data[table] = <DataRow>[];
  }
  for (final table in ['lots', 'purchases', 'production', 'sales']) {
    for (final row in (data[table] as List).cast<DataRow>()) {
      row['cost'] = null;
      if (table == 'purchases') {
        row['unitCost'] = null;
        row['transport'] = 0;
        row.remove('credited');
      }
      if (table == 'production') {
        row['labor'] = null;
        row['overhead'] = 0;
      }
      if (table == 'sales') {
        row['paid'] = 0;
        row.remove('credited');
      }
    }
  }
  return jsonEncode(data);
}
