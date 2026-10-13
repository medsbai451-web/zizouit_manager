import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_language.dart';

/// Firebase owns the credentials. Preferences store only the session choice.
class AuthPersistence {
  const AuthPersistence({
    required this.web,
    required this.setPersistence,
    required this.signOut,
  });
  static const preferenceKey = 'zizouit.auth.staySignedIn';
  final bool web;
  final Future<void> Function(Persistence) setPersistence;
  final Future<void> Function() signOut;

  Future<bool> read() async =>
      (await SharedPreferences.getInstance()).getBool(preferenceKey) ?? true;

  Future<void> initialize() async {
    final remember = await read();
    if (web) {
      await setPersistence(remember ? Persistence.LOCAL : Persistence.SESSION);
    } else if (!remember) {
      // Native SDKs always persist their session; clear it at the next cold start.
      await signOut();
    }
  }

  Future<void> select(bool remember) async {
    if (web) {
      await setPersistence(remember ? Persistence.LOCAL : Persistence.SESSION);
    }
    final saved = await (await SharedPreferences.getInstance()).setBool(
      preferenceKey,
      remember,
    );
    if (!saved) throw StateError('تعذر حفظ اختيار الجلسة. عاود المحاولة.');
  }

  static AuthPersistence firebase(FirebaseAuth auth) => AuthPersistence(
    web: kIsWeb,
    setPersistence: auth.setPersistence,
    signOut: auth.signOut,
  );
}

abstract class AccountService {
  Future<bool> readStaySignedIn();
  Future<void> signIn(String email, String password, bool staySignedIn);
  Future<void> signUp(
    String name,
    String email,
    String password,
    bool staySignedIn,
  );
  Future<void> resetPassword(String email, AppLanguage language);
}

class FirebaseAccountService implements AccountService {
  FirebaseAuth get auth => FirebaseAuth.instance;
  @override
  Future<bool> readStaySignedIn() => AuthPersistence.firebase(auth).read();
  @override
  Future<void> signIn(String email, String password, bool staySignedIn) async {
    await AuthPersistence.firebase(auth).select(staySignedIn);
    await auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signUp(
    String name,
    String email,
    String password,
    bool staySignedIn,
  ) async {
    await AuthPersistence.firebase(auth).select(staySignedIn);
    final credential = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    // Verification is sent from the dedicated screen after AuthGate reacts.
    // There is no client-side role selection or administrator assignment.
    await credential.user?.updateDisplayName(name);
  }

  @override
  Future<void> resetPassword(String email, AppLanguage language) async {
    await auth.setLanguageCode(language == AppLanguage.french ? 'fr' : 'ar');
    try {
      await auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      // The same confirmation avoids exposing whether an email is registered.
      if (e.code != 'user-not-found') rethrow;
    }
  }
}

String accountError(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'network-request-failed' => 'تحقق من الإنترنت',
      'email-already-in-use' =>
        'هاد البريد مسجل. دخل للحساب أو عين كلمة السر من الاسترجاع.',
      'weak-password' => 'كلمة السر ضعيفة. اختار كلمة أقوى.',
      'invalid-email' => 'دخل بريد صحيح',
      'too-many-requests' => 'محاولات كثيرة. تسنى شوية وعاود.',
      'operation-not-allowed' =>
        'الدخول بالبريد وكلمة السر مازال ما مفعلش فـ Firebase.',
      _ => 'تعذر تسجيل الدخول. تحقق من البريد وكلمة السر.',
    };
  }
  return 'تعذرت العملية. تحقق من الاتصال وعاود المحاولة.';
}
