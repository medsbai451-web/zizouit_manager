import 'dart:async';

import '../l10n/app_language.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/manager.dart' hide DataRow;
import 'firebase_config.dart';
import 'firebase_session.dart';
import 'sign_in_screen.dart';
import 'email_verification_screen.dart';
export 'sign_in_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.builder});
  final Widget Function(Manager, FirebaseSession) builder;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? subscription;
  FirebaseSession? session;
  String? error;
  bool loading = true;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    subscription = FirebaseAuth.instance.authStateChanges().listen(load);
  }

  Future<void> load(User? user) async {
    final current = ++generation;
    await session?.stop();
    session = null;
    if (!mounted) return;
    setState(() {
      loading = user != null;
      error = null;
    });
    if (user == null) return;
    if (!user.emailVerified) {
      setState(() => loading = false);
      return;
    }
    FirebaseSession? candidate;
    try {
      final member = await FirebaseFirestore.instance
          .collection('workspaces')
          .doc(FirebaseConfig.workspace)
          .collection('members')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      final role = member.data()?['role'];
      if (member.data()?['active'] != true || !roles.contains(role)) {
        throw StateError('حسابك بانتظار تفعيل المدير وتعيين الدور.');
      }
      candidate = FirebaseSession(user: user, role: role as String);
      await candidate.start();
      if (!mounted || current != generation) {
        await candidate.stop();
        return;
      }
      setState(() {
        session = candidate;
        loading = false;
      });
    } catch (e) {
      await candidate?.stop();
      if (mounted && current == generation) {
        setState(() {
          error = e is StateError
              ? e.message.toString()
              : 'تعذر التحقق من الحساب. تحقق من الإنترنت وإعداد Firebase.';
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    generation++;
    subscription?.cancel();
    session?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session != null) return widget.builder(session!.manager, session!);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SignInScreen();
    if (!user.emailVerified) {
      return EmailVerificationScreen(
        email: user.email ?? '',
        send: (language) async {
          await FirebaseAuth.instance.setLanguageCode(
            language == AppLanguage.french ? 'fr' : 'ar',
          );
          await user.sendEmailVerification();
        },
        refresh: () async {
          await user.reload();
          final refreshed = FirebaseAuth.instance.currentUser;
          await refreshed?.getIdToken(true);
          await load(refreshed);
        },
        signOut: FirebaseAuth.instance.signOut,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LanguagePicker(),
                  AppText(
                    error ?? 'الحساب بانتظار التفعيل',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const AppText('رقم الحساب باش المدير يعين الدور:'),
                  AppSelectableText(user.uid),
                  TextButton.icon(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: user.uid)),
                    icon: const Icon(Icons.copy),
                    label: const AppText('نسخ رقم الحساب'),
                  ),
                  FilledButton(
                    onPressed: () => load(user),
                    child: const AppText('عاود التحقق'),
                  ),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
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
}
