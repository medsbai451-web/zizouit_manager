import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zizouit_manager/domain/manager.dart';
import 'package:zizouit_manager/l10n/app_language.dart';
import 'package:zizouit_manager/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Messages and nested report values translate in both added languages', () {
    const message =
        'مرحبا المدير. الدور مرتبط بالحساب. البيانات المالية والديون غير متاحة إلا للمدير.';
    expect(translate(message, AppLanguage.darija), message);
    expect(
      translate(message, AppLanguage.arabic),
      startsWith('مرحبًا المدير.'),
    );
    expect(
      translate(message, AppLanguage.french),
      startsWith('Bienvenue Administrateur.'),
    );
    expect(
      translate(
        'زبناء: أصل 200.00 د.م.، مؤدى 50.00 د.م.، باقي 150.00 د.م.',
        AppLanguage.french,
      ),
      'Clients : initial 200.00 MAD, payé 50.00 MAD, solde 150.00 MAD',
    );
    expect(
      translate('مخزون عسل سائب ناقص بـ 0.25 كلغ', AppLanguage.french),
      'Stock de عسل سائب insuffisant de 0.25 kg',
    );
    expect(
      translate('كمية ABC 250 · قطعة لكل دفعة وصفة', AppLanguage.french),
      'Quantité de ABC 250 · pièce par recette',
    );
    expect(
      translate('اسم خاص — Élixir du Rif', AppLanguage.french),
      'اسم خاص — Élixir du Rif',
    );
  });

  test(
    'Language preference is saved and restored independently of business data',
    () async {
      final controller = LanguageController();
      controller.select(AppLanguage.french);
      controller.select(AppLanguage.arabic);
      await controller.saved;
      final restored = LanguageController();
      await restored.load();
      expect(restored.value, AppLanguage.arabic);
      controller.dispose();
      restored.dispose();
    },
  );

  testWidgets(
    'French forms preserve canonical units and Standard Arabic changes direction',
    (tester) async {
      tester.view.physicalSize = const Size(1300, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(const Size(1300, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final manager = Manager(save: (_) async {});
      await tester.pumpWidget(MyApp(manager: manager));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-picker')));
      await tester.pumpAndSettle();
      expect(find.text('الدارجة'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<AppLanguage>, 'Français'),
      );
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.text('Tableau de bord').first)),
        TextDirection.ltr,
      );
      await tester.tap(find.text('Produits'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajouter un produit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmer et enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Veuillez remplir ce champ'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom du produit'),
        'Miel du Rif',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Format ou variante'),
        '250 g',
      );
      await tester.tap(find.text('Confirmer et enregistrer'));
      await tester.pumpAndSettle();
      expect(manager.rows('products').single['unit'], 'قطعة');
      expect(manager.rows('products').single['name'], 'Miel du Rif');
      expect(find.text('Miel du Rif 250 g · pièce'), findsOneWidget);
      final backup = manager.export();
      await tester.tap(find.byKey(const ValueKey('language-picker')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<AppLanguage>,
          'العربية الفصحى',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('إضافة صنف'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('إضافة صنف'))),
        TextDirection.rtl,
      );
      expect(manager.export(), backup);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in AppLanguage.values) {
    testWidgets(
      'Phone layout and authenticated permissions in ${language.code}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          LanguageController.preferenceKey: language.code,
        });
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MyApp(
            manager: Manager(save: (_) async {}, authenticatedRole: 'نجاة'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        expect(find.text(translate('المالية', language)), findsNothing);
        expect(find.text(translate('الديون', language)), findsNothing);
        await tester.tap(find.text(translate('الإنتاج', language)));
        await tester.pumpAndSettle();
        expect(find.text(translate('الإنتاج', language)), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
