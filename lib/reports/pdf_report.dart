import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../l10n/app_language.dart';

Future<void> printReport(
  String title,
  String text, {
  AppLanguage language = AppLanguage.darija,
}) async {
  final bytes = await buildReport(title, text, language: language);
  if (kIsWeb) {
    await Printing.sharePdf(bytes: bytes, filename: 'ZIZOUIT-report.pdf');
  } else {
    await Printing.layoutPdf(
      name: 'ZIZOUIT-report.pdf',
      onLayout: (_) async => bytes,
    );
  }
}

Future<Uint8List> buildReport(
  String title,
  String text, {
  AppLanguage language = AppLanguage.darija,
}) async {
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoNaskhArabic.ttf'),
  );
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      textDirection: language.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (_) => [
        pw.Text(
          translate(title, language),
          style: const pw.TextStyle(fontSize: 20),
        ),
        pw.SizedBox(height: 20),
        for (final line in translate(text, language).split('\n'))
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              line,
              textAlign: language.rtl ? pw.TextAlign.right : pw.TextAlign.left,
            ),
          ),
      ],
    ),
  );
  return document.save();
}
