import 'dart:convert';

import 'package:flutter/foundation.dart';

typedef DataRow = Map<String, dynamic>;
typedef SaveData = Future<void> Function(String data);

const workshop = 'ورشة بني بوعياش';
const shop = 'محل الحسيمة';
const roles = ['المدير', 'نجاة', 'سلمى', 'حسن', 'لقمان'];
const families = [
  'العسل',
  'أملو',
  'الأعشاب',
  'الزيوت الغذائية',
  'الزيوت التجميلية',
  'التجميل',
  'مواد أولية',
  'التغليف',
];
const debtCategories = ['تأسيس قديم', 'موردون', 'زبناء'];

class RuleViolation implements Exception {
  RuleViolation(this.message);
  final String message;
  @override
  String toString() => message;
}

double number(DataRow row, String key) => (row[key] as num?)?.toDouble() ?? 0;
int cents(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite || value < 0) {
    throw RuleViolation('دخل مبلغ صحيح وموجب');
  }
  return (value * 100).round();
}

double quantity(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite || value <= 0) {
    throw RuleViolation('الكمية خاصها تكون أكبر من صفر');
  }
  return value;
}

String money(num value) => '${(value / 100).toStringAsFixed(2)} د.م.';
String today() => DateTime.now().toIso8601String().substring(0, 10);

class Manager extends ChangeNotifier {
  Manager({required this.save, String? initial}) {
    if (initial != null) data = decode(initial);
  }
  final SaveData save;
  String actor = 'المدير';
  bool busy = false;
  DataRow data = {
    'version': 1,
    'sequence': 0,
    for (final key in tables) key: <DataRow>[],
  };
  static const tables = [
    'products',
    'lots',
    'movements',
    'purchases',
    'production',
    'sales',
    'debts',
    'payments',
    'ledger',
    'suppliers',
    'exhibitions',
    'campaigns',
    'recipes',
    'audit',
    'commands',
    'payroll',
    'closings',
  ];
  static DataRow decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['sequence'] is! int ||
        decoded['sequence'] < 0) {
      throw RuleViolation('صيغة النسخة الاحتياطية غير صالحة');
    }
    for (final table in tables) {
      if (decoded[table] is! List ||
          (decoded[table] as List).any((e) => e is! Map<String, dynamic>)) {
        throw RuleViolation('بيانات ناقصة أو غير صالحة: $table');
      }
    }
    validateSnapshot(decoded);
    return decoded;
  }

  static void validateSnapshot(DataRow snapshot) {
    const strings = {
      'products': ['name', 'family', 'size', 'unit', 'flow'],
      'lots': ['product', 'location', 'batch', 'expiry', 'created'],
      'movements': ['lot', 'kind', 'description', 'actor', 'date'],
      'purchases': [
        'product',
        'supplier',
        'invoice',
        'ordered',
        'received',
        'due',
        'lot',
        'confirmedBy',
      ],
      'production': ['lot', 'workers', 'activity', 'date'],
      'sales': [
        'lot',
        'product',
        'customer',
        'channel',
        'discovery',
        'campaign',
        'exhibition',
        'due',
        'status',
        'date',
      ],
      'debts': ['category', 'party', 'due', 'reason', 'source', 'created'],
      'payments': ['debt', 'account', 'date', 'actor'],
      'ledger': ['account', 'kind', 'reference', 'description', 'date'],
      'suppliers': ['name', 'contact', 'terms'],
      'exhibitions': ['name', 'city', 'start', 'end'],
      'campaigns': ['name', 'source', 'start', 'end'],
      'recipes': ['name', 'product', 'description', 'date'],
      'audit': ['actor', 'date', 'action', 'description'],
      'payroll': ['employee', 'month', 'account', 'date'],
      'closings': ['account', 'explanation', 'actor', 'date'],
    };
    const numbers = {
      'lots': ['quantity', 'costQuantity'],
      'movements': ['quantity'],
      'purchases': ['quantity', 'transport'],
      'production': ['quantity', 'hours', 'waste', 'overhead'],
      'sales': ['quantity', 'total', 'paid'],
      'debts': ['principal', 'paid'],
      'payments': ['amount'],
      'ledger': ['amount'],
      'payroll': ['amount'],
      'closings': ['actual', 'recorded', 'difference'],
    };
    const nullableMoney = {
      'lots': ['cost'],
      'purchases': ['cost', 'unitCost'],
      'production': ['cost', 'labor'],
      'sales': ['cost'],
    };
    final allIds = <String>{};
    final idsByTable = <String, Set<String>>{};
    void invalid() => throw RuleViolation('النسخة فيها قيم أو مراجع غير صالحة');
    for (final table in tables) {
      idsByTable[table] = <String>{};
      for (final row in (snapshot[table] as List).cast<DataRow>()) {
        final id = row['id'];
        if (id is! String || id.isEmpty || !idsByTable[table]!.add(id)) {
          invalid();
        }
        if (table != 'commands') {
          if (!allIds.add(id as String)) invalid();
          final seq = int.tryParse(id.substring(1));
          if (!id.startsWith('Z') ||
              seq == null ||
              seq > snapshot['sequence']) {
            invalid();
          }
        }
        for (final key in strings[table] ?? <String>[]) {
          if (row[key] is! String) invalid();
        }
        for (final key in numbers[table] ?? <String>[]) {
          final value = row[key];
          if (value is! num || !value.isFinite) invalid();
          if (!['movements', 'ledger', 'closings'].contains(table) &&
              value < 0) {
            invalid();
          }
          if (!['quantity', 'costQuantity', 'hours', 'waste'].contains(key) &&
              value is! int) {
            invalid();
          }
        }
        for (final key in nullableMoney[table] ?? <String>[]) {
          final value = row[key];
          if (value != null && (value is! int || value < 0)) invalid();
        }
        if (table == 'lots' && number(row, 'costQuantity') <= 0) invalid();
        if (table == 'debts') {
          if (!debtCategories.contains(row['category']) ||
              row['paid'] > row['principal'] ||
              row['installments'] is! List) {
            invalid();
          }
          for (final item in row['installments']) {
            if (item is! Map ||
                item['id'] is! String ||
                item['due'] is! String ||
                item['amount'] is! int ||
                item['paid'] is! int ||
                item['amount'] <= 0 ||
                item['paid'] < 0 ||
                item['paid'] > item['amount']) {
              invalid();
            }
          }
        }
        if (table == 'production' &&
            (row['inputs'] is! List || row['estimated'] is! bool)) {
          invalid();
        }
        if (table == 'sales' &&
            (number(row, 'quantity') <= 0 ||
                !['محجوز', 'مسلم', 'ملغى'].contains(row['status']) ||
                number(row, 'returned') > number(row, 'quantity'))) {
          invalid();
        }
      }
    }
    const references = {
      'lots': {'product': 'products'},
      'movements': {'lot': 'lots'},
      'purchases': {
        'product': 'products',
        'supplier': 'suppliers',
        'lot': 'lots',
      },
      'production': {'lot': 'lots'},
      'sales': {'lot': 'lots', 'product': 'products'},
      'payments': {'debt': 'debts'},
      'recipes': {'product': 'products'},
    };
    for (final table in references.entries) {
      for (final row in (snapshot[table.key] as List).cast<DataRow>()) {
        for (final ref in table.value.entries) {
          if (!idsByTable[ref.value]!.contains(row[ref.key])) invalid();
        }
      }
    }
  }

  List<DataRow> rows(String table) => (data[table] as List).cast<DataRow>();
  DataRow byId(String table, String id) => rows(table).firstWhere(
    (r) => r['id'] == id,
    orElse: () => throw RuleViolation('السجل غير موجود'),
  );
  String id() => 'Z${++data['sequence']}';
  String export() => const JsonEncoder.withIndent('  ').convert(data);
  bool allowed(String operation) {
    if (actor == 'المدير') return true;
    return switch (actor) {
      'نجاة' => [
        'product',
        'purchase',
        'production',
        'transfer',
        'stock',
        'recipe',
      ].contains(operation),
      'سلمى' => ['sale', 'receive', 'stock'].contains(operation),
      'حسن' => operation == 'campaign',
      _ => false,
    };
  }

  void permit(String operation) {
    if (!allowed(operation)) {
      throw RuleViolation('هاد العملية خاصها صلاحية أخرى');
    }
  }

  Future<void> commit(
    String operation,
    String description,
    void Function() action, {
    String? commandId,
  }) async {
    permit(operation);
    if (busy) throw RuleViolation('تسنى حتى تتسجل العملية السابقة');
    if (commandId != null &&
        rows('commands').any((r) => r['id'] == commandId)) {
      return;
    }
    busy = true;
    final before = jsonEncode(data);
    try {
      action();
      rows('audit').add({
        'id': id(),
        'actor': actor,
        'date': DateTime.now().toIso8601String(),
        'action': operation,
        'description': description,
      });
      if (commandId != null) rows('commands').add({'id': commandId});
      await save(jsonEncode(data));
    } catch (_) {
      data = decode(before);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> restore(String text) async {
    permit('restore');
    final replacement = decode(text);
    await commit('restore', 'استرجاع نسخة احتياطية', () {
      data = replacement;
    });
  }

  void positive(num amount) {
    if (!amount.isFinite || amount <= 0) {
      throw RuleViolation('القيمة خاصها تكون أكبر من صفر');
    }
  }

  void nonnegative(num amount) {
    if (!amount.isFinite || amount < 0) throw RuleViolation('المبلغ غير صالح');
  }

  void requiredText(String text) {
    if (text.trim().isEmpty) throw RuleViolation('كمّل الخانات المطلوبة');
  }

  bool validDate(String text) {
    final date = DateTime.tryParse(text);
    return date != null && date.toIso8601String().substring(0, 10) == text;
  }

  void date(String text) {
    if (!validDate(text)) throw RuleViolation('التاريخ خاصو يكون YYYY-MM-DD');
  }

  void movement(String lot, double amount, String kind, String description) {
    rows('movements').add({
      'id': id(),
      'lot': lot,
      'quantity': amount,
      'kind': kind,
      'description': description,
      'actor': actor,
      'date': DateTime.now().toIso8601String(),
    });
  }

  DataRow addLot(
    String product,
    double amount,
    String location,
    String batch,
    int? totalCost,
    String expiry,
    String kind, {
    bool estimated = false,
  }) {
    byId('products', product);
    positive(amount);
    requiredText(location);
    requiredText(batch);
    if (expiry.isNotEmpty) date(expiry);
    if (totalCost != null) nonnegative(totalCost);
    final lot = <String, dynamic>{
      'id': id(),
      'product': product,
      'quantity': amount,
      'location': location,
      'batch': batch,
      'cost': totalCost,
      'costQuantity': amount,
      'estimated': estimated,
      'expiry': expiry,
      'created': today(),
    };
    rows('lots').add(lot);
    movement(lot['id'], amount, kind, batch);
    return lot;
  }

  void available(DataRow lot, double amount) {
    positive(amount);
    if (number(lot, 'quantity') < amount) {
      throw RuleViolation('الكمية ما كافياش فهاد الموقع');
    }
    final expiry = lot['expiry'] as String;
    if (expiry.isNotEmpty && expiry.compareTo(today()) < 0) {
      throw RuleViolation('هاد الدفعة فات تاريخ الصلاحية ديالها');
    }
  }

  int? lotCost(DataRow lot, double amount) => lot['cost'] == null
      ? null
      : (number(lot, 'cost') * amount / number(lot, 'costQuantity')).round();
  void ledger(
    String account,
    int amount,
    String kind,
    String reference,
    String description,
  ) {
    rows('ledger').add({
      'id': id(),
      'account': account,
      'amount': amount,
      'kind': kind,
      'reference': reference,
      'description': description,
      'date': today(),
    });
  }

  int balance(String account) =>
      rows('ledger')
          .where((r) => r['account'] == account)
          .fold(0, (s, r) => s + (r['amount'] as int));
  void spend(
    String account,
    int amount,
    String kind,
    String reference,
    String description,
  ) {
    if (balance(account) < amount) {
      throw RuleViolation('الرصيد المسجل ما كافيش. سجل الرصيد الافتتاحي أولاً');
    }
    ledger(account, -amount, kind, reference, description);
  }

  Future<void> product(
    String name,
    String family,
    String size,
    String unit,
    String flow,
  ) => commit('product', 'تعريف صنف: $name', () {
    requiredText(name);
    requiredText(unit);
    if (rows('products')
        .any((r) => r['name'] == name.trim() && r['size'] == size.trim())) {
      throw RuleViolation('هاد الصنف مسجل من قبل');
    }
    rows('products').add({
      'id': id(),
      'name': name.trim(),
      'family': family,
      'size': size.trim(),
      'unit': unit,
      'flow': flow,
    });
  });
  Future<void> openingStock(
    String product,
    double amount,
    String location,
    String batch,
    int? cost,
    String expiry,
  ) => commit('stock', 'جرد افتتاحي: $batch', () {
    if (actor != 'المدير') throw RuleViolation('الجرد الافتتاحي خاصو المدير');
    addLot(product, amount, location, batch, cost, expiry, 'جرد افتتاحي');
  });
  Future<void> adjust(String lotId, double actual, String reason) =>
      commit('stock', 'تصحيح جرد: $reason', () {
        if (actor != 'المدير') {
          throw RuleViolation('تصحيح الجرد خاصو اعتماد المدير');
        }
        nonnegative(actual);
        requiredText(reason);
        final lot = byId('lots', lotId);
        movement(lotId, actual - number(lot, 'quantity'), 'تصحيح', reason);
        lot['quantity'] = actual;
      });
  Future<void> supplier(String name, String contact, String terms) => commit(
    'supplier',
    'مورد: $name',
    () {
      requiredText(name);
      rows('suppliers')
          .add({'id': id(), 'name': name, 'contact': contact, 'terms': terms});
    },
  );
  Future<void> purchase({
    required String productId,
    required double amount,
    required String supplierId,
    required String invoice,
    required String ordered,
    required String received,
    required String due,
    required int? unitCost,
    required int transport,
    required int paid,
    required String account,
    required String batch,
    required String expiry,
    String? commandId,
  }) => commit('purchase', 'استلام شراء: $invoice', () {
    positive(amount);
    requiredText(invoice);
    date(ordered);
    date(received);
    date(due);
    if (received.compareTo(ordered) < 0) {
      throw RuleViolation('الاستلام ما يقدرش يسبق الطلب');
    }
    byId('suppliers', supplierId);
    nonnegative(transport);
    nonnegative(paid);
    if (unitCost != null) nonnegative(unitCost);
    if (unitCost != null && actor != 'المدير') {
      throw RuleViolation('نجاة كتأكد الاستلام؛ اعتماد التكلفة خاصو المدير');
    }
    if (rows('purchases')
        .any((r) => r['supplier'] == supplierId && r['invoice'] == invoice)) {
      throw RuleViolation('هاد الفاتورة مسجلة من قبل');
    }
    final total = unitCost == null
        ? null
        : (unitCost * amount).round() + transport;
    if (total == null && (paid > 0 || transport > 0)) {
      throw RuleViolation('أكد الثمن قبل تسجيل المصاريف أو الأداء');
    }
    if (total != null && paid > total) {
      throw RuleViolation('الأداء أكبر من الفاتورة');
    }
    final purchaseId = id();
    final lot = addLot(
      productId,
      amount,
      workshop,
      batch,
      total,
      expiry,
      'شراء',
    );
    rows('purchases').add({
      'id': purchaseId,
      'product': productId,
      'quantity': amount,
      'supplier': supplierId,
      'invoice': invoice,
      'ordered': ordered,
      'received': received,
      'due': due,
      'cost': total,
      'unitCost': unitCost,
      'transport': transport,
      'lot': lot['id'],
      'confirmedBy': actor,
    });
    if (total != null) {
      if (paid > 0) {
        if (actor != 'المدير') throw RuleViolation('الأداء خاصو اعتماد المدير');
        spend(account, paid, 'شراء', purchaseId, invoice);
      }
      if (total > 0) {
        final debt = addDebt(
          'موردون',
          byId('suppliers', supplierId)['name'],
          total,
          due,
          invoice,
          purchaseId,
        );
        debt['paid'] = paid;
        if (paid > 0) {
          rows('payments').add({
            'id': id(),
            'debt': debt['id'],
            'amount': paid,
            'account': account,
            'date': received,
            'actor': actor,
          });
        }
      }
    }
  }, commandId: commandId);
  Future<void> confirmPurchaseCost(
    String purchaseId,
    int unitCost,
    int transport,
  ) => commit('finance', 'تأكيد تكلفة شراء', () {
    final purchase = byId('purchases', purchaseId);
    if (purchase['cost'] != null) {
      throw RuleViolation('التكلفة مؤكدة بالفعل؛ لا تغير التكلفة التاريخية');
    }
    nonnegative(unitCost);
    nonnegative(transport);
    final total = (unitCost * number(purchase, 'quantity')).round() + transport;
    final lot = byId('lots', purchase['lot']);
    // Downstream batches need explicit reconciliation if unknown-cost material was already used.
    if (number(lot, 'quantity') != number(lot, 'costQuantity')) {
      throw RuleViolation(
        'تحركت الدفعة؛ خاص مراجعة التكاليف المرتبطة قبل التأكيد',
      );
    }
    purchase.addAll({
      'cost': total,
      'unitCost': unitCost,
      'transport': transport,
    });
    lot['cost'] = total;
    if (total > 0) {
      addDebt(
        'موردون',
        byId('suppliers', purchase['supplier'])['name'],
        total,
        purchase['due'],
        purchase['invoice'],
        purchaseId,
      );
    }
  });
  DataRow addDebt(
    String category,
    String party,
    int principal,
    String due,
    String reason,
    String source,
  ) {
    positive(principal);
    requiredText(party);
    requiredText(reason);
    date(due);
    final debt = <String, dynamic>{
      'id': id(),
      'category': category,
      'party': party,
      'principal': principal,
      'paid': 0,
      'due': due,
      'reason': reason,
      'source': source,
      'created': today(),
      'installments': <DataRow>[],
    };
    rows('debts').add(debt);
    return debt;
  }

  Future<void> historicalDebt(
    String party,
    int principal,
    String due,
    String reason,
  ) => commit('finance', 'دين تأسيس: $party', () {
    addDebt('تأسيس قديم', party, principal, due, reason, id());
  });
  Future<void> schedule(String debtId, List<DataRow> installments) =>
      commit('finance', 'جدولة أقساط', () {
        final debt = byId('debts', debtId);
        if ((debt['installments'] as List).isNotEmpty) {
          throw RuleViolation('الجدولة مسجلة؛ تعديلها يحتاج مراجعة موثقة');
        }
        final remaining = (debt['principal'] as int) - (debt['paid'] as int);
        var total = 0;
        for (final item in installments) {
          positive(item['amount'] as int);
          date(item['due']);
          total += item['amount'] as int;
        }
        if (total != remaining) {
          throw RuleViolation('مجموع الأقساط خاصو يساوي الرصيد المتبقي');
        }
        debt['installments'] = [
          for (final item in installments) {'id': id(), ...item, 'paid': 0},
        ];
      });
  Future<void> payDebt(
    String debtId,
    int amount,
    String account, {
    String? commandId,
  }) => commit('finance', 'أداء / تحصيل دين', () {
    positive(amount);
    final debt = byId('debts', debtId);
    final remaining = (debt['principal'] as int) - (debt['paid'] as int);
    if (amount > remaining) {
      throw RuleViolation('المبلغ أكبر من الرصيد المتبقي');
    }
    final paymentId = id();
    if (debt['category'] == 'زبناء') {
      ledger(account, amount, 'تحصيل', debtId, debt['party']);
    } else {
      spend(account, amount, 'أداء دين', debtId, debt['party']);
    }
    debt['paid'] = (debt['paid'] as int) + amount;
    var unallocated = amount;
    final installments = (debt['installments'] as List).cast<DataRow>()
      ..sort((a, b) => (a['due'] as String).compareTo(b['due']));
    for (final installment in installments) {
      final left =
          (installment['amount'] as int) - (installment['paid'] as int);
      final allocated = unallocated < left ? unallocated : left;
      installment['paid'] = (installment['paid'] as int) + allocated;
      unallocated -= allocated;
    }
    rows('payments').add({
      'id': paymentId,
      'debt': debtId,
      'amount': amount,
      'account': account,
      'date': today(),
      'actor': actor,
    });
  }, commandId: commandId);
  Future<void> produce({
    required List<DataRow> inputs,
    required String productId,
    required double output,
    required String batch,
    required String expiry,
    required String workers,
    required double hours,
    required double waste,
    required int? labor,
    required int overhead,
    required String activity,
    required bool estimated,
  }) => commit('production', 'إنتاج: $batch', () {
    positive(output);
    positive(hours);
    nonnegative(waste);
    nonnegative(overhead);
    requiredText(workers);
    if (labor != null) nonnegative(labor);
    if (inputs.isEmpty) throw RuleViolation('سجل المواد المستعملة');
    final ids = <String>{};
    int? cost = labor == null ? null : labor + overhead;
    var isEstimated = estimated;
    for (final input in inputs) {
      final lotId = input['lot'] as String;
      if (!ids.add(lotId)) throw RuleViolation('الدفعة مكررة في المواد');
      final lot = byId('lots', lotId);
      isEstimated = isEstimated || lot['estimated'] == true;
      if (lot['location'] != workshop) {
        throw RuleViolation('الإنتاج كيستعمل مخزون الورشة');
      }
      final amount = number(input, 'quantity');
      available(lot, amount);
      final inputCost = lotCost(lot, amount);
      cost = cost == null || inputCost == null ? null : cost + inputCost;
    }
    for (final input in inputs) {
      final lot = byId('lots', input['lot']);
      lot['quantity'] = number(lot, 'quantity') - number(input, 'quantity');
      movement(lot['id'], -number(input, 'quantity'), 'مواد إنتاج', batch);
    }
    final lot = addLot(
      productId,
      output,
      workshop,
      batch,
      cost,
      expiry,
      'إنتاج',
      estimated: isEstimated,
    );
    rows('production').add({
      'id': id(),
      'lot': lot['id'],
      'inputs': inputs,
      'quantity': output,
      'workers': workers,
      'hours': hours,
      'waste': waste,
      'labor': labor,
      'overhead': overhead,
      'cost': cost,
      'estimated': isEstimated,
      'activity': activity,
      'date': today(),
    });
  });
  Future<void> transfer(String lotId, double amount, String destination) =>
      commit('transfer', 'صيفطت: $destination', () {
        final lot = byId('lots', lotId);
        available(lot, amount);
        requiredText(destination);
        if (destination == lot['location']) {
          throw RuleViolation('المصدر والوجهة متطابقين');
        }
        if (actor == 'نجاة' && lot['location'] != workshop) {
          throw RuleViolation('نجاة كتسير مخزون الورشة فقط');
        }
        final cost = lotCost(lot, amount);
        lot['quantity'] = number(lot, 'quantity') - amount;
        movement(lotId, -amount, 'إرسال', destination);
        final shipment = addLot(
          lot['product'],
          amount,
          'شحنة مفتوحة',
          lot['batch'],
          cost,
          lot['expiry'],
          'شحنة',
          estimated: lot['estimated'] == true,
        );
        shipment.addAll({
          'source': lot['location'],
          'destination': destination,
          'sourceLot': lotId,
          'shipment': true,
        });
      });
  Future<void> receive(
    String shipmentId,
    double amount, {
    bool returnToSource = false,
  }) => commit(
    returnToSource ? 'transfer' : 'receive',
    returnToSource ? 'إرجاع شحنة' : 'تسلمت السلعة',
    () {
      final shipment = byId('lots', shipmentId);
      if (shipment['shipment'] != true) {
        throw RuleViolation('السجل ماشي شحنة مفتوحة');
      }
      if (actor == 'سلمى' && shipment['destination'] != shop) {
        throw RuleViolation('سلمى كتأكد استلام المحل فقط');
      }
      available(shipment, amount);
      final cost = lotCost(shipment, amount);
      shipment['quantity'] = number(shipment, 'quantity') - amount;
      movement(
        shipmentId,
        -amount,
        returnToSource ? 'إرجاع' : 'استلام',
        shipment['destination'],
      );
      addLot(
        shipment['product'],
        amount,
        returnToSource ? shipment['source'] : shipment['destination'],
        shipment['batch'],
        cost,
        shipment['expiry'],
        returnToSource ? 'إرجاع شحنة' : 'استلام',
        estimated: shipment['estimated'] == true,
      );
    },
  );
  Future<void> sale({
    required String lotId,
    required double amount,
    required int unitPrice,
    required String customer,
    required String channel,
    required String discovery,
    required int paid,
    required String account,
    required String due,
    required bool approved,
    String campaign = '',
    String exhibition = '',
    bool reserve = false,
    String? commandId,
  }) => commit('sale', reserve ? 'حجز طلبية' : 'بيع: $customer', () {
    final lot = byId('lots', lotId);
    available(lot, amount);
    nonnegative(unitPrice);
    nonnegative(paid);
    if (actor == 'سلمى' && lot['location'] != shop) {
      throw RuleViolation('سلمى كتبيع من مخزون المحل فقط');
    }
    if (lot['shipment'] == true && actor != 'المدير') {
      throw RuleViolation('بيع الشحنة خاصو اعتماد المدير');
    }
    if (lot['location'] == 'طلبية محجوزة') {
      throw RuleViolation('هاد الكمية محجوزة لطلبية أخرى');
    }
    final total = (unitPrice * amount).round();
    if (paid > total) throw RuleViolation('التحصيل أكبر من ثمن البيع');
    if (reserve && paid != 0) {
      throw RuleViolation('الحجز بدون تحصيل؛ سجل التحصيل عند التسليم');
    }
    if (paid < total || reserve) {
      requiredText(customer);
      date(due);
    }
    if (campaign.isNotEmpty) byId('campaigns', campaign);
    if (exhibition.isNotEmpty) {
      final event = byId('exhibitions', exhibition);
      if (lot['location'] != event['name']) {
        throw RuleViolation('حدد مخزون نفس المعرض');
      }
    }
    final cost = lotCost(lot, amount);
    if (!reserve &&
        cost != null &&
        total < cost &&
        !(approved && actor == 'المدير')) {
      throw RuleViolation('الثمن أقل من التكلفة؛ خاص اعتماد المدير');
    }
    final saleId = id();
    lot['quantity'] = number(lot, 'quantity') - amount;
    movement(lotId, -amount, reserve ? 'حجز' : 'بيع', saleId);
    String? reservedLot;
    if (reserve) {
      reservedLot = addLot(
        lot['product'],
        amount,
        'طلبية محجوزة',
        lot['batch'],
        cost,
        lot['expiry'],
        'حجز',
        estimated: lot['estimated'] == true,
      )['id'];
    } else {
      if (paid > 0) ledger(account, paid, 'بيع', saleId, customer);
      if (total > paid) {
        final debt = addDebt(
          'زبناء',
          customer,
          total,
          due,
          'بيع $saleId',
          saleId,
        );
        debt['paid'] = paid;
        if (paid > 0) {
          rows('payments').add({
            'id': id(),
            'debt': debt['id'],
            'amount': paid,
            'account': account,
            'date': today(),
            'actor': actor,
          });
        }
      }
    }
    rows('sales').add({
      'id': saleId,
      'lot': lotId,
      'product': lot['product'],
      'quantity': amount,
      'total': total,
      'cost': cost,
      'estimated': lot['estimated'] == true,
      'customer': customer,
      'channel': channel,
      'discovery': discovery,
      'campaign': campaign,
      'exhibition': exhibition,
      'paid': paid,
      'due': due,
      'status': reserve ? 'محجوز' : 'مسلم',
      'reservedLot': reservedLot,
      'date': today(),
      'approvedBy': approved ? actor : null,
    });
  }, commandId: commandId);
  Future<void> deliver(
    String saleId,
    int paid,
    String account,
    bool approved,
  ) => commit('sale', 'تسليم طلبية', () {
    final sale = byId('sales', saleId);
    if (sale['status'] != 'محجوز') throw RuleViolation('الطلبية مسلمة بالفعل');
    final source = byId('lots', sale['lot']);
    if (actor == 'سلمى' && source['location'] != shop) {
      throw RuleViolation('طلبية خارج المحل');
    }
    nonnegative(paid);
    final total = sale['total'] as int;
    if (paid > total) throw RuleViolation('التحصيل أكبر من الثمن');
    if (sale['cost'] != null &&
        total < sale['cost'] &&
        !(approved && actor == 'المدير')) {
      throw RuleViolation('بيع أقل من التكلفة يحتاج المدير');
    }
    final lot = byId('lots', sale['reservedLot']);
    available(lot, number(sale, 'quantity'));
    lot['quantity'] = 0.0;
    movement(lot['id'], -number(sale, 'quantity'), 'تسليم', saleId);
    if (paid > 0) ledger(account, paid, 'بيع', saleId, sale['customer']);
    if (total > paid) {
      final debt = addDebt(
        'زبناء',
        sale['customer'],
        total,
        sale['due'],
        'بيع $saleId',
        saleId,
      );
      debt['paid'] = paid;
      if (paid > 0) {
        rows('payments').add({
          'id': id(),
          'debt': debt['id'],
          'amount': paid,
          'account': account,
          'date': today(),
          'actor': actor,
        });
      }
    }
    sale.addAll({
      'status': 'مسلم',
      'paid': paid,
      'approvedBy': approved ? actor : null,
    });
  });
  Future<void> cancelOrder(String saleId, String reason) =>
      commit('sale', 'إلغاء طلبية: $reason', () {
        requiredText(reason);
        final sale = byId('sales', saleId);
        if (sale['status'] != 'محجوز') throw RuleViolation('خاص طلبية محجوزة');
        final source = byId('lots', sale['lot']);
        if (actor == 'سلمى' && source['location'] != shop) {
          throw RuleViolation('طلبية خارج المحل');
        }
        final reserved = byId('lots', sale['reservedLot']);
        final amount = number(reserved, 'quantity');
        reserved['quantity'] = 0.0;
        source['quantity'] = number(source, 'quantity') + amount;
        movement(reserved['id'], -amount, 'إلغاء حجز', reason);
        movement(source['id'], amount, 'تحرير حجز', reason);
        sale['status'] = 'ملغى';
      });

  Future<void> returnSale(
    String saleId,
    double amount,
    String reason,
    String account,
  ) => commit('finance', 'مرتجع بيع: $reason', () {
    requiredText(reason);
    positive(amount);
    final sale = byId('sales', saleId);
    if (sale['status'] != 'مسلم') throw RuleViolation('المرتجع خاص ببيع مسلم');
    final already = number(sale, 'returned');
    if (amount + already > number(sale, 'quantity')) {
      throw RuleViolation('المرتجع أكبر من كمية البيع');
    }
    final cumulativeRefund =
        ((amount + already) * number(sale, 'total') / number(sale, 'quantity'))
            .round();
    var credit = cumulativeRefund - (sale['credited'] as int? ?? 0);
    for (final debt in rows('debts').where((d) => d['source'] == saleId)) {
      final remaining = (debt['principal'] as int) - (debt['paid'] as int);
      final reduction = credit < remaining ? credit : remaining;
      debt['principal'] = (debt['principal'] as int) - reduction;
      debt['installments'] = <DataRow>[];
      credit -= reduction;
    }
    if (credit > 0) spend(account, credit, 'رد تحصيل', saleId, reason);
    final source = byId('lots', sale['lot']);
    final cost = sale['cost'] == null
        ? null
        : (number(sale, 'cost') * amount / number(sale, 'quantity')).round();
    addLot(
      sale['product'],
      amount,
      source['source'] ?? source['location'],
      source['batch'],
      cost,
      source['expiry'],
      'مرتجع بيع',
      estimated: sale['estimated'] == true,
    );
    sale.addAll({'returned': already + amount, 'credited': cumulativeRefund});
  });
  Future<void> finance(
    String account,
    int amount,
    String kind,
    String reason, {
    String reference = '',
  }) => commit('finance', '$kind: $reason', () {
    positive(amount);
    requiredText(reason);
    if (kind == 'رصيد افتتاحي' &&
        rows('ledger')
            .any((r) => r['account'] == account && r['kind'] == kind)) {
      throw RuleViolation('الرصيد الافتتاحي مسجل لهذا الحساب');
    }
    if (kind == 'أجر') {
      throw RuleViolation('سجل الأجر من عملية الأجور مع الفترة لمنع التكرار');
    }
    final ref = reference.isEmpty ? id() : reference;
    if (['رصيد افتتاحي', 'تمويل'].contains(kind)) {
      ledger(account, amount, kind, ref, reason);
    } else {
      spend(account, amount, kind, ref, reason);
    }
  });

  Future<void> salary(
    String employee,
    String month,
    int amount,
    String account,
  ) => commit('finance', 'أجر $employee: $month', () {
    requiredText(employee);
    positive(amount);
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      throw RuleViolation('الفترة خاصها تكون YYYY-MM');
    }
    if (rows('payroll')
        .any((r) => r['employee'] == employee && r['month'] == month)) {
      throw RuleViolation('أجر هاد الشخص وهاد الشهر مسجل بالفعل');
    }
    final ref = id();
    spend(account, amount, 'أجر', ref, '$employee — $month');
    rows('payroll').add({
      'id': ref,
      'employee': employee,
      'month': month,
      'amount': amount,
      'account': account,
      'date': today(),
    });
  });

  Future<void> closeCash(String account, int actual, String explanation) =>
      commit('finance', 'مطابقة صندوق: $account', () {
        nonnegative(actual);
        requiredText(explanation);
        if (rows('closings')
            .any((r) => r['account'] == account && r['date'] == today())) {
          throw RuleViolation('المطابقة مسجلة اليوم لهذا الحساب');
        }
        rows('closings').add({
          'id': id(),
          'account': account,
          'actual': actual,
          'recorded': balance(account),
          'difference': actual - balance(account),
          'explanation': explanation,
          'actor': actor,
          'date': today(),
        });
      });

  Future<void> returnPurchase(
    String purchaseId,
    double amount,
    String reason,
    String account,
  ) => commit('finance', 'مرتجع مورد: $reason', () {
    requiredText(reason);
    positive(amount);
    final purchase = byId('purchases', purchaseId);
    if (purchase['cost'] == null) {
      throw RuleViolation('أكد التكلفة قبل تسوية مرتجع المورد');
    }
    final lot = byId('lots', purchase['lot']);
    available(lot, amount);
    final returned = number(purchase, 'returned');
    if (returned + amount > number(purchase, 'quantity')) {
      throw RuleViolation('المرتجع أكبر من الشراء');
    }
    final unitCost = purchase['unitCost'] as int;
    final cumulativeCredit = ((returned + amount) * unitCost).round();
    var credit = cumulativeCredit - (purchase['credited'] as int? ?? 0);
    for (final debt in rows('debts').where((d) => d['source'] == purchaseId)) {
      final remaining = (debt['principal'] as int) - (debt['paid'] as int);
      final reduction = credit < remaining ? credit : remaining;
      debt['principal'] = (debt['principal'] as int) - reduction;
      debt['installments'] = <DataRow>[];
      credit -= reduction;
    }
    // Only merchandise is credited; allocated transport is not assumed refundable.
    if (credit > 0) ledger(account, credit, 'رد مورد', purchaseId, reason);
    lot['quantity'] = number(lot, 'quantity') - amount;
    movement(lot['id'], -amount, 'مرتجع مورد', reason);
    purchase.addAll({
      'returned': returned + amount,
      'credited': cumulativeCredit,
    });
  });
  Future<void> accountTransfer(String from, String to, int amount) =>
      commit('finance', 'تحويل بين حسابات', () {
        positive(amount);
        if (from == to) throw RuleViolation('الحسابان متطابقان');
        final ref = id();
        spend(from, amount, 'تحويل حساب', ref, to);
        ledger(to, amount, 'تحويل حساب', ref, from);
      });
  Future<void> exhibition(String name, String city, String start, String end) =>
      commit('exhibition', 'معرض: $name', () {
        requiredText(name);
        requiredText(city);
        date(start);
        date(end);
        if (end.compareTo(start) < 0) throw RuleViolation('راجع تواريخ المعرض');
        if (rows('exhibitions').any((r) => r['name'] == name)) {
          throw RuleViolation('اسم المعرض مكرر');
        }
        rows('exhibitions').add({
          'id': id(),
          'name': name,
          'city': city,
          'start': start,
          'end': end,
        });
      });
  Future<void> campaign(String name, String source, String start, String end) =>
      commit('campaign', 'حملة: $name', () {
        requiredText(name);
        date(start);
        date(end);
        if (end.compareTo(start) < 0) throw RuleViolation('راجع تواريخ الحملة');
        rows('campaigns').add({
          'id': id(),
          'name': name,
          'source': source,
          'start': start,
          'end': end,
        });
      });
  Future<void> recipe(String name, String product, String description) =>
      commit('recipe', 'وصفة: $name', () {
        requiredText(name);
        requiredText(description);
        byId('products', product);
        rows('recipes').add({
          'id': id(),
          'name': name,
          'product': product,
          'description': description,
          'date': today(),
        });
      });
  int get revenue => rows('sales')
      .where((s) => s['status'] == 'مسلم')
      .fold(
        0,
        (sum, s) => sum + (s['total'] as int) - (s['credited'] as int? ?? 0),
      );
  int debtTotal(String category, String field) =>
      rows('debts')
          .where((d) => d['category'] == category)
          .fold(0, (sum, d) => sum + (d[field] as int));
  int remaining(String category) =>
      debtTotal(category, 'principal') - debtTotal(category, 'paid');
  int get liquidity =>
      rows('ledger').fold(0, (sum, r) => sum + (r['amount'] as int));
  List<DataRow> get upcoming {
    final result = <DataRow>[];
    for (final d in rows('debts')) {
      final parts = (d['installments'] as List).cast<DataRow>();
      if (parts.isEmpty && d['principal'] > d['paid']) {
        result.add({...d, 'amount': d['principal'], 'debt': d['id']});
      }
      for (final part in parts) {
        if (part['amount'] > part['paid']) {
          result.add({
            ...part,
            'party': d['party'],
            'category': d['category'],
            'debt': d['id'],
          });
        }
      }
    }
    result.sort((a, b) => (a['due'] as String).compareTo(b['due']));
    return result;
  }

  String get repaymentAdvice =>
      'خاص مراجعة المدير: مازال ما تحددوش المصاريف الضرورية، احتياطي السيولة، استهلاك المواد وآجال التوريد. ما كاين حتى اقتراح أداء تلقائي.';
}
