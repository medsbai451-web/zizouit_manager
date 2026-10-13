import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zizouit_manager/domain/manager.dart';

void main() {
  late Manager m;
  late String product;
  late String supplier;
  setUp(() async {
    m = Manager(save: (_) async {});
    await m.product('عسل', 'العسل', '250غ', 'قطعة', 'شراء جاهز');
    product = m.rows('products').single['id'];
    await m.supplier('المورد', '0600000000', 'حسب الفاتورة');
    supplier = m.rows('suppliers').single['id'];
  });
  Future<void> purchase({
    int? cost = 1000,
    int paid = 0,
    String invoice = 'INV1',
  }) => m.purchase(
    productId: product,
    amount: 10,
    supplierId: supplier,
    invoice: invoice,
    ordered: '2026-01-01',
    received: '2026-01-02',
    due: '2026-02-01',
    unitCost: cost,
    transport: cost == null ? 0 : 200,
    paid: paid,
    account: 'البنك',
    batch: invoice,
    expiry: '2030-01-01',
  );
  Future<void> sale({
    String? lot,
    int price = 2000,
    int paid = 0,
    bool reserve = false,
    String? command,
  }) => m.sale(
    lotId: lot ?? m.rows('lots').first['id'],
    amount: 2,
    unitPrice: price,
    customer: 'الزبون',
    channel: 'الجملة',
    discovery: 'فيسبوك',
    paid: paid,
    account: 'صندوق الورشة',
    due: '2026-12-01',
    approved: false,
    reserve: reserve,
    commandId: command,
  );

  test(
    'Deferred purchase adds stock and payable without spending cash',
    () async {
      await purchase();
      expect(m.rows('lots').single['quantity'], 10);
      expect(m.rows('lots').single['cost'], 10200);
      expect(m.remaining('موردون'), 10200);
      expect(m.liquidity, 0);
      expect(m.rows('ledger'), isEmpty);
    },
  );
  test(
    'Partial supplier payments update installments, not purchase cost',
    () async {
      await m.finance('البنك', 20000, 'رصيد افتتاحي', 'موثق');
      await purchase();
      final debt = m.rows('debts').single;
      await m.schedule(debt['id'], [
        {'due': '2026-02-01', 'amount': 5000},
        {'due': '2026-03-01', 'amount': 5200},
      ]);
      await m.payDebt(debt['id'], 6000, 'البنك');
      expect(m.balance('البنك'), 14000);
      expect(m.remaining('موردون'), 4200);
      expect(m.rows('lots').single['cost'], 10200);
      expect(m.rows('purchases').single['cost'], 10200);
      expect(debt['installments'][0]['paid'], 5000);
      expect(debt['installments'][1]['paid'], 1000);
    },
  );
  test('Transfer only adds shop stock after actual partial receipt', () async {
    await purchase();
    final lot = m.rows('lots').single;
    await m.transfer(lot['id'], 4, shop);
    final shipment = m.rows('lots').last;
    expect(lot['quantity'], 6);
    expect(m.rows('lots').where((l) => l['location'] == shop), isEmpty);
    m.actor = 'سلمى';
    await m.receive(shipment['id'], 3);
    expect(m.rows('lots').last['quantity'], 3);
    expect(m.rows('lots').last['location'], shop);
    expect(shipment['quantity'], 1);
    expect(m.rows('sales'), isEmpty);
    expect(m.liquidity, 0);
    m.actor = 'المدير';
    await m.receive(shipment['id'], 1, returnToSource: true);
    expect(m.rows('lots').last['location'], workshop);
  });
  test('Missing purchase and production costs stay unknown', () async {
    await purchase(cost: null);
    expect(m.rows('lots').single['cost'], isNull);
    expect(m.rows('debts'), isEmpty);
    final input = m.rows('lots').single;
    await m.produce(
      inputs: [
        {'lot': input['id'], 'quantity': 2.0},
      ],
      productId: product,
      output: 1,
      batch: 'PROD',
      expiry: '',
      workers: 'نجاة',
      hours: 2,
      waste: 0.2,
      labor: 0,
      overhead: 0,
      activity: 'تعبئة',
      estimated: false,
    );
    expect(m.rows('lots').last['cost'], isNull);
    expect(m.rows('lots').last['location'], workshop);
    expect(m.rows('production').single['cost'], isNull);
  });
  test(
    'Production consumes multiple materials and adds actual workshop output',
    () async {
      await purchase();
      await m.openingStock(product, 4, workshop, 'PACK', 400, '');
      final inputs = m.rows('lots').toList();
      await m.produce(
        inputs: [
          {'lot': inputs[0]['id'], 'quantity': 2.0},
          {'lot': inputs[1]['id'], 'quantity': 1.0},
        ],
        productId: product,
        output: 3,
        batch: 'PROD',
        expiry: '',
        workers: 'نجاة',
        hours: 2,
        waste: 0.5,
        labor: 500,
        overhead: 100,
        activity: 'تصنيع',
        estimated: true,
      );
      expect(m.rows('lots').last['cost'], 2740);
      expect(inputs[0]['quantity'], 8);
      expect(inputs[1]['quantity'], 3);
      expect(m.rows('lots').last['location'], workshop);
    },
  );
  test('Customer collection does not book another sale', () async {
    await purchase();
    await sale(paid: 1000);
    final debt = m.rows('debts').last;
    await m.payDebt(debt['id'], 2000, 'صندوق الورشة');
    expect(m.rows('sales'), hasLength(1));
    expect(m.revenue, 4000);
    expect(m.remaining('زبناء'), 1000);
    expect(m.balance('صندوق الورشة'), 3000);
    expect(m.rows('lots').first['quantity'], 8);
  });
  test(
    'Below-cost sales require manager approval, insufficient stock rolls back',
    () async {
      await purchase();
      final before = m.export();
      await expectLater(sale(price: 100), throwsA(isA<RuleViolation>()));
      expect(m.export(), before);
      await expectLater(
        m.transfer(m.rows('lots').first['id'], 11, shop),
        throwsA(isA<RuleViolation>()),
      );
      expect(m.export(), before);
    },
  );
  test(
    'Reservation reduces availability without revenue, delivery books once',
    () async {
      await purchase();
      await sale(reserve: true);
      final order = m.rows('sales').single;
      expect(m.revenue, 0);
      expect(m.rows('lots').first['quantity'], 8);
      expect(m.rows('lots').last['location'], 'طلبية محجوزة');
      await m.deliver(order['id'], 2000, 'صندوق الورشة', false);
      expect(m.revenue, 4000);
      expect(m.rows('lots').last['quantity'], 0);
      expect(m.remaining('زبناء'), 2000);
      await expectLater(
        m.deliver(order['id'], 2000, 'صندوق الورشة', false),
        throwsA(isA<RuleViolation>()),
      );
      expect(m.revenue, 4000);
    },
  );
  test(
    'Returns reduce receivable before refunding cash and restore stock',
    () async {
      await purchase();
      await sale(paid: 1000);
      final saleId = m.rows('sales').single['id'];
      await m.returnSale(saleId, 1, 'مرتجع', 'صندوق الورشة');
      expect(m.remaining('زبناء'), 1000);
      expect(m.balance('صندوق الورشة'), 1000);
      expect(m.revenue, 2000);
      await m.returnSale(saleId, 1, 'باقي', 'صندوق الورشة');
      expect(m.remaining('زبناء'), 0);
      expect(m.balance('صندوق الورشة'), 0);
      expect(m.revenue, 0);
      expect(
        m
            .rows('lots')
            .where((l) => l['location'] == workshop)
            .fold<double>(0, (sum, l) => sum + number(l, 'quantity')),
        10,
      );
    },
  );
  test('Supplier return credits merchandise, not transport', () async {
    await purchase();
    await m.returnPurchase(
      m.rows('purchases').single['id'],
      2,
      'موثق',
      'البنك',
    );
    expect(m.remaining('موردون'), 8200);
    expect(m.rows('lots').first['quantity'], 8);
    expect(m.liquidity, 0);
  });
  test('Repeated command and duplicate invoices cannot double post', () async {
    await purchase();
    await sale(command: 'request-1');
    await sale(command: 'request-1');
    expect(m.rows('sales'), hasLength(1));
    await expectLater(purchase(), throwsA(isA<RuleViolation>()));
    expect(m.rows('purchases'), hasLength(1));
  });
  test(
    'Invalid installment totals and excessive payments are rejected',
    () async {
      await purchase();
      final debt = m.rows('debts').single;
      await expectLater(
        m.schedule(debt['id'], [
          {'due': '2026-12-01', 'amount': 1},
        ]),
        throwsA(isA<RuleViolation>()),
      );
      await expectLater(
        m.payDebt(debt['id'], 20000, 'البنك'),
        throwsA(isA<RuleViolation>()),
      );
      expect(m.remaining('موردون'), 10200);
    },
  );
  test('Role boundaries reject finance and cross-location sales', () async {
    await purchase();
    m.actor = 'سلمى';
    await expectLater(sale(), throwsA(isA<RuleViolation>()));
    await expectLater(
      m.finance('البنك', 10000, 'تمويل', 'تمويل'),
      throwsA(isA<RuleViolation>()),
    );
    m.actor = 'حسن';
    await expectLater(
      m.transfer(m.rows('lots').first['id'], 1, shop),
      throwsA(isA<RuleViolation>()),
    );
    expect(m.rows('lots').first['quantity'], 10);
  });
  test(
    'Duplicate monthly salaries are prevented; withdrawals are separate',
    () async {
      await m.finance('البنك', 300000, 'رصيد افتتاحي', 'موثق');
      await m.salary('حسن', '2026-10', 100000, 'البنك');
      await expectLater(
        m.salary('حسن', '2026-10', 100000, 'البنك'),
        throwsA(isA<RuleViolation>()),
      );
      await m.finance('البنك', 10000, 'سحب شخصي', 'للمراجعة');
      expect(m.balance('البنك'), 190000);
      expect(m.revenue, 0);
    },
  );
  test(
    'Cash reconciliation records variance without inventing adjustment',
    () async {
      await m.finance('البنك', 10000, 'رصيد افتتاحي', 'موثق');
      await m.closeCash('البنك', 9500, 'للمراجعة');
      expect(m.rows('closings').single['difference'], -500);
      expect(m.balance('البنك'), 10000);
    },
  );
  test('Failed persistence rolls back stock and financial changes', () async {
    await purchase();
    final failing = Manager(
      save: (_) async => throw Exception('disk full'),
      initial: m.export(),
    );
    final before = failing.export();
    await expectLater(
      failing.transfer(failing.rows('lots').first['id'], 1, shop),
      throwsException,
    );
    expect(failing.export(), before);
    expect(failing.busy, false);
  });
  test(
    'Initial payments preserve original debt principal and repayment ratios',
    () async {
      await m.finance('البنك', 20000, 'رصيد افتتاحي', 'موثق');
      await purchase(paid: 2000);
      expect(m.debtTotal('موردون', 'principal'), 10200);
      expect(m.debtTotal('موردون', 'paid'), 2000);
      expect(m.remaining('موردون'), 8200);
      await sale(paid: 1000);
      expect(m.debtTotal('زبناء', 'principal'), 4000);
      expect(m.debtTotal('زبناء', 'paid'), 1000);
    },
  );
  test(
    'Cancelled reservation restores source without recording sale or money',
    () async {
      await purchase();
      await sale(reserve: true);
      await m.cancelOrder(m.rows('sales').single['id'], 'إلغاء الزبون');
      expect(m.rows('lots').first['quantity'], 10);
      expect(m.rows('lots').last['quantity'], 0);
      expect(m.revenue, 0);
      expect(m.liquidity, 0);
    },
  );
  test('Najat confirms receipt but cannot approve purchase costs', () async {
    m.actor = 'نجاة';
    await expectLater(purchase(), throwsA(isA<RuleViolation>()));
    await purchase(cost: null);
    expect(m.rows('purchases').single['confirmedBy'], 'نجاة');
    m.actor = 'المدير';
    await m.confirmPurchaseCost(m.rows('purchases').single['id'], 1000, 200);
    expect(m.remaining('موردون'), 10200);
  });
  test(
    'Invalid backup references and negative stock leave live data intact',
    () async {
      await purchase();
      final before = m.export();
      final corrupted = jsonDecode(before) as Map<String, dynamic>;
      corrupted['lots'][0]['product'] = 'missing';
      await expectLater(
        m.restore(jsonEncode(corrupted)),
        throwsA(isA<RuleViolation>()),
      );
      expect(m.export(), before);
      corrupted['lots'][0]['product'] = product;
      corrupted['lots'][0]['quantity'] = -1;
      await expectLater(
        m.restore(jsonEncode(corrupted)),
        throwsA(isA<RuleViolation>()),
      );
      expect(m.export(), before);
    },
  );
  test('Backup round trip and invalid formats', () async {
    await purchase();
    final restored = Manager(save: (_) async {}, initial: m.export());
    expect(restored.export(), m.export());
    await expectLater(
      m.restore(jsonEncode({'version': 99})),
      throwsA(isA<RuleViolation>()),
    );
    expect(m.rows('purchases'), hasLength(1));
  });
  test('Invalid dates and non-finite input are rejected', () async {
    await expectLater(
      m.historicalDebt('طرف', 100, '2026-02-31', 'سبب'),
      throwsA(isA<RuleViolation>()),
    );
    expect(() => quantity('NaN'), throwsA(isA<RuleViolation>()));
    expect(() => cents('Infinity'), throwsA(isA<RuleViolation>()));
    expect(cents('12,50'), 1250);
  });
}
