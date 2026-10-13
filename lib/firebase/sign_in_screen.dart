import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import 'account_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.accounts});
  final AccountService? accounts;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final confirmation = TextEditingController();
  final formKey = GlobalKey<FormState>();
  late final AccountService accounts =
      widget.accounts ?? FirebaseAccountService();
  bool busy = false;
  bool signup = false;
  bool staySignedIn = true;
  bool showPassword = false;
  bool preferenceChanged = false;
  String? error;
  String? message;

  @override
  void initState() {
    super.initState();
    loadPreference();
  }

  Future<void> loadPreference() async {
    try {
      final saved = await accounts.readStaySignedIn();
      if (mounted && !preferenceChanged) setState(() => staySignedIn = saved);
    } catch (_) {
      // A temporary read failure keeps the default choice visible.
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    confirmation.dispose();
    super.dispose();
  }

  bool validEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

  Future<void> submit() async {
    if (busy || !formKey.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      if (signup) {
        await accounts.signUp(
          name.text.trim(),
          email.text.trim(),
          password.text,
          staySignedIn,
        );
      } else {
        await accounts.signIn(email.text.trim(), password.text, staySignedIn);
      }
      if (mounted) {
        password.clear();
        confirmation.clear();
      }
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (busy) return;
    if (!validEmail(email.text)) {
      setState(() {
        error = 'دخل البريد الإلكتروني أولاً باش تسترجع كلمة السر.';
        message = null;
      });
      return;
    }
    final language = LanguageScope.of(context).value;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await accounts.resetPassword(email.text.trim(), language);
      if (mounted) {
        setState(
          () => message =
              'إلا كان الحساب موجود، غادي توصلك رسالة باش تعين كلمة السر. قلب حتى فالبريد المزعج.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: LanguagePicker(),
                    ),
                    const Icon(Icons.spa_outlined, size: 60),
                    const SizedBox(height: 16),
                    const AppText(
                      'ZIZOUIT Manager',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppText(
                      signup ? 'إنشاء حساب' : 'تسجيل الدخول',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const AppText(
                      'دخل بحسابك. الدور والصلاحيات كيعينهم المدير؛ ماشي اختيار من الجهاز.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (signup) ...[
                      TextFormField(
                        key: const ValueKey('signup-name'),
                        controller: name,
                        enabled: !busy,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          label: AppText('الاسم الكامل'),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? tr(context, 'كمّل هاد الخانة')
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      key: const ValueKey('account-email'),
                      controller: email,
                      enabled: !busy,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        label: AppText('البريد الإلكتروني'),
                      ),
                      validator: (value) => !validEmail(value ?? '')
                          ? tr(context, 'دخل بريد صحيح')
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('account-password'),
                      controller: password,
                      enabled: !busy,
                      obscureText: !showPassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: signup
                          ? TextInputAction.next
                          : TextInputAction.done,
                      autofillHints: [
                        signup
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        label: const AppText('كلمة السر'),
                        suffixIcon: IconButton(
                          tooltip: tr(
                            context,
                            showPassword ? 'خبي كلمة السر' : 'بين كلمة السر',
                          ),
                          onPressed: busy
                              ? null
                              : () => setState(
                                  () => showPassword = !showPassword,
                                ),
                          icon: Icon(
                            showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? tr(context, 'كمّل هاد الخانة')
                          : signup && value.length < 8
                          ? tr(context, 'كلمة السر خاصها 8 حروف على الأقل')
                          : null,
                      onFieldSubmitted: (_) {
                        if (!signup) submit();
                      },
                    ),
                    if (signup) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('signup-confirmation'),
                        controller: confirmation,
                        enabled: !busy,
                        obscureText: !showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          label: AppText('أكد كلمة السر'),
                        ),
                        validator: (value) =>
                            value != password.text || (value ?? '').isEmpty
                            ? tr(context, 'كلمات السر ما متطابقاش')
                            : null,
                        onFieldSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 12),
                      const AppText(
                        'من بعد إنشاء الحساب، أكد البريد الإلكتروني. المدير كيعين الدور قبل الولوج للبيانات.',
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      key: const ValueKey('stay-signed-in'),
                      contentPadding: EdgeInsets.zero,
                      value: staySignedIn,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const AppText('بقى داخل للحساب'),
                      subtitle: const AppText('فعلها غير فجهازك الشخصي.'),
                      onChanged: busy
                          ? null
                          : (value) => setState(() {
                              preferenceChanged = true;
                              staySignedIn = value ?? true;
                            }),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppText(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppText(message!),
                      ),
                    FilledButton(
                      key: const ValueKey('account-submit'),
                      onPressed: busy ? null : submit,
                      child: AppText(
                        busy
                            ? 'كنتحقق…'
                            : signup
                            ? 'إنشاء حساب'
                            : 'تسجيل الدخول',
                      ),
                    ),
                    if (!signup)
                      TextButton(
                        key: const ValueKey('reset-password'),
                        onPressed: busy ? null : resetPassword,
                        child: const AppText(
                          'نسيت كلمة السر / تعيين كلمة السر',
                        ),
                      ),
                    TextButton(
                      key: const ValueKey('switch-account-mode'),
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              signup = !signup;
                              error = null;
                              message = null;
                              password.clear();
                              confirmation.clear();
                              formKey.currentState?.reset();
                            }),
                      child: AppText(
                        signup
                            ? 'عندك حساب؟ سجل الدخول'
                            : 'ما عندكش حساب؟ أنشئ حساب',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
