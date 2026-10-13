import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/manager.dart' hide DataRow;
import 'firebase_config.dart';
import 'firebase_session.dart';

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
                  Text(
                    error ?? 'الحساب بانتظار التفعيل',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const Text('رقم الحساب باش المدير يعين الدور:'),
                  SelectableText(user.uid),
                  TextButton.icon(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: user.uid)),
                    icon: const Icon(Icons.copy),
                    label: const Text('نسخ رقم الحساب'),
                  ),
                  FilledButton(
                    onPressed: () => load(user),
                    child: const Text('عاود التحقق'),
                  ),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('تسجيل الخروج'),
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

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final key = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit(bool signup) async {
    if (!key.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (signup) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          error = e.code == 'network-request-failed'
              ? 'تحقق من الإنترنت'
              : 'تعذر تسجيل الدخول أو إنشاء الحساب. تحقق من البريد وكلمة السر (${e.code}).';
        });
      }
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
            child: Form(
              key: key,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.spa_outlined, size: 60),
                  const SizedBox(height: 16),
                  const Text(
                    'ZIZOUIT Manager',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'دخل بحسابك. الدور والصلاحيات كيعينهم المدير؛ ماشي اختيار من الجهاز.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                    ),
                    validator: (v) =>
                        v == null || !v.contains('@') ? 'دخل بريد صحيح' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: password,
                    enabled: !busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'كلمة السر'),
                    validator: (v) => v == null || v.length < 6
                        ? 'كلمة السر خاصها 6 حروف على الأقل'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: busy ? null : () => submit(false),
                    child: Text(busy ? 'كنتحقق…' : 'تسجيل الدخول'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => submit(true),
                    child: const Text('إنشاء حساب — يحتاج تفعيل المدير'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
