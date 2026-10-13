import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zizouit_manager/main.dart';
import 'package:zizouit_manager/domain/manager.dart';

void main() {
  testWidgets('Arabic dashboard navigates and creates a product', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(1300, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manager = Manager(save: (_) async {});
    await tester.pumpWidget(MyApp(manager: manager));
    await tester.pumpAndSettle();
    expect(find.text('ZIZOUIT'), findsOneWidget);
    await tester.tap(find.text('الأصناف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('زيد صنف'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'اسم الصنف'),
      'عسل',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'الحجم أو المتغير'),
      '250 غرام',
    );
    await tester.tap(find.text('تأكيد وتسجيل'));
    await tester.pumpAndSettle();
    expect(manager.rows('products').single['name'], 'عسل');
    expect(find.text('عسل 250 غرام · قطعة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phone layout has working drawer and no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MyApp(manager: Manager(save: (_) async {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المخزون'));
    await tester.pumpAndSettle();
    expect(find.text('المخزون'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
