import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zizouit_manager/domain/manager.dart';
import 'package:zizouit_manager/main.dart';

void main() {
  testWidgets(
    'Production recipe button converts actual bulk and packaging through the form',
    (tester) async {
      tester.view.physicalSize = const Size(1300, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(const Size(1300, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final seed = Manager(save: (_) async {});
      await seed.product('عسل سائب', 'العسل', 'سائب', 'كلغ', 'شراء جاهز');
      final bulk = seed.rows('products').last['id'];
      await seed.product('قرعة', 'التغليف', '250غ', 'قطعة', 'شراء جاهز');
      final jar = seed.rows('products').last['id'];
      await seed.product('عسل للبيع', 'العسل', '250غ', 'قطعة', 'تعبئة');
      final output = seed.rows('products').last['id'];
      await seed.openingStock(bulk, 3, workshop, 'BULK', 3000, '2030-01-01');
      await seed.openingStock(jar, 10, workshop, 'PACK', 1000, '');
      await seed.recipe(
        'قرعات عسل',
        output,
        'تعبئة',
        ingredients: [
          {'product': bulk, 'quantity': 0.25},
          {'product': jar, 'quantity': 1},
        ],
      );
      final manager = Manager(
        save: (_) async {},
        initial: seed.export(),
        authenticatedRole: 'نجاة',
      );
      await tester.pumpWidget(MyApp(manager: manager));
      await tester.pumpAndSettle();
      expect(find.text('المالية'), findsNothing);
      expect(find.text('الديون'), findsNothing);
      expect(find.byType(DropdownButton<String>), findsNothing);
      await tester.tap(find.text('الإنتاج'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('عبأت بالوصفة'));
      await tester.pumpAndSettle();
      for (final entry in {
        'الكمية': '4',
        'رقم الدفعة LOT': 'FINISHED',
        'العاملات المشاركات': 'نجاة',
        'الساعات الفعلية': '1',
        'تكلفة العمل المخصصة (د.م.)': '0',
      }.entries) {
        final finder = find.widgetWithText(TextFormField, entry.key);
        await tester.ensureVisible(finder);
        await tester.enterText(finder, entry.value);
      }
      await tester.tap(find.text('تأكيد وتسجيل'));
      await tester.pumpAndSettle();
      expect(manager.rows('lots').last['product'], output);
      expect(manager.rows('lots').last['quantity'], 4);
      expect(manager.rows('lots').first['quantity'], 2);
      expect(manager.rows('lots')[1]['quantity'], 6);
      expect(tester.takeException(), isNull);
    },
  );
}
