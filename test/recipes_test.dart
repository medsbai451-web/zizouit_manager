import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zizouit_manager/domain/manager.dart';
import 'package:zizouit_manager/firebase/command_executor.dart';

void main() {
  late Manager manager;
  late String bulk;
  late String jar;
  late String output;
  late String recipe;
  setUp(() async {
    manager = Manager(save: (_) async {});
    await manager.product(
      'عسل سائب',
      'العسل',
      'وعاء التخزين',
      'كلغ',
      'شراء جاهز',
    );
    bulk = manager.rows('products').last['id'];
    await manager.product('قرعة وغطاء', 'التغليف', '250غ', 'قطعة', 'شراء جاهز');
    jar = manager.rows('products').last['id'];
    await manager.product('عسل للبيع', 'العسل', '250غ', 'قطعة', 'تعبئة');
    output = manager.rows('products').last['id'];
    await manager.openingStock(bulk, 1, workshop, 'B1', 1000, '2030-01-01');
    await manager.openingStock(bulk, 2, workshop, 'B2', 2000, '2029-01-01');
    await manager.openingStock(jar, 12, workshop, 'JAR', 1200, '');
    await manager.recipe(
      'عسل 250غ',
      output,
      'تعبئة',
      ingredients: [
        {'product': bulk, 'quantity': 0.25},
        {'product': jar, 'quantity': 1.0},
      ],
    );
    recipe = manager.rows('recipes').last['id'];
  });
  Future<void> convert(double count, {String expiry = ''}) =>
      manager.produceFromRecipe(
        recipeId: recipe,
        output: count,
        batch: 'FINISHED',
        expiry: expiry,
        workers: 'نجاة',
        hours: 1,
        labor: 0,
        overhead: 0,
      );
  test(
    'Scales bulk and packaging, uses nearest expiry, and creates selling stock',
    () async {
      await convert(4);
      final lots = manager.rows('lots');
      expect(lots[0]['quantity'], 1);
      expect(lots[1]['quantity'], 1);
      expect(lots[2]['quantity'], 8);
      expect(lots.last['product'], output);
      expect(lots.last['quantity'], 4);
      expect(lots.last['location'], workshop);
      expect(lots.last['cost'], 1400);
      expect(lots.last['expiry'], '2029-01-01');
      expect(manager.rows('production').single['recipe']['id'], recipe);
    },
  );
  test(
    'Consumes multiple bulk lots without assuming a different product unit',
    () async {
      await convert(10);
      expect(manager.rows('lots')[1]['quantity'], 0);
      expect(manager.rows('lots')[0]['quantity'], 0.5);
      expect(manager.rows('lots')[2]['quantity'], 2);
      expect(manager.rows('lots').last['quantity'], 10);
    },
  );
  test('Insufficient packaging rolls back every lot and record', () async {
    await manager.adjust(manager.rows('lots')[2]['id'], 2, 'جرد');
    final before = manager.export();
    await expectLater(convert(4), throwsA(isA<RuleViolation>()));
    expect(manager.export(), before);
  });
  test(
    'Expired bulk is excluded and output expiry cannot exceed ingredients',
    () async {
      await manager.openingStock(
        bulk,
        100,
        workshop,
        'EXPIRED',
        100,
        '2000-01-01',
      );
      await expectLater(
        convert(4, expiry: '2031-01-01'),
        throwsA(isA<RuleViolation>()),
      );
      await convert(4);
      expect(
        manager
            .rows('lots')
            .firstWhere((l) => l['batch'] == 'EXPIRED')['quantity'],
        100,
      );
    },
  );
  test(
    'Recipe quantities are frozen on production and unknown costs remain unknown',
    () async {
      await convert(4);
      final record = manager.rows('production').last;
      manager.byId('recipes', recipe)['description'] = 'ملاحظة جديدة';
      expect(record['recipe']['description'], 'تعبئة');
      final unknown = Manager(save: (_) async {}, initial: manager.export());
      unknown.rows('lots')[1]['cost'] = null;
      await unknown.produceFromRecipe(
        recipeId: recipe,
        output: 1,
        batch: 'UNKNOWN',
        expiry: '',
        workers: 'نجاة',
        hours: 1,
        labor: 0,
      );
      expect(unknown.rows('lots').last['cost'], isNull);
    },
  );
  test(
    'Legacy note recipes stay readable and cannot pretend to be a conversion',
    () async {
      await manager.recipe('وصفة نصية', output, 'المقادير غير محددة');
      final id = manager.rows('recipes').last['id'];
      expect(() => manager.recipeInputs(id, 2), throwsA(isA<RuleViolation>()));
    },
  );
  test(
    'Fractional selling containers and duplicated/self input products are rejected',
    () async {
      await expectLater(convert(1.5), throwsA(isA<RuleViolation>()));
      await expectLater(
        manager.recipe(
          'خطأ',
          output,
          'وصفة',
          ingredients: [
            {'product': output, 'quantity': 1},
          ],
        ),
        throwsA(isA<RuleViolation>()),
      );
      await expectLater(
        manager.recipe(
          'خطأ',
          output,
          'وصفة',
          ingredients: [
            {'product': bulk, 'quantity': 1},
            {'product': bulk, 'quantity': 2},
          ],
        ),
        throwsA(isA<RuleViolation>()),
      );
    },
  );
  test('Tampered ingredient references in a backup are rejected', () async {
    final invalid = jsonDecode(manager.export());
    invalid['recipes'][0]['ingredients'][0]['product'] = 'MISSING';
    await expectLater(
      manager.restore(jsonEncode(invalid)),
      throwsA(isA<RuleViolation>()),
    );
  });
  test(
    'Queued recipe conversion is replayed against authoritative stock',
    () async {
      final baseline = manager.export();
      await convert(4);
      final command = manager.currentCommand!;
      expect(command['kind'], 'produceFromRecipe');
      final authoritative = Manager(
        save: (_) async {},
        initial: baseline,
        authenticatedRole: 'نجاة',
      );
      await replayCommand(authoritative, command);
      expect(authoritative.rows('lots').last['quantity'], 4);
      expect(authoritative.rows('lots').last['cost'], 1400);
      expect(authoritative.rows('lots')[1]['quantity'], 1);
    },
  );
  test(
    'Queued conversion rejects a changed recipe instead of silently consuming other materials',
    () async {
      final baseline = manager.export();
      await convert(4);
      final command = manager.currentCommand!;
      final authoritative = Manager(
        save: (_) async {},
        initial: baseline,
        authenticatedRole: 'نجاة',
      );
      authoritative.byId('recipes', recipe)['ingredients'][0]['quantity'] = 0.5;
      final before = authoritative.export();
      await expectLater(
        replayCommand(authoritative, command),
        throwsA(isA<RuleViolation>()),
      );
      expect(authoritative.export(), before);
    },
  );
  test(
    'Queued commands cannot elevate a staff role or perform another role operation',
    () async {
      final staff = Manager(
        save: (_) async {},
        initial: manager.export(),
        authenticatedRole: 'سلمى',
      );
      expect(() => staff.actor = 'المدير', throwsA(isA<RuleViolation>()));
      await expectLater(
        replayCommand(staff, {
          'kind': 'produceFromRecipe',
          'arguments': {
            'recipeId': recipe,
            'recipe': jsonDecode(jsonEncode(manager.byId('recipes', recipe))),
            'output': 1,
            'batch': 'FORGED',
            'expiry': '',
            'workers': 'سلمى',
            'hours': 1,
            'labor': 0,
            'overhead': 0,
          },
        }),
        throwsA(isA<RuleViolation>()),
      );
      expect(staff.rows('production'), isEmpty);
    },
  );
}
