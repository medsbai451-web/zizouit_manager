import 'package:flutter/material.dart' hide DataRow;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseFirestore, Settings;

import 'domain/manager.dart';
import 'reports/pdf_report.dart';
import 'storage/storage.dart' as storage;
import 'firebase/firebase_config.dart';
import 'firebase/auth_gate.dart';
import 'firebase/firebase_session.dart';
import 'firebase/account_service.dart';
import 'l10n/app_language.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (FirebaseConfig.enabled) {
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      await AuthPersistence.firebase(FirebaseAuth.instance).initialize();
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      runApp(
        MyApp(
          homeOverride: AuthGate(
            builder: (manager, session) =>
                Home(manager: manager, session: session),
          ),
        ),
      );
    } catch (e) {
      runApp(MyApp(startupError: 'تعذر تشغيل Firebase: $e'));
    }
    return;
  }
  String? initial;
  String? error;
  try {
    initial = await storage.readData();
    if (initial != null) Manager.decode(initial);
  } catch (e) {
    error = 'تعذر فتح البيانات المحلية. النسخة الأصلية محفوظة: $e';
  }
  runApp(
    MyApp(
      manager: error == null
          ? Manager(save: storage.writeData, initial: initial)
          : null,
      startupError: error,
    ),
  );
}

const ink = Color(0xFF163E35);
const accent = Color(0xFFB38339);
const accounts = ['صندوق الورشة', 'صندوق المحل', 'البنك'];

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.manager, this.startupError, this.homeOverride});
  final Manager? manager;
  final String? startupError;
  final Widget? homeOverride;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final language = LanguageController();
  late final Manager fallbackManager = Manager(save: (_) async {});
  @override
  void initState() {
    super.initState();
    language.load();
  }

  @override
  void dispose() {
    language.dispose();
    fallbackManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LanguageScope(
    controller: language,
    child: ListenableBuilder(
      listenable: language,
      builder: (context, _) => MaterialApp(
        title: 'ZIZOUIT Manager',
        debugShowCheckedModeBanner: false,
        locale: language.value.locale,
        supportedLocales: const [
          Locale('ar', 'MA'),
          Locale('ar'),
          Locale('fr'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: language.value.rtl ? 'NotoNaskhArabic' : null,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: ink,
            primary: ink,
            secondary: accent,
          ),
          scaffoldBackgroundColor: const Color(0xFFF6F7F3),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF6F7F3),
            foregroundColor: ink,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          cardTheme: const CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.zero,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
        ),
        builder: (context, child) => Directionality(
          textDirection: language.value.rtl
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        ),
        home: widget.startupError != null
            ? Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LanguagePicker(),
                        AppSelectableText(widget.startupError!),
                      ],
                    ),
                  ),
                ),
              )
            : widget.homeOverride ??
                  Home(manager: widget.manager ?? fallbackManager),
      ),
    ),
  );
}

class FormFieldSpec {
  const FormFieldSpec(
    this.keyName,
    this.label, {
    this.options,
    this.initial = '',
    this.optional = false,
    this.lines = 1,
    this.numeric = false,
  });
  final String keyName;
  final String label;
  final Map<String, String>? options;
  final String initial;
  final bool optional;
  final int lines;
  final bool numeric;
}

class Home extends StatefulWidget {
  const Home({super.key, required this.manager, this.session});
  final Manager manager;
  final FirebaseSession? session;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Manager get m => widget.manager;
  String section = 'اليوم';
  String search = '';
  bool get admin => m.actor == 'المدير';
  FirebaseSession? get session => widget.session;
  final sections = <String, IconData>{
    'اليوم': Icons.space_dashboard_outlined,
    'الأصناف': Icons.category_outlined,
    'المخزون': Icons.inventory_2_outlined,
    'المشتريات': Icons.shopping_bag_outlined,
    'الإنتاج': Icons.spa_outlined,
    'المبيعات': Icons.storefront_outlined,
    'الموردون': Icons.local_shipping_outlined,
    'الديون': Icons.account_balance_outlined,
    'المالية': Icons.wallet_outlined,
    'المعارض': Icons.festival_outlined,
    'التسويق': Icons.campaign_outlined,
    'التقارير': Icons.insights_outlined,
    'الإعدادات': Icons.settings_outlined,
  };
  List<String> get visibleSections => switch (m.actor) {
    'نجاة' => ['اليوم', 'الأصناف', 'المخزون', 'المشتريات', 'الإنتاج'],
    'سلمى' => ['اليوم', 'الأصناف', 'المخزون', 'المبيعات'],
    'حسن' => ['اليوم', 'التسويق'],
    'لقمان' => ['اليوم', 'الأصناف', 'المخزون'],
    _ => sections.keys.toList(),
  };
  @override
  void initState() {
    super.initState();
    m.addListener(changed);
    session?.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    m.removeListener(changed);
    session?.removeListener(changed);
    super.dispose();
  }

  Map<String, String> options(List<String> values) => {
    for (final value in values) value: value,
  };
  Map<String, String> records(
    String table,
    String Function(DataRow) label, {
    bool Function(DataRow)? where,
  }) => {
    for (final row in m.rows(table).where(where ?? (_) => true))
      row['id']: label(row),
  };
  String productName(String id) {
    final p = m.byId('products', id);
    return '${p['name']} ${p['size']} · ${tr(context, p['unit'])}';
  }

  String lotLabel(DataRow lot) =>
      '${productName(lot['product'])} | ${lot['batch']} | ${lot['location']} | ${number(lot, 'quantity')}';
  Map<String, String> get productOptions =>
      records('products', (p) => productName(p['id']));
  Map<String, String> get lotOptions => records(
    'lots',
    lotLabel,
    where: (r) =>
        number(r, 'quantity') > 0 &&
        r['location'] != 'طلبية محجوزة' &&
        (admin ||
            (m.actor == 'نجاة'
                ? r['location'] == workshop
                : m.actor == 'سلمى'
                ? r['location'] == shop
                : true)),
  );
  FormFieldSpec field(
    String key,
    String label, {
    String initial = '',
    bool optional = false,
    int lines = 1,
    bool numeric = false,
  }) => FormFieldSpec(
    key,
    label,
    initial: initial,
    optional: optional,
    lines: lines,
    numeric: numeric,
  );
  FormFieldSpec select(
    String key,
    String label,
    Map<String, String> values, {
    bool optional = false,
  }) => FormFieldSpec(
    key,
    label,
    options: optional ? {'': 'بدون', ...values} : values,
    optional: optional,
  );
  FormFieldSpec dateField(String key, String label) =>
      field(key, '$label (YYYY-MM-DD)', initial: today());
  FormFieldSpec moneyField(
    String key,
    String label, {
    String initial = '',
    bool optional = false,
  }) => field(
    key,
    '$label (د.م.)',
    initial: initial,
    optional: optional,
    numeric: true,
  );
  FormFieldSpec get amountField => field('quantity', 'الكمية', numeric: true);
  FormFieldSpec get accountField =>
      select('account', 'الحساب', options(accountNames));

  List<String> get accountNames => [
    ...accounts,
    ...m.rows('exhibitions').map((e) => 'صندوق ${e['name']}'),
  ];
  List<FormFieldSpec> get batchFields => [
    field('batch', 'رقم الدفعة LOT'),
    field('expiry', 'الصلاحية YYYY-MM-DD', optional: true),
  ];

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: AppText('تسجلات العملية بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText('$e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> form(
    String title,
    List<FormFieldSpec> specs,
    Future<void> Function(Map<String, String>) submit, {
    String? help,
  }) async {
    final values = <String, String>{
      for (final s in specs)
        s.keyName: s.options == null
            ? s.initial
            : (s.options!.containsKey(s.initial)
                  ? s.initial
                  : s.options!.keys.firstOrNull ?? ''),
    };
    final key = GlobalKey<FormState>();
    bool saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: AppText(title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Form(
                key: key,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (help != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: AppText(
                          help,
                          style: const TextStyle(color: ink),
                        ),
                      ),
                    for (final s in specs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: s.options != null
                            ? DropdownButtonFormField<String>(
                                initialValue:
                                    values[s.keyName]!.isEmpty &&
                                        !s.options!.containsKey('')
                                    ? null
                                    : values[s.keyName],
                                isExpanded: true,
                                decoration: InputDecoration(
                                  label: AppText(s.label),
                                ),
                                items: [
                                  for (final entry in s.options!.entries)
                                    DropdownMenuItem(
                                      value: entry.key,
                                      child: AppText(
                                        entry.value,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: saving
                                    ? null
                                    : (value) {
                                        values[s.keyName] = value ?? '';
                                      },
                                validator: (v) =>
                                    !s.optional && (v == null || v.isEmpty)
                                    ? tr(context, 'خاص اختيار')
                                    : null,
                              )
                            : TextFormField(
                                initialValue: s.initial,
                                minLines: s.lines,
                                maxLines: s.lines,
                                decoration: InputDecoration(
                                  label: AppText(s.label),
                                ),
                                keyboardType: s.numeric
                                    ? const TextInputType.numberWithOptions(
                                        decimal: true,
                                      )
                                    : TextInputType.text,
                                onChanged: (v) => values[s.keyName] = v,
                                validator: (v) =>
                                    !s.optional &&
                                        (v == null || v.trim().isEmpty)
                                    ? tr(context, 'كمّل هاد الخانة')
                                    : null,
                                enabled: !saving,
                              ),
                      ),
                    if (error != null)
                      AppText(
                        error!,
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const AppText('إلغاء'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!key.currentState!.validate()) return;
                      update(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await submit(values);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: AppText('تسجلات العملية بنجاح'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          update(() {
                            error = '$e';
                            saving = false;
                          });
                        }
                      }
                    },
              child: AppText(saving ? 'كيتسجل…' : 'تأكيد وتسجيل'),
            ),
          ],
        ),
      ),
    );
  }

  Widget button(
    String label,
    IconData icon,
    VoidCallback action, {
    bool secondary = false,
  }) => secondary
      ? OutlinedButton.icon(
          onPressed: m.busy || session?.processing == true ? null : action,
          icon: Icon(icon, size: 20),
          label: AppText(label),
        )
      : FilledButton.icon(
          onPressed: m.busy || session?.processing == true ? null : action,
          icon: Icon(icon, size: 20),
          label: AppText(label),
        );
  Widget actions(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(spacing: 12, runSpacing: 12, children: children),
  );
  Widget notice(String text, {IconData icon = Icons.info_outline}) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFECEFE4),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: ink),
        const SizedBox(width: 12),
        Expanded(child: AppText(text, style: const TextStyle(height: 1.6))),
      ],
    ),
  );
  Widget empty(String text, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: accent),
          const SizedBox(height: 16),
          AppText(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: ink),
          ),
        ],
      ),
    ),
  );
  Widget tile(
    String title,
    String subtitle, {
    List<Widget> controls = const [],
    IconData icon = Icons.receipt_long_outlined,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFF0F3EB),
                child: Icon(icon, color: ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AppText(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (controls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: controls),
            ),
        ],
      ),
    ),
  );
  Widget stack(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final c in children)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
    ],
  );
  Widget stats(Map<String, String> values) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final v in values.entries)
          SizedBox(
            width: constraints.maxWidth < 500
                ? constraints.maxWidth
                : (constraints.maxWidth - 24) / 3,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(v.key, style: const TextStyle(color: ink)),
                    const SizedBox(height: 12),
                    AppText(
                      v.value,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (session?.revoked == true) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppText('الصلاحية تبدلات. خاص تسجيل الدخول من جديد.'),
              TextButton(
                onPressed: () => run(session!.signOut),
                child: const AppText('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final nav = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                'ZIZOUIT',
                style: TextStyle(
                  fontSize: 26,
                  letterSpacing: 3,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              AppText(
                'تعاونية زيزويت ريف',
                style: TextStyle(color: Color(0xFFC6D8CF)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final item in visibleSections)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    selected: section == item,
                    selectedTileColor: Colors.white.withValues(alpha: 0.12),
                    selectedColor: Colors.white,
                    textColor: const Color(0xFFC6D8CF),
                    iconColor: const Color(0xFFC6D8CF),
                    leading: Icon(sections[item]),
                    title: AppText(item),
                    onTap: () {
                      setState(() {
                        section = item;
                        search = '';
                      });
                      if (!wide) Navigator.pop(context);
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.all(20),
          child: AppText(
            session == null
                ? 'نسخة محلية • بلا مزامنة\nالبيانات محفوظة فهاد الجهاز'
                : 'Firebase • حساب ${m.actor}\nالعمليات كتتزامن مع التعاونية',
            style: TextStyle(color: Color(0xFFC6D8CF), height: 1.7),
          ),
        ),
      ],
    );
    final body = Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 32 : 16,
            vertical: 14,
          ),
          child: Row(
            children: [
              if (!wide)
                Builder(
                  builder: (context) => IconButton(
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      section,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: ink,
                      ),
                    ),
                    const AppText(
                      'خطوة بخطوة، كلشي مسجل',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const LanguagePicker(),
              SizedBox(
                width: 125,
                child: m.authenticatedRole != null
                    ? AppText(m.actor, textAlign: TextAlign.center)
                    : DropdownButton<String>(
                        isExpanded: true,
                        value: m.actor,
                        items: [
                          for (final role in roles)
                            DropdownMenuItem(value: role, child: AppText(role)),
                        ],
                        onChanged: m.busy
                            ? null
                            : (value) => setState(() {
                                m.actor = value!;
                                section = 'اليوم';
                                search = '';
                              }),
                      ),
              ),
              const SizedBox(width: 8),
              if (session != null)
                IconButton(
                  tooltip: tr(context, 'تسجيل الخروج'),
                  onPressed: () => run(session!.signOut),
                  icon: const Icon(Icons.logout),
                ),
              const CircleAvatar(
                backgroundColor: ink,
                child: Icon(Icons.person_outline, color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(wide ? 32 : 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: content(),
              ),
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      drawer: wide ? null : Drawer(backgroundColor: ink, child: nav),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  SizedBox(
                    width: 235,
                    child: Material(color: ink, child: nav),
                  ),
                  Expanded(child: body),
                ],
              )
            : body,
      ),
    );
  }

  Widget content() => !visibleSections.contains(section)
      ? notice('ما عندكش صلاحية لهاذ الصفحة')
      : switch (section) {
          'الأصناف' => products(),
          'المخزون' => inventory(),
          'المشتريات' => purchases(),
          'الإنتاج' => production(),
          'المبيعات' => sales(),
          'الموردون' => suppliers(),
          'الديون' => debts(),
          'المالية' => finance(),
          'المعارض' => exhibitions(),
          'التسويق' => marketing(),
          'التقارير' => reports(),
          'الإعدادات' => settings(),
          _ => dashboard(),
        };
  Widget dashboard() => stack([
    notice(
      session == null
          ? 'مرحبا ${m.actor}. هادي نسخة محلية للتجربة. اختيار الاسم ماشي تسجيل دخول آمن؛ ما تدخلش بيانات حساسة قبل إعداد الخادم والصلاحيات.'
          : 'مرحبا ${m.actor}. الدور مرتبط بالحساب. البيانات المالية والديون غير متاحة إلا للمدير.',
    ),
    if (session != null) ...[
      notice(
        '${session!.status ?? 'المزامنة مفعلة'}\nعمليات فالجهاز: ${session!.outbox.length} · فانتظار المعالجة: ${session!.commands.where((c) => c['status'] == 'pending').length}',
      ),
      for (final command
          in session!.commands.where((c) => c['status'] == 'rejected').take(5))
        notice(
          'عملية ما تطبقاتش: ${command['error'] ?? 'تواصل مع المدير'}',
          icon: Icons.warning_amber,
        ),
      actions([
        button(
          'حدث المزامنة',
          Icons.sync,
          () => run(() async {
            await session!.flush();
            await session!.refresh();
          }),
          secondary: true,
        ),
      ]),
    ],
    if (admin)
      stats({
        'المبيعات المسلمة': money(m.revenue),
        'السيولة المسجلة': money(m.liquidity),
        'التزامات باقية': money(
          m.remaining('تأسيس قديم') + m.remaining('موردون'),
        ),
      }),
    if (admin)
      stats({
        'مستحقات الزبناء': money(m.remaining('زبناء')),
        'أصناف مسجلة': '${m.rows('products').length}',
        'شحنات مفتوحة':
            '${m.rows('lots').where((l) => l['shipment'] == true && number(l, 'quantity') > 0).length}',
      }),
    actions([
      if (m.allowed('production'))
        button('صنعت', Icons.spa_outlined, produceForm),
      if (m.allowed('purchase'))
        button('تسلمت السلعة', Icons.shopping_bag_outlined, purchaseForm),
      if (m.allowed('sale')) button('بعت', Icons.storefront_outlined, saleForm),
      if (m.allowed('transfer'))
        button('صيفطت للمحل', Icons.local_shipping_outlined, transferForm),
    ]),
    if (m.rows('products').isEmpty)
      empty(
        'بدا بتعريف الأصناف، ومن بعد سجل الجرد الافتتاحي',
        Icons.spa_outlined,
      ),
    if (admin && m.upcoming.isNotEmpty) ...[
      const AppText(
        'الاستحقاقات الجاية والمتأخرة',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: ink),
      ),
      for (final d in m.upcoming.take(5))
        tile(
          d['party'],
          '${d['category']} · ${d['due']} · ${money((d['amount'] as int) - (d['paid'] as int))}${(d['due'] as String).compareTo(today()) < 0 ? ' · متأخر' : ''}',
        ),
    ],
    for (final lot
        in m
            .rows('lots')
            .where(
              (l) =>
                  number(l, 'quantity') > 0 &&
                  (l['expiry'] as String).isNotEmpty &&
                  (l['expiry'] as String).compareTo(
                        DateTime.now()
                            .add(const Duration(days: 30))
                            .toIso8601String()
                            .substring(0, 10),
                      ) <=
                      0 &&
                  (admin ||
                      (m.actor == 'نجاة' && l['location'] == workshop) ||
                      (m.actor == 'سلمى' && l['location'] == shop)),
            ))
      notice(
        'تنبيه الصلاحية: ${lotLabel(lot)} · ${lot['expiry']}',
        icon: Icons.warning_amber,
      ),
  ]);
  void productForm() => form(
    'صنف جديد',
    [
      field('name', 'اسم الصنف'),
      select('family', 'العائلة', options(families)),
      field('size', 'الحجم أو المتغير'),
      select('unit', 'الوحدة', options(['قطعة', 'كلغ', 'لتر', 'غرام', 'مل'])),
      select(
        'flow',
        'طريقة العمل',
        options(['شراء جاهز', 'تصنيع', 'عصر', 'تعبئة', 'تجميع']),
      ),
    ],
    (v) =>
        m.product(v['name']!, v['family']!, v['size']!, v['unit']!, v['flow']!),
  );
  Widget products() {
    final filtered = m
        .rows('products')
        .where(
          (r) => '${r['name']} ${r['family']} ${r['size']} ${r['id']}'.contains(
            search,
          ),
        );
    return stack([
      if (m.allowed('product'))
        actions([button('زيد صنف', Icons.add, productForm)]),
      TextField(
        decoration: const InputDecoration(
          label: AppText('قلب على الاسم، العائلة أو الحجم'),
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (value) => setState(() => search = value),
      ),
      if (filtered.isEmpty) empty('ما كاين حتى صنف', Icons.category_outlined),
      for (final p in filtered)
        tile(
          productName(p['id']),
          '${p['id']} · ${p['family']} · ${p['flow']}',
          icon: Icons.spa_outlined,
        ),
    ]);
  }

  void openingForm() => form(
    'الجرد الافتتاحي',
    [
      select('product', 'الصنف', productOptions),
      amountField,
      select(
        'location',
        'الموقع',
        options([
          workshop,
          shop,
          ...m.rows('exhibitions').map((r) => r['name'] as String),
        ]),
      ),
      ...batchFields,
      moneyField('cost', 'التكلفة الإجمالية المؤكدة', optional: true),
    ],
    (v) => m.openingStock(
      v['product']!,
      quantity(v['quantity']!),
      v['location']!,
      v['batch']!,
      v['cost']!.isEmpty ? null : cents(v['cost']!),
      v['expiry']!,
    ),
    help:
        'خلي التكلفة فارغة إلا ما عندكش وثيقة مؤكدة. الجرد كيضيف مخزون؛ ماشي شراء ولا سيولة.',
  );
  void transferForm() => form(
    'صيفطت السلعة',
    [
      select('lot', 'الدفعة والموقع المصدر', lotOptions),
      amountField,
      select(
        'destination',
        'الوجهة',
        options([
          workshop,
          shop,
          ...m.rows('exhibitions').map((r) => r['name'] as String),
        ]),
      ),
    ],
    (v) => m.transfer(v['lot']!, quantity(v['quantity']!), v['destination']!),
    help:
        'غير الكمية المرسلة كتخرج من المصدر. المخزون فالوجهة ما كيزيد حتى يتأكد الاستلام.',
  );
  Widget inventory() {
    final lots = m
        .rows('lots')
        .where(
          (l) =>
              number(l, 'quantity') > 0 &&
              (admin ||
                  m.actor == 'لقمان' ||
                  (m.actor == 'نجاة' &&
                      (l['location'] == workshop || l['source'] == workshop)) ||
                  (m.actor == 'سلمى' &&
                      (l['location'] == shop || l['destination'] == shop))),
        )
        .where((l) => lotLabel(l).contains(search));
    return stack([
      actions([
        if (admin) button('جرد افتتاحي', Icons.add_box_outlined, openingForm),
        if (m.allowed('transfer'))
          button(
            'صيفطت السلعة',
            Icons.local_shipping_outlined,
            transferForm,
            secondary: true,
          ),
      ]),
      TextField(
        decoration: const InputDecoration(
          label: AppText('قلب على الصنف، LOT أو الموقع'),
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (value) => setState(() => search = value),
      ),
      notice(
        'الكمية المتاحة منفصلة عن الشحنات المفتوحة والطلبيات المحجوزة. التقييم الشامل للمخزون باقي خاصو اختيار المنهج؛ التكلفة المعروضة مرتبطة بالدفعة المحددة.',
      ),
      if (lots.isEmpty)
        empty(
          'المخزون خاوي. سجل الجرد أو استلام شراء',
          Icons.inventory_2_outlined,
        ),
      for (final lot in lots)
        tile(
          productName(lot['product']),
          '${lot['id']} · ${lot['batch']}\n${lot['location']} · ${number(lot, 'quantity')}\nالصلاحية: ${lot['expiry'] == '' ? 'غير مسجلة' : lot['expiry']}${admin ? '\nالتكلفة المتبقية: ${lotCostText(lot)}' : ''}${lot['shipment'] == true ? '\nمن ${lot['source']} إلى ${lot['destination']}' : ''}',
          controls: [
            if (lot['shipment'] == true &&
                m.allowed('receive') &&
                (admin || lot['destination'] == shop))
              button(
                'تسلمت',
                Icons.check,
                () => form('تأكيد الاستلام الفعلي', [
                  amountField,
                ], (v) => m.receive(lot['id'], quantity(v['quantity']!))),
                secondary: true,
              ),
            if (lot['shipment'] == true && m.allowed('transfer'))
              button(
                'رجعت للمصدر',
                Icons.undo,
                () => form(
                  'إرجاع شحنة',
                  [amountField],
                  (v) => m.receive(
                    lot['id'],
                    quantity(v['quantity']!),
                    returnToSource: true,
                  ),
                ),
                secondary: true,
              ),
            if (admin &&
                lot['shipment'] != true &&
                lot['location'] != 'طلبية محجوزة')
              button(
                'صحح الجرد',
                Icons.fact_check_outlined,
                () => form(
                  'مطابقة الجرد',
                  [
                    field('actual', 'الكمية الفعلية', numeric: true),
                    field('reason', 'سبب الفرق'),
                  ],
                  (v) {
                    final actual = double.tryParse(
                      v['actual']!.replaceAll(',', '.'),
                    );
                    if (actual == null) throw RuleViolation('دخل كمية صحيحة');
                    return m.adjust(lot['id'], actual, v['reason']!);
                  },
                ),
                secondary: true,
              ),
          ],
          icon: Icons.inventory_2_outlined,
        ),
      if (admin) ...[
        const AppText(
          'آخر حركات المخزون',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        for (final r in m.rows('movements').reversed.take(20))
          tile(
            '${r['kind']} · ${r['quantity']}',
            '${r['lot']} · ${r['description']}\n${r['actor']} · ${r['date']}',
          ),
      ],
    ]);
  }

  String lotCostText(DataRow lot) {
    final cost = m.lotCost(lot, number(lot, 'quantity'));
    return cost == null
        ? 'غير مؤكدة'
        : '${money(cost)} · ${lot['estimated'] == true ? 'مقدرة' : 'مقاسة'}';
  }

  void purchaseForm() => form(
    'تسلمت السلعة',
    [
      select('product', 'الصنف', productOptions),
      amountField,
      select('supplier', 'المورد', records('suppliers', (r) => r['name'])),
      field('invoice', 'رقم الفاتورة'),
      dateField('ordered', 'تاريخ الطلب'),
      dateField('received', 'تاريخ الوصول الفعلي'),
      dateField('due', 'الاستحقاق حسب الاتفاق'),
      if (admin) moneyField('unitCost', 'ثمن الوحدة', optional: true),
      if (admin)
        moneyField(
          'transport',
          'نقل ومصاريف مباشرة لهذه الدفعة فقط',
          initial: '0',
        ),
      if (admin) moneyField('paid', 'المبلغ المؤدى', initial: '0'),
      if (admin) accountField,
      ...batchFields,
    ],
    (v) => m.purchase(
      productId: v['product']!,
      amount: quantity(v['quantity']!),
      supplierId: v['supplier']!,
      invoice: v['invoice']!,
      ordered: v['ordered']!,
      received: v['received']!,
      due: v['due']!,
      unitCost: (v['unitCost'] ?? '').isEmpty ? null : cents(v['unitCost']!),
      transport: cents(v['transport'] ?? '0'),
      paid: admin ? cents(v['paid']!) : 0,
      account: v['account'] ?? accounts.first,
      batch: v['batch']!,
      expiry: v['expiry']!,
    ),
    help:
        'سجل المورد من لوحته أولاً. نجاة كتأكد الكمية، والمدير كيأكد التكلفة. الثمن المجهول يبقى غير مؤكد. الفاتورة المؤجلة كتزيد المخزون والدين بلا خروج نقدي. النقل هنا جزء من التكلفة؛ ما تسجلوش مرة أخرى كمصروف.',
  );
  Widget purchases() => stack([
    actions([button('تسلمت السلعة', Icons.add, purchaseForm)]),
    if (m.rows('purchases').isEmpty)
      empty('ما تسجل حتى شراء', Icons.shopping_bag_outlined),
    for (final p in m.rows('purchases').reversed)
      tile(
        '${p['invoice']} · ${productName(p['product'])}',
        '${p['quantity']} · ${m.byId('suppliers', p['supplier'])['name']}\nالطلب ${p['ordered']} · الوصول ${p['received']}\nالاستحقاق ${p['due']} · أكد الاستلام: ${p['confirmedBy']}${admin ? '\nالتكلفة الواصلة: ${p['cost'] == null ? 'غير مؤكدة' : money(p['cost'])}' : ''}',
        controls: [
          if (admin && p['cost'] == null)
            button(
              'أكد التكلفة',
              Icons.verified_outlined,
              () => form(
                'تأكيد تكلفة الشراء',
                [
                  moneyField('unit', 'ثمن الوحدة'),
                  moneyField('transport', 'نقل ومصاريف مباشرة', initial: '0'),
                ],
                (v) => m.confirmPurchaseCost(
                  p['id'],
                  cents(v['unit']!),
                  cents(v['transport']!),
                ),
              ),
              secondary: true,
            ),
          if (admin &&
              p['cost'] != null &&
              number(m.byId('lots', p['lot']), 'quantity') > 0)
            button(
              'مرتجع للمورد',
              Icons.undo,
              () => form(
                'مرتجع شراء',
                [amountField, field('reason', 'السبب والوثيقة'), accountField],
                (v) => m.returnPurchase(
                  p['id'],
                  quantity(v['quantity']!),
                  v['reason']!,
                  v['account']!,
                ),
                help:
                    'كيخصم من الدفعة الأصلية فالورشة وكيخفض الدين أولاً. استرداد ثمن السلعة فقط؛ النقل ما نفترضوش يرجع. الجدولة السابقة كتتلغى لإعادة اعتماد الرصيد.',
              ),
              secondary: true,
            ),
        ],
      ),
  ]);
  Future<void> produceForm() async {
    final available = m
        .rows('lots')
        .where((l) => l['location'] == workshop && number(l, 'quantity') > 0)
        .toList();
    if (available.isEmpty) {
      await run(() async {
        throw RuleViolation('سجل مواد الورشة أولاً');
      });
      return;
    }
    await form(
      'صنعت — دفعة إنتاج',
      [
        select('product', 'الصنف المنتج', productOptions),
        amountField,
        ...batchFields,
        for (final l in available)
          field(
            'input_${l['id']}',
            'المستعمل: ${lotLabel(l)}',
            optional: true,
            numeric: true,
          ),
        field('workers', 'العاملات المشاركات'),
        field('hours', 'الساعات الفعلية', numeric: true),
        field(
          'waste',
          'الهدر الفعلي — وضح الوحدة في النشاط',
          initial: '0',
          numeric: true,
        ),
        select(
          'activity',
          'النشاط',
          options(['تصنيع', 'عصر', 'تعبئة', 'تجميع']),
        ),
        moneyField('labor', 'تكلفة العمل المخصصة لهذه الدفعة', optional: true),
        moneyField('overhead', 'مصاريف الإنتاج المخصصة', initial: '0'),
        select('estimated', 'نوع قياس التكلفة', options(['مقاسة', 'مقدرة'])),
      ],
      (v) => m.produce(
        inputs: [
          for (final l in available)
            if (v['input_${l['id']}']!.isNotEmpty)
              {'lot': l['id'], 'quantity': quantity(v['input_${l['id']}']!)},
        ],
        productId: v['product']!,
        output: quantity(v['quantity']!),
        batch: v['batch']!,
        expiry: v['expiry']!,
        workers: v['workers']!,
        hours: quantity(v['hours']!),
        waste: double.parse(v['waste']!.replaceAll(',', '.')),
        labor: v['labor']!.isEmpty ? null : cents(v['labor']!),
        overhead: cents(v['overhead']!),
        activity: v['activity']!,
        estimated: v['estimated'] == 'مقدرة',
      ),
      help:
          'الكمية الأولى هي الناتج الصالح الفعلي. دخل استهلاك كل مادة، بما فيها التغليف؛ خلي غير المستعمل فارغ. الناتج كامل كيدخل للورشة. الأجور هنا توزيع للتكلفة فقط؛ الأداء النقدي من المالية. ما نفترضوش مردودية ثابتة للعصر.',
    );
  }

  Widget production() => stack([
    actions([
      button('صنعت', Icons.add, produceForm),
      button('حفظ وصفة', Icons.menu_book_outlined, recipeForm, secondary: true),
    ]),
    if (m.rows('production').isEmpty)
      empty('سجل أول دفعة إنتاج فعلية', Icons.spa_outlined),
    for (final r in m.rows('production').reversed)
      tile(
        '${m.byId('lots', r['lot'])['batch']} · ${r['activity']}',
        '${productName(m.byId('lots', r['lot'])['product'])} · ${r['quantity']}\n${r['workers']} · ${r['hours']} ساعة · هدر ${r['waste']}\n${r['date']}${admin ? '\nالتكلفة: ${r['cost'] == null ? 'غير مؤكدة' : money(r['cost'])} · ${r['estimated'] == true ? 'مقدرة' : 'مقاسة'}' : ''}\n${(r['inputs'] as List).map((i) => '${i['lot']}: ${i['quantity']}').join(' / ')}',
        icon: Icons.spa_outlined,
      ),
    for (final r in m.rows('recipes'))
      tile(
        'وصفة: ${r['name']}',
        '${productName(r['product'])}\n${recipeSummary(r)}\n${r['description']}',
        icon: Icons.menu_book_outlined,
        controls: [
          if ((r['ingredients'] as List?)?.isNotEmpty == true)
            button(
              'عبأت بالوصفة',
              Icons.auto_awesome,
              () => conversionForm(r),
              secondary: true,
            ),
        ],
      ),
  ]);
  String recipeSummary(DataRow recipe) =>
      'لكل ${recipe['outputQuantity'] ?? 1} من الناتج:\n${((recipe['ingredients'] as List?) ?? []).map((i) => '${i['quantity']} ${m.byId('products', i['product'])['unit']} من ${productName(i['product'])}').join('\n')}';
  void recipeForm() => form(
    'وصفة تحويل وتعبئة',
    [
      field('name', 'اسم الوصفة'),
      select('product', 'الصنف المعبأ للبيع', productOptions),
      field('basis', 'عدد النواتج في الوصفة', initial: '1', numeric: true),
      for (final p in m.rows('products'))
        field(
          'ingredient_${p['id']}',
          'كمية ${productName(p['id'])} لكل دفعة وصفة',
          optional: true,
          numeric: true,
        ),
      field('description', 'خطوات وملاحظات', optional: true, lines: 3),
    ],
    (v) {
      final ingredients = <DataRow>[
        for (final p in m.rows('products'))
          if (v['ingredient_${p['id']}']!.isNotEmpty)
            {
              'product': p['id'],
              'quantity': quantity(v['ingredient_${p['id']}']!),
            },
      ];
      if (ingredients.isEmpty) {
        throw RuleViolation('حدد المادة السائبة ومواد العبوة المطلوبة');
      }
      return m.recipe(
        v['name']!,
        v['product']!,
        v['description']!.trim().isEmpty
            ? 'تعبئة حسب المقادير المسجلة'
            : v['description']!,
        outputQuantity: quantity(v['basis']!),
        ingredients: ingredients,
      );
    },
    help:
        'عرف المادة السائبة والعبوات كأصناف مستقلة. مثال لكل قرعة عسل 250غ: 0.25 كلغ عسل سائب + 1 قرعة + 1 غطاء + 1 ملصق. المقادير بوحدة كل صنف؛ ما كنبدلوش الوحدات بالتخمين.',
  );
  void conversionForm(DataRow recipe) => form(
    'عبأت: ${recipe['name']}',
    [
      amountField,
      ...batchFields,
      field('workers', 'العاملات المشاركات'),
      field('hours', 'الساعات الفعلية', numeric: true),
      moneyField('labor', 'تكلفة العمل المخصصة', optional: true),
      moneyField('overhead', 'مصاريف مخصصة', initial: '0'),
    ],
    (v) => m.produceFromRecipe(
      recipeId: recipe['id'],
      output: quantity(v['quantity']!),
      batch: v['batch']!,
      expiry: v['expiry']!,
      workers: v['workers']!,
      hours: quantity(v['hours']!),
      labor: v['labor']!.isEmpty ? null : cents(v['labor']!),
      overhead: cents(v['overhead']!),
    ),
    help:
        '${recipeSummary(recipe)}\nدخل عدد العبوات الفعلي. المواد والتغليف كيتخصمو تلقائياً من دفعات الورشة الأقرب للصلاحية. الصلاحية الفارغة كتتورث من أقرب مادة، والناتج كيدخل مخزون الورشة.',
  );
  void saleForm() => form(
    'بعت / حجزت طلبية',
    [
      select('lot', 'الدفعة والموقع', lotOptions),
      amountField,
      moneyField('price', 'ثمن الوحدة'),
      field('customer', 'الزبون', optional: true),
      select(
        'channel',
        'قناة إتمام الطلب',
        options([
          'المحل',
          'الورشة',
          'الجملة',
          'معرض',
          'واتساب',
          'تسليم مباشر',
          'آخر',
        ]),
      ),
      select(
        'discovery',
        'كيفاش عرفنا الزبون',
        options(['غير معروف', 'فيسبوك', 'إنستغرام', 'توصية', 'زيارة', 'آخر']),
      ),
      select(
        'campaign',
        'الحملة المنسوب ليها البيع — حسب الدليل',
        records('campaigns', (r) => r['name']),
        optional: true,
      ),
      select(
        'exhibition',
        'المعرض',
        records('exhibitions', (r) => r['name']),
        optional: true,
      ),
      moneyField('paid', 'التحصيل الفعلي', initial: '0'),
      accountField,
      dateField('due', 'استحقاق الباقي'),
      select('reserve', 'الحالة', options(['بيع مسلم', 'طلبية محجوزة'])),
      if (admin)
        select('approve', 'اعتماد بيع أقل من التكلفة', options(['لا', 'نعم'])),
    ],
    (v) => m.sale(
      lotId: v['lot']!,
      amount: quantity(v['quantity']!),
      unitPrice: cents(v['price']!),
      customer: v['customer']!,
      channel: v['channel']!,
      discovery: v['discovery']!,
      paid: cents(v['paid']!),
      account: v['account']!,
      due: v['due']!,
      approved: v['approve'] == 'نعم',
      reserve: v['reserve'] == 'طلبية محجوزة',
      campaign: v['campaign']!,
      exhibition: v['exhibition']!,
    ),
    help:
        'البيع كيخصم من الدفعة المختارة فقط. الحجز كيحفظ الكمية بلا تسجيل مبيعات أو تحصيل حتى التسليم. التكلفة المجهولة ما كتولدش ربح وهمي.',
  );
  Widget sales() => stack([
    actions([button('بعت', Icons.add, saleForm)]),
    if (m.rows('sales').isEmpty)
      empty('ما تسجل حتى بيع', Icons.storefront_outlined),
    for (final s
        in m
            .rows('sales')
            .reversed
            .where(
              (s) => admin || m.byId('lots', s['lot'])['location'] == shop,
            ))
      tile(
        '${productName(s['product'])} · ${s['customer'] == '' ? 'زبون مباشر' : s['customer']}',
        '${s['id']} · ${s['quantity']} · ${money(s['total'])}\n${s['status']} · ${s['channel']} · المصدر: ${s['discovery']}\n${s['date']} · مرتجع ${number(s, 'returned')}${admin ? '\nالتكلفة: ${s['cost'] == null ? 'غير مؤكدة' : money(s['cost'])}' : ''}',
        controls: [
          if (s['status'] == 'محجوز')
            button(
              'إلغاء الحجز',
              Icons.close,
              () => form('إلغاء طلبية', [
                field('reason', 'السبب'),
              ], (v) => m.cancelOrder(s['id'], v['reason']!)),
              secondary: true,
            ),
          if (s['status'] == 'محجوز')
            button(
              'سلمت الطلبية',
              Icons.check,
              () => form(
                'تسليم طلبية',
                [
                  moneyField('paid', 'المبلغ المحصل', initial: '0'),
                  accountField,
                  if (admin)
                    select(
                      'approve',
                      'اعتماد بيع أقل من التكلفة',
                      options(['لا', 'نعم']),
                    ),
                ],
                (v) => m.deliver(
                  s['id'],
                  cents(v['paid']!),
                  v['account']!,
                  v['approve'] == 'نعم',
                ),
              ),
              secondary: true,
            ),
          if (admin &&
              s['status'] == 'مسلم' &&
              number(s, 'returned') < number(s, 'quantity'))
            button(
              'مرتجع',
              Icons.undo,
              () => form(
                'مرتجع بيع',
                [amountField, field('reason', 'السبب'), accountField],
                (v) => m.returnSale(
                  s['id'],
                  quantity(v['quantity']!),
                  v['reason']!,
                  v['account']!,
                ),
                help:
                    'كيتم تخفيض ذمة الزبون أولاً، والباقي كيرجع من الحساب المختار. الكمية كترجع للموقع الأصلي.',
              ),
              secondary: true,
            ),
        ],
        icon: Icons.storefront_outlined,
      ),
  ]);
  Widget suppliers() => stack([
    actions([
      button(
        'زيد مورد',
        Icons.add,
        () => form('ملف مورد', [
          field('name', 'الاسم'),
          field('contact', 'الهاتف وبيانات الاتصال', optional: true),
          field('terms', 'شروط الأداء المتفق عليها', optional: true, lines: 3),
        ], (v) => m.supplier(v['name']!, v['contact']!, v['terms']!)),
      ),
    ]),
    if (m.rows('suppliers').isEmpty)
      empty('عرف الموردين قبل تسجيل المشتريات', Icons.local_shipping_outlined),
    for (final s in m.rows('suppliers')) supplierTile(s),
  ]);
  Widget supplierTile(DataRow s) {
    final purchases = m
        .rows('purchases')
        .where((p) => p['supplier'] == s['id'])
        .toList();
    final purchaseIds = purchases.map((p) => p['id']).toSet();
    final debts = m
        .rows('debts')
        .where(
          (d) => d['category'] == 'موردون' && purchaseIds.contains(d['source']),
        );
    final paid = debts.fold<int>(0, (sum, d) => sum + (d['paid'] as int));
    final remaining = debts.fold<int>(
      0,
      (sum, d) => sum + (d['principal'] as int) - (d['paid'] as int),
    );
    return tile(
      s['name'],
      '${s['contact']}\n${s['terms']}\n${purchases.length} توريد · ديون مؤداة ${money(paid)} · باقي ${money(remaining)}\nآخر توريد: ${purchases.isEmpty ? 'ما كاينش' : purchases.last['received']}\n${purchases.any((p) => p['cost'] == null) ? 'كاين شراء بتكلفة غير مؤكدة' : 'إجمالي شراء مؤكد: ${money(purchases.fold<int>(0, (sum, p) => sum + (p['cost'] as int)))}'}',
      icon: Icons.local_shipping_outlined,
    );
  }

  Widget debts() => stack([
    actions([
      button(
        'دين تأسيس قديم',
        Icons.add,
        () => form(
          'دين تأسيس مستقل',
          [
            field('party', 'الدائن'),
            moneyField('principal', 'الرصيد الموثق عند بداية التتبع'),
            dateField('due', 'الاستحقاق'),
            field('reason', 'الأصل والسبب والوثيقة المرجعية', lines: 3),
          ],
          (v) => m.historicalDebt(
            v['party']!,
            cents(v['principal']!),
            v['due']!,
            v['reason']!,
          ),
          help:
              'سجل فقط الرصيد الموثق عند بداية التتبع، واشرح أصل الدين والأداء السابق فالمرجع. الأداء المسجل هنا كيتبع الفترة الحالية.',
        ),
      ),
    ]),
    notice(
      'ثلاث فئات مستقلة. ديون الموردين كتجي من الشراء، وذمم الزبناء من البيع. الفرق بين المستحقات والالتزامات ماشي سيولة.',
    ),
    for (final category in debtCategories) ...[
      AppText(
        category,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: ink,
        ),
      ),
      stats({
        'الأصل المسجل': money(m.debtTotal(category, 'principal')),
        'المؤدى / المحصل': money(m.debtTotal(category, 'paid')),
        'المتبقي': money(m.remaining(category)),
      }),
      if (m.rows('debts').where((d) => d['category'] == category).isEmpty)
        empty('ما كاين حتى سجل فهاد الفئة', Icons.account_balance_outlined),
      for (final d in m.rows('debts').where((d) => d['category'] == category))
        debtTile(d),
    ],
    notice(m.repaymentAdvice),
  ]);
  Widget debtTile(DataRow d) {
    final principal = d['principal'] as int;
    final paid = d['paid'] as int;
    final remaining = principal - paid;
    return tile(
      d['party'],
      '${d['id']} · ${d['reason']}\nالأصل ${money(principal)} · المؤدى ${money(paid)} · باقي ${money(remaining)}\nالسداد ${principal == 0 ? '100' : (paid * 100 / principal).toStringAsFixed(1)}% · الاستحقاق ${d['due']}\n${(d['installments'] as List).map((p) => '${p['due']} · ${money(p['amount'])} · باقي ${money((p['amount'] as int) - (p['paid'] as int))}').join('\n')}',
      controls: [
        if (remaining > 0)
          button(
            d['category'] == 'زبناء' ? 'حصلت دفعة' : 'خلصت دفعة',
            Icons.payments_outlined,
            () => form(
              'دفعة فعلية',
              [moneyField('amount', 'المبلغ'), accountField],
              (v) => m.payDebt(d['id'], cents(v['amount']!), v['account']!),
              help:
                  'كيحدث الدين والحساب مرة وحدة. ما كيعيدش تسجيل شراء أو بيع.',
            ),
            secondary: true,
          ),
        if (remaining > 0 && (d['installments'] as List).isEmpty)
          button(
            'جدول الأقساط',
            Icons.calendar_month_outlined,
            () => form(
              'جدولة الرصيد المتبقي',
              [
                field(
                  'parts',
                  'قسط في كل سطر: YYYY-MM-DD = مبلغ بالدرهم',
                  lines: 5,
                ),
              ],
              (v) {
                final installments = <DataRow>[];
                for (final line
                    in v['parts']!
                        .split('\n')
                        .where((line) => line.trim().isNotEmpty)) {
                  final parts = line.split('=');
                  if (parts.length != 2) {
                    throw RuleViolation('كل سطر خاصو تاريخ = مبلغ');
                  }
                  installments.add({
                    'due': parts[0].trim(),
                    'amount': cents(parts[1]),
                  });
                }
                return m.schedule(d['id'], installments);
              },
              help:
                  'مجموع الأقساط خاصو يساوي ${money(remaining)}. الأداء كيتوزع على الأقساط حسب الاستحقاق.',
            ),
            secondary: true,
          ),
      ],
      icon: Icons.account_balance_outlined,
    );
  }

  Widget finance() => stack([
    stats({for (final a in accountNames) a: money(m.balance(a))}),
    actions([
      button(
        'سجل حركة مالية',
        Icons.add,
        () => form(
          'حركة مالية',
          [
            accountField,
            select(
              'kind',
              'نوع العملية',
              options(['رصيد افتتاحي', 'تمويل', 'مصروف تشغيل', 'سحب شخصي']),
            ),
            moneyField('amount', 'المبلغ'),
            field('reason', 'الوصف والوثيقة المرجعية', lines: 2),
          ],
          (v) => m.finance(
            v['account']!,
            cents(v['amount']!),
            v['kind']!,
            v['reason']!,
          ),
          help:
              'التمويل والسحب الشخصي منفصلان عن المصروف. أداء دين المورد أو تحصيل الزبون من لوحة الديون. الأجور تحتاج سجل فترة لتجنب التكرار؛ لا تدخل الأجر نفسه مرتين.',
        ),
      ),
      button(
        'تحويل بين حسابات',
        Icons.swap_horiz,
        () => form('تحويل مالي', [
          select('from', 'من', options(accountNames)),
          select('to', 'إلى', options(accountNames)),
          moneyField('amount', 'المبلغ'),
        ], (v) => m.accountTransfer(v['from']!, v['to']!, cents(v['amount']!))),
        secondary: true,
      ),
      button(
        'خلصت أجر',
        Icons.person_outline,
        () => form(
          'أجر شهري',
          [
            field('employee', 'الشخص', initial: 'حسن'),
            field('month', 'الفترة YYYY-MM', initial: today().substring(0, 7)),
            moneyField('amount', 'المبلغ الفعلي', initial: '1000'),
            accountField,
          ],
          (v) => m.salary(
            v['employee']!,
            v['month']!,
            cents(v['amount']!),
            v['account']!,
          ),
          help:
              'أجر حسن المرجعي 1000 د.م. كنمنعو تكرار نفس الشخص ونفس الشهر. باقي الأجور خاصها اتفاق مؤكد.',
        ),
        secondary: true,
      ),
      button(
        'طابقت الصندوق',
        Icons.fact_check_outlined,
        () => form(
          'مطابقة يومية',
          [
            accountField,
            moneyField('actual', 'الرصيد الفعلي المعدود'),
            field('explanation', 'المطابقة أو تفسير الفرق', lines: 2),
          ],
          (v) => m.closeCash(
            v['account']!,
            cents(v['actual']!),
            v['explanation']!,
          ),
          help: 'كيحفظ الرصيد الفعلي والفرق؛ ما كيبدلش الرصيد الحسابي آلياً.',
        ),
        secondary: true,
      ),
    ]),
    notice(
      'الرصيد المسجل ماشي ربح. هامش البيع فالتقارير مستقل عن السيولة. إقفال الصندوق الرسمي، التسويات القانونية للسحب الشخصي وكشوف البنك باقي خاصها مراجعة واعتماد.',
    ),
    if (m.rows('ledger').isEmpty)
      empty('سجل الرصيد الافتتاحي لكل حساب', Icons.wallet_outlined),
    for (final c in m.rows('closings').reversed)
      tile(
        'مطابقة ${c['account']} · ${c['date']}',
        'مسجل ${money(c['recorded'])} · فعلي ${money(c['actual'])} · الفرق ${money(c['difference'])}\n${c['explanation']}',
      ),
    for (final r in m.rows('ledger').reversed)
      tile(
        '${r['kind']} · ${money(r['amount'])}',
        '${r['account']} · ${r['description']}\n${r['date']} · المرجع ${r['reference']}',
        icon: Icons.wallet_outlined,
      ),
  ]);
  Widget exhibitions() => stack([
    actions([
      button(
        'ملف معرض',
        Icons.add,
        () => form('معرض جديد', [
          field('name', 'اسم المعرض الفريد'),
          field('city', 'المدينة'),
          dateField('start', 'البداية'),
          dateField('end', 'النهاية'),
        ], (v) => m.exhibition(v['name']!, v['city']!, v['start']!, v['end']!)),
      ),
    ]),
    notice(
      'صيفط المخزون للمعرض من لوحة المخزون وأكد الاستلام. اختار اسم المعرض عند البيع؛ الصندوق المستقل متاح فالمالية. المصاريف المسجلة هنا كتخرج من الحساب مرة وحدة.',
    ),
    if (m.rows('exhibitions').isEmpty)
      empty('ما كاين حتى معرض', Icons.festival_outlined),
    for (final e in m.rows('exhibitions'))
      tile(
        e['name'],
        '${e['city']} · ${e['start']} إلى ${e['end']}\nمبيعات مسلمة: ${money(m.rows('sales').where((s) => s['exhibition'] == e['id'] && s['status'] == 'مسلم').fold<int>(0, (sum, s) => sum + (s['total'] as int) - (s['credited'] as int? ?? 0)))}\nالمخزون الحالي: ${m.rows('lots').where((l) => l['location'] == e['name'] && number(l, 'quantity') > 0).map(lotLabel).join('\n')}',
        icon: Icons.festival_outlined,
        controls: [
          button(
            'سجل مصروف',
            Icons.payments_outlined,
            () => eventExpense(e, false),
            secondary: true,
          ),
          button(
            'تقرير PDF',
            Icons.picture_as_pdf_outlined,
            () => run(
              () => printReport(
                'تقرير المعرض',
                eventReport(e),
                language: LanguageScope.of(context).value,
              ),
            ),
            secondary: true,
          ),
        ],
      ),
  ]);
  Widget marketing() => stack([
    actions([
      button(
        'زيد حملة',
        Icons.add,
        () => form('حملة تسويقية', [
          field('name', 'الاسم'),
          select('source', 'المنصة', options(['فيسبوك', 'إنستغرام', 'آخر'])),
          dateField('start', 'البداية'),
          dateField('end', 'النهاية'),
        ], (v) => m.campaign(v['name']!, v['source']!, v['start']!, v['end']!)),
      ),
    ]),
    notice(
      'مصدر اكتشاف الزبون منفصل عن قناة إتمام الطلب. نسبة مساهمة الإعلان ما كتفترضش بلا دليل. أجر حسن المرجعي 1000 د.م. شهرياً؛ ما كاين حتى أداء مفترض.',
    ),
    if (m.rows('campaigns').isEmpty)
      empty(
        'سجل الحملات وربط المبيعات حسب المصدر المؤكد',
        Icons.campaign_outlined,
      ),
    for (final c in m.rows('campaigns'))
      tile(
        c['name'],
        '${c['source']} · ${c['start']} إلى ${c['end']}${admin ? '\nالمبيعات المنسوبة: ${money(m.rows('sales').where((s) => s['campaign'] == c['id'] && s['status'] == 'مسلم').fold<int>(0, (sum, s) => sum + (s['total'] as int) - (s['credited'] as int? ?? 0)))}' : ''}',
        icon: Icons.campaign_outlined,
        controls: [
          if (admin)
            button(
              'سجل تكلفة',
              Icons.payments_outlined,
              () => eventExpense(c, true),
              secondary: true,
            ),
          if (admin) AppText('التكلفة المسجلة: ${money(eventCost(c['id']))}'),
        ],
      ),
  ]);
  Widget reports() {
    final delivered = m
        .rows('sales')
        .where((s) => s['status'] == 'مسلم')
        .toList();
    final unknown = delivered.where((s) => s['cost'] == null).length;
    final knownMargin = delivered
        .where((s) => s['cost'] != null)
        .fold<int>(
          0,
          (sum, s) =>
              sum +
              (s['total'] as int) -
              (s['credited'] as int? ?? 0) -
              (number(s, 'cost') *
                      (1 - number(s, 'returned') / number(s, 'quantity')))
                  .round(),
        );
    return stack([
      stats({
        'إيراد مسجل': money(m.revenue),
        'هامش المبيعات المؤكدة': money(knownMargin),
        'مبيعات بتكلفة مجهولة': '$unknown',
      }),
      notice(
        'هاد الهامش ماشي ربح صافي. ما كيشملش تسويات المصاريف والأجور والمخزون؛ ما كنحسبوش ربح المبيعات بتكلفة غير مؤكدة.',
      ),
      actions([
        button(
          'تقرير PDF',
          Icons.picture_as_pdf_outlined,
          () => run(
            () => printReport(
              'تقرير زيزويت ريف',
              reportText(),
              language: LanguageScope.of(context).value,
            ),
          ),
        ),
        button(
          'نسخ تقرير',
          Icons.copy_outlined,
          () => showText('تقرير نشاط', reportText()),
        ),
      ]),
      const AppText(
        'تقويم الاستحقاقات',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: ink),
      ),
      for (final d in m.upcoming)
        tile(
          '${d['due']} · ${d['party']}',
          '${d['category']} · باقي ${money((d['amount'] as int) - (d['paid'] as int))}',
        ),
      notice(
        'الزكاة 2026: معلقة للمراجعة. خاص تحديد ملكية أصول التعاونية، الحول والنصاب، قيمة عروض التجارة يوم الوجوب ومراجعة الذمم وفق المرجعية المالكية. لا توجد حاسبة نهائية قبل تثبيت هذه القرارات.',
      ),
      notice(m.repaymentAdvice),
    ]);
  }

  int eventCost(String reference) => -m
      .rows('ledger')
      .where((r) => r['reference'] == reference && r['amount'] < 0)
      .fold<int>(0, (sum, r) => sum + (r['amount'] as int));
  void eventExpense(DataRow record, bool campaign) => form(
    campaign ? 'تكلفة حملة' : 'مصروف معرض',
    [
      accountField,
      moneyField('amount', 'المبلغ'),
      select(
        'kind',
        'التصنيف',
        options(
          campaign
              ? ['إعلان', 'مصروف تسويق']
              : ['نقل معرض', 'إقامة', 'كراء معرض', 'عمالة معرض', 'مصروف معرض'],
        ),
      ),
      field('reason', 'الوصف والمرجع'),
    ],
    (v) => m.finance(
      v['account']!,
      cents(v['amount']!),
      v['kind']!,
      v['reason']!,
      reference: record['id'],
    ),
    help:
        'ربط بالملف وخروج نقدي مرة وحدة. ما تدخلش نفس الأداء فالمالية مرة أخرى.',
  );
  String eventReport(DataRow event) {
    final sales = m
        .rows('sales')
        .where((s) => s['exhibition'] == event['id'] && s['status'] == 'مسلم')
        .toList();
    final revenue = sales.fold<int>(
      0,
      (sum, s) => sum + (s['total'] as int) - (s['credited'] as int? ?? 0),
    );
    final unknown = sales.any((s) => s['cost'] == null);
    final cost = sales.fold<int>(
      0,
      (sum, s) =>
          sum +
          (number(s, 'cost') *
                  (1 - number(s, 'returned') / number(s, 'quantity')))
              .round(),
    );
    final expenses = eventCost(event['id']);
    return '${event['name']} — ${event['city']}\n${event['start']} إلى ${event['end']}\nمبيعات ${money(revenue)}\nمصاريف مسجلة ${money(expenses)}\nنتيجة البيع بعد المصاريف: ${unknown ? 'غير مؤكدة — تكلفة مفقودة' : money(revenue - cost - expenses)}\nالصندوق ${money(m.balance('صندوق ${event['name']}'))}\nالمخزون الحالي:\n${m.rows('lots').where((l) => l['location'] == event['name']).map(lotLabel).join('\n')}\nالنتيجة حسب التكاليف المسجلة فقط وتحتاج مراجعة التخصيصات.';
  }

  String reportText() =>
      'تقرير زيزويت ريف — ${today()}\nالمبيعات المسلمة: ${money(m.revenue)}\nالسيولة المسجلة: ${money(m.liquidity)}\n${debtCategories.map((c) => '$c: أصل ${money(m.debtTotal(c, 'principal'))}، مؤدى ${money(m.debtTotal(c, 'paid'))}، باقي ${money(m.remaining(c))}').join('\n')}\nهذا تقرير محلي؛ الربح الصافي والزكاة غير معتمدين.\n${m.upcoming.map((d) => '${d['due']} ${d['party']}: ${money((d['amount'] as int) - (d['paid'] as int))}').join('\n')}';
  Future<void> showText(String title, String text, {bool localize = true}) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: AppText(title),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: AppSelectableText(text, localize: localize),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const AppText('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: localize ? tr(context, text) : text),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: AppText('تنسخ النص')));
                }
              },
              icon: const Icon(Icons.copy),
              label: const AppText('نسخ'),
            ),
          ],
        ),
      );
  Widget settings() => stack([
    if (session != null) ...[
      notice(
        'Firebase مرتبط بحسابك. التعيين بالأرقام UID كيعطي صلاحيات الخادم، وليس اختياراً محلياً. عمليات العاملات كتتعالج آلياً ملي جهاز المدير متصل.',
      ),
      actions([
        button(
          'عين صلاحية حساب',
          Icons.manage_accounts,
          () => form('تعيين دور', [
            field('uid', 'UID من شاشة حساب الشخص'),
            select('role', 'الدور', options(roles)),
          ], (v) => session!.setMember(v['uid']!, v['role']!)),
        ),
        button(
          'حدث بيانات الخادم',
          Icons.sync,
          () => run(session!.refresh),
          secondary: true,
        ),
      ]),
    ],
    notice(
      session == null
          ? 'تخزين محلي فقط. تبديل الأدوار للعرض والتجربة وليس حماية للبيانات. فعل إعداد Firebase للولوج والصلاحيات والمزامنة.'
          : 'البيانات المالية والديون محفوظة في وثيقة خاصة بالمدير. النسخة المحلية للحساب كتتمسح عند الخروج؛ ما تدخلش مفاتيح الخدمة أو كلمات السر فالنسخ الاحتياطية.',
    ),
    actions([
      button(
        'نسخة احتياطية JSON',
        Icons.copy_outlined,
        () => showText(
          'نسخة احتياطية — احفظ النص في ملف آمن',
          m.export(),
          localize: false,
        ),
      ),
      button(
        'استرجاع نسخة',
        Icons.restore,
        () => form(
          'استرجاع نسخة احتياطية',
          [
            field('json', 'نص النسخة JSON', lines: 8),
            field('confirm', 'كتب: استرجاع'),
          ],
          (v) {
            if (v['confirm'] != 'استرجاع') {
              throw RuleViolation('أكد الاسترجاع بالكلمة المطلوبة');
            }
            return m.restore(v['json']!);
          },
          help:
              'كتستبدل البيانات المحلية بالنسخة المختارة. خذ نسخة احتياطية من البيانات الحالية قبل التأكيد.',
        ),
        secondary: true,
      ),
    ]),
    const AppText(
      'قرارات باقية',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: ink),
    ),
    notice(
      'منهج تقييم المخزون • ملكية التعاونية وحصص الأعضاء • أجور وساعات العاملات • دور لقمان واعتماده • الميزانية والاستضافة • الحول الزكوي. لقمان هنا عرض فقط، ووئام مستبعدة حسب المرجع.',
    ),
    const AppText(
      'سجل التدقيق المحلي',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: ink),
    ),
    for (final r in m.rows('audit').reversed.take(100))
      tile(
        r['description'],
        '${r['actor']} · ${r['date']} · ${r['id']}',
        icon: Icons.history_outlined,
      ),
  ]);
}
