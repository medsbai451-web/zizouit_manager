import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';

enum AppLanguage {
  darija('darija', 'الدارجة', Locale('ar', 'MA')),
  arabic('ar', 'العربية الفصحى', Locale('ar')),
  french('fr', 'Français', Locale('fr'));

  const AppLanguage(this.code, this.label, this.locale);
  final String code;
  final String label;
  final Locale locale;
  bool get rtl => this != french;
}

class LanguageController extends ChangeNotifier {
  LanguageController({AppLanguage initial = AppLanguage.darija})
    : _value = initial;
  static const preferenceKey = 'zizouit.language';
  AppLanguage _value;
  AppLanguage get value => _value;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _writes = Future<void>.value();

  Future<void> load() async {
    final revision = _revision;
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(preferenceKey);
      if (_disposed || revision != _revision) return;
      for (final language in AppLanguage.values) {
        if (language.code == saved && language != _value) {
          _value = language;
          notifyListeners();
        }
      }
    } catch (_) {
      // Keep the selected language when device preferences are unavailable.
    }
  }

  void select(AppLanguage language) {
    if (_value == language) return;
    _revision++;
    _value = language;
    notifyListeners();
    _writes = _writes.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(preferenceKey, language.code);
      } catch (_) {
        // A preference failure does not prevent changing the display language.
      }
    });
  }

  Future<void> get saved => _writes;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class LanguageScope extends InheritedNotifier<LanguageController> {
  const LanguageScope({
    super.key,
    required LanguageController controller,
    required super.child,
  }) : super(notifier: controller);
  static LanguageController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanguageScope>()!.notifier!;
}

String tr(BuildContext context, String text) =>
    translate(text, LanguageScope.of(context).value);

final _templates = translations.keys.where((key) => key.contains('{}')).map((
  key,
) {
  final parts = key.split('{}');
  return (
    key: key,
    pattern: RegExp(
      '^${parts.map(RegExp.escape).join('(.*?)')}\$',
      dotAll: true,
    ),
    specificity: parts.join().length,
  );
}).toList()..sort((a, b) => b.specificity.compareTo(a.specificity));

/// Translate application messages and templates without changing stored values.
/// Captured values are translated only when they themselves are known labels.
String translate(String text, AppLanguage language, {int depth = 0}) {
  if (language == AppLanguage.darija || depth > 12) return text;
  final index = language == AppLanguage.arabic ? 0 : 1;
  final exact = translations[text];
  if (exact != null) return exact[index];
  for (final template in _templates) {
    final match = template.pattern.firstMatch(text);
    if (match == null) continue;
    var group = 0;
    return translations[template.key]![index].replaceAllMapped(
      RegExp(r'\{\}'),
      (_) => translate(match.group(++group)!, language, depth: depth + 1),
    );
  }
  // Compound labels and report lines retain user-entered names and numbers.
  for (final separator in ['\n', ' · ', ' | ']) {
    if (text.contains(separator)) {
      return text
          .split(separator)
          .map((part) => translate(part, language, depth: depth + 1))
          .join(separator);
    }
  }
  return text;
}

class AppText extends StatelessWidget {
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  @override
  Widget build(BuildContext context) => Text(
    tr(context, data),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
  );
}

class AppSelectableText extends StatelessWidget {
  const AppSelectableText(this.data, {super.key, this.localize = true});
  final String data;
  final bool localize;
  @override
  Widget build(BuildContext context) =>
      SelectableText(localize ? tr(context, data) : data);
}

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = LanguageScope.of(context);
    return PopupMenuButton<AppLanguage>(
      key: const ValueKey('language-picker'),
      tooltip: switch (controller.value) {
        AppLanguage.darija => 'اللغة',
        AppLanguage.arabic => 'اللغة',
        AppLanguage.french => 'Langue',
      },
      icon: const Icon(Icons.language),
      initialValue: controller.value,
      onSelected: controller.select,
      itemBuilder: (_) => [
        for (final language in AppLanguage.values)
          CheckedPopupMenuItem(
            value: language,
            checked: controller.value == language,
            child: Text(
              language.label,
              textDirection: language.rtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            ),
          ),
      ],
    );
  }
}
