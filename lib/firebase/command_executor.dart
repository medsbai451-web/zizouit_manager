import 'dart:convert';
import '../domain/manager.dart';

Future<void> replayCommand(Manager m, DataRow command) async {
  final a = command['arguments'];
  if (a is! Map<String, dynamic>) {
    throw RuleViolation('معطيات العملية غير صالحة');
  }
  double n(String key) {
    final value = a[key];
    if (value is! num || !value.isFinite) {
      throw RuleViolation('قيمة غير صالحة: $key');
    }
    return value.toDouble();
  }

  String s(String key) {
    final value = a[key];
    if (value is! String) throw RuleViolation('خانة غير صالحة: $key');
    return value;
  }

  int i(String key) {
    final value = a[key];
    if (value is! int) throw RuleViolation('مبلغ غير صالح: $key');
    return value;
  }

  bool b(String key) => a[key] == true;
  List<DataRow> list(String key) => (a[key] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  switch (command['kind']) {
    case 'product':
      await m.product(s('name'), s('family'), s('size'), s('unit'), s('flow'));
    case 'purchase':
      await m.purchase(
        productId: s('productId'),
        amount: n('amount'),
        supplierId: s('supplierId'),
        invoice: s('invoice'),
        ordered: s('ordered'),
        received: s('received'),
        due: s('due'),
        unitCost: a['unitCost'] as int?,
        transport: i('transport'),
        paid: i('paid'),
        account: s('account'),
        batch: s('batch'),
        expiry: s('expiry'),
      );
    case 'produce':
      await m.produce(
        inputs: list('inputs'),
        productId: s('productId'),
        output: n('output'),
        batch: s('batch'),
        expiry: s('expiry'),
        workers: s('workers'),
        hours: n('hours'),
        waste: n('waste'),
        labor: a['labor'] as int?,
        overhead: i('overhead'),
        activity: s('activity'),
        estimated: b('estimated'),
      );
    case 'produceFromRecipe':
      if (jsonEncode(m.byId('recipes', s('recipeId'))) !=
          jsonEncode(a['recipe'])) {
        throw RuleViolation('الوصفة تبدلات؛ راجع المقادير وعاود العملية');
      }
      await m.produceFromRecipe(
        recipeId: s('recipeId'),
        output: n('output'),
        batch: s('batch'),
        expiry: s('expiry'),
        workers: s('workers'),
        hours: n('hours'),
        labor: a['labor'] as int?,
        overhead: i('overhead'),
      );
    case 'transfer':
      await m.transfer(s('lotId'), n('amount'), s('destination'));
    case 'receive':
      await m.receive(
        s('shipmentId'),
        n('amount'),
        returnToSource: b('returnToSource'),
      );
    case 'sale':
      await m.sale(
        lotId: s('lotId'),
        amount: n('amount'),
        unitPrice: i('unitPrice'),
        customer: s('customer'),
        channel: s('channel'),
        discovery: s('discovery'),
        paid: i('paid'),
        account: s('account'),
        due: s('due'),
        approved: b('approved'),
        campaign: s('campaign'),
        exhibition: s('exhibition'),
        reserve: b('reserve'),
      );
    case 'deliver':
      await m.deliver(s('saleId'), i('paid'), s('account'), b('approved'));
    case 'cancelOrder':
      await m.cancelOrder(s('saleId'), s('reason'));
    case 'campaign':
      await m.campaign(s('name'), s('source'), s('start'), s('end'));
    case 'recipe':
      await m.recipe(
        s('name'),
        s('product'),
        s('description'),
        outputQuantity: n('outputQuantity'),
        ingredients: list('ingredients'),
      );
    default:
      throw RuleViolation('نوع العملية غير مسموح');
  }
}
