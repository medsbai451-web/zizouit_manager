import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zizouit_manager/reports/pdf_report.dart';
import 'package:zizouit_manager/l10n/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final language in [AppLanguage.arabic, AppLanguage.french]) {
    test(
      'PDF builds locally in ${language.code} with accented and Arabic names',
      () async {
        final bytes = await buildReport(
          'تقرير زيزويت ريف',
          'زبناء: أصل 200.00 د.م.، مؤدى 50.00 د.م.، باقي 150.00 د.م.\nÉlixir — عسل الريف',
          language: language,
        );
        expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      },
    );
  }
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
