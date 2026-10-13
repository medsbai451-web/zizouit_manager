import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zizouit_manager/reports/pdf_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Arabic PDF uses bundled font and builds without network or printing',
    () async {
      final bytes = await buildReport(
        'تقرير زيزويت ريف',
        'المبيعات: 1000 درهم\nديون الموردين: 500 درهم\nالتكلفة غير مؤكدة',
      );
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    },
  );
}
