import 'package:flutter/material.dart';
import '../l10n/app_language.dart';
import 'account_service.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.send,
    required this.refresh,
    required this.signOut,
  });
  final String email;
  final Future<void> Function(AppLanguage) send;
  final Future<void> Function() refresh;
  final Future<void> Function() signOut;
  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool busy = false;
  String? message;
  String? error;
  Future<void> run(Future<void> Function() action, {String? success}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) setState(() => message = success);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: LanguagePicker(),
                ),
                const Icon(Icons.mark_email_unread_outlined, size: 60),
                const SizedBox(height: 20),
                const AppText(
                  'أكد البريد الإلكتروني',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.email,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const AppText(
                  'فتح رسالة التحقق وكليكي على الرابط، ومن بعد عاود التحقق هنا. ما كاينش ولوج للبيانات قبل تأكيد البريد.',
                ),
                const SizedBox(height: 20),
                if (message != null) AppText(message!),
                if (error != null)
                  AppText(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(
                          () => widget.send(LanguageScope.of(context).value),
                          success:
                              'تبعثات رسالة التحقق. قلب حتى فالبريد المزعج.',
                        ),
                  child: const AppText('صيفط رسالة التحقق'),
                ),
                TextButton(
                  onPressed: busy ? null : () => run(widget.refresh),
                  child: const AppText('أكدت البريد — عاود التحقق'),
                ),
                TextButton(
                  onPressed: busy ? null : () => run(widget.signOut),
                  child: const AppText('تسجيل الخروج'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
