import 'package:flutter_test/flutter_test.dart';
import 'package:zizouit_manager/domain/manager.dart';
import 'package:zizouit_manager/firebase/public_snapshot.dart';

void main() {
  test(
    'Staff snapshots omit debts, money, salaries, purchase costs and financial audit',
    () async {
      final m = Manager(save: (_) async {});
      await m.product('عسل', 'العسل', '250غ', 'قطعة', 'شراء جاهز');
      final product = m.rows('products').single['id'];
      await m.supplier('مورد', 'الهاتف', 'الأجل');
      await m.finance('البنك', 200000, 'رصيد افتتاحي', 'PRIVATE_FINANCE');
      await m.salary('حسن', '2026-10', 100000, 'البنك');
      await m.historicalDebt(
        'PRIVATE_DEBT',
        10000,
        '2030-01-01',
        'PRIVATE_HISTORY',
      );
      await m.purchase(
        productId: product,
        amount: 10,
        supplierId: m.rows('suppliers').single['id'],
        invoice: 'INV',
        ordered: '2026-01-01',
        received: '2026-01-02',
        due: '2030-01-01',
        unitCost: 1000,
        transport: 100,
        paid: 0,
        account: 'البنك',
        batch: 'LOT',
        expiry: '',
      );
      await m.sale(
        lotId: m.rows('lots').single['id'],
        amount: 1,
        unitPrice: 2000,
        customer: 'زبون',
        channel: 'المحل',
        discovery: 'زيارة',
        paid: 1000,
        account: 'صندوق المحل',
        due: '2030-01-01',
        approved: false,
      );
      final original = m.export();
      final json = publicSnapshot(original);
      final public = Manager.decode(json);
      for (final key in [
        'debts',
        'payments',
        'ledger',
        'payroll',
        'closings',
        'audit',
      ]) {
        expect(public[key], isEmpty);
      }
      expect(public['lots'][0]['cost'], isNull);
      expect(public['purchases'][0]['unitCost'], isNull);
      expect(public['purchases'][0]['transport'], 0);
      expect(public['sales'][0]['paid'], 0);
      expect(json, isNot(contains('PRIVATE_')));
      expect(m.export(), original);
    },
  );
}
