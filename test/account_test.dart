import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zizouit_manager/firebase/account_service.dart';
import 'package:zizouit_manager/firebase/email_verification_screen.dart';
import 'package:zizouit_manager/firebase/sign_in_screen.dart';
import 'package:zizouit_manager/l10n/app_language.dart';
import 'package:zizouit_manager/main.dart';

class FakeAccounts implements AccountService {
  bool preference = true;
  List<Object>? signedIn;
  List<Object>? signedUp;
  List<Object>? reset;
  Object? failure;
  Completer<void>? pending;
  int requests = 0;
  @override
  Future<bool> readStaySignedIn() async => preference;
  @override
  Future<void> signIn(String email, String password, bool remember) async {
    requests++;
    signedIn = [email, password, remember];
    if (failure != null) throw failure!;
    await pending?.future;
  }

  @override
  Future<void> signUp(
    String name,
    String email,
    String password,
    bool remember,
  ) async {
    requests++;
    signedUp = [name, email, password, remember];
    if (failure != null) throw failure!;
  }

  @override
  Future<void> resetPassword(String email, AppLanguage language) async {
    reset = [email, language];
    if (failure != null) throw failure!;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Remembered web sessions use LOCAL; unchecked sessions use SESSION',
    () async {
      final modes = <Persistence>[];
      var signouts = 0;
      final preference = AuthPersistence(
        web: true,
        setPersistence: (mode) async => modes.add(mode),
        signOut: () async => signouts++,
      );
      await preference.initialize();
      await preference.select(false);
      await preference.initialize();
      expect(modes, [
        Persistence.LOCAL,
        Persistence.SESSION,
        Persistence.SESSION,
      ]);
      expect(signouts, 0);
      expect((await SharedPreferences.getInstance()).getKeys(), {
        AuthPersistence.preferenceKey,
      });
      await preference.select(true);
      expect(await preference.read(), isTrue);
    },
  );

  test(
    'Native remembered sessions survive; unchecked sessions sign out at cold start',
    () async {
      var signouts = 0;
      final preference = AuthPersistence(
        web: false,
        setPersistence: (_) async =>
            fail('Native SDK persistence must not be changed'),
        signOut: () async => signouts++,
      );
      await preference.initialize();
      expect(signouts, 0);
      await preference.select(false);
      expect(signouts, 0);
      await preference.initialize();
      expect(signouts, 1);
      await preference.select(true);
      await preference.initialize();
      expect(signouts, 1);
    },
  );

  testWidgets(
    'Sign in forwards the session choice and blocks duplicate submissions',
    (tester) async {
      final accounts = FakeAccounts()..pending = Completer<void>();
      await tester.pumpWidget(
        MyApp(homeOverride: SignInScreen(accounts: accounts)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('account-email')),
        ' medsbai451@gmail.com ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        'secret123',
      );
      await tester.tap(find.byKey(const ValueKey('stay-signed-in')));
      await tester.tap(find.byKey(const ValueKey('account-submit')));
      await tester.pump();
      expect(accounts.signedIn, ['medsbai451@gmail.com', 'secret123', false]);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('account-submit')))
            .onPressed,
        isNull,
      );
      accounts.pending!.complete();
      await tester.pumpAndSettle();
      expect(accounts.requests, 1);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('account-password')),
            )
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'Sign up validates confirmation and creates a user without role selection',
    (tester) async {
      final accounts = FakeAccounts();
      await tester.pumpWidget(
        MyApp(homeOverride: SignInScreen(accounts: accounts)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('switch-account-mode')),
      );
      await tester.tap(find.byKey(const ValueKey('switch-account-mode')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('signup-name')),
        ' Salma ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-email')),
        'salma@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-password')),
        'secret123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('signup-confirmation')),
        'different123',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('account-submit')));
      await tester.tap(find.byKey(const ValueKey('account-submit')));
      await tester.pumpAndSettle();
      expect(accounts.signedUp, isNull);
      expect(find.text('كلمات السر ما متطابقاش'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('signup-confirmation')),
        'secret123',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('account-submit')));
      await tester.tap(find.byKey(const ValueKey('account-submit')));
      await tester.pumpAndSettle();
      expect(accounts.signedUp, [
        'Salma',
        'salma@example.com',
        'secret123',
        true,
      ]);
    },
  );

  testWidgets('Password setup needs an email and uses the selected language', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LanguageController.preferenceKey: 'fr',
    });
    final accounts = FakeAccounts();
    await tester.pumpWidget(
      MyApp(homeOverride: SignInScreen(accounts: accounts)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('reset-password')));
    await tester.tap(find.byKey(const ValueKey('reset-password')));
    await tester.pumpAndSettle();
    expect(accounts.reset, isNull);
    expect(
      find.text(
        'Saisissez d’abord votre adresse e-mail pour réinitialiser le mot de passe.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      'medsbai451@gmail.com',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('reset-password')));
    await tester.tap(find.byKey(const ValueKey('reset-password')));
    await tester.pumpAndSettle();
    expect(accounts.reset, ['medsbai451@gmail.com', AppLanguage.french]);
    expect(find.textContaining('Si le compte existe'), findsOneWidget);
  });

  testWidgets('Failed login shows a translated error and re-enables the form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LanguageController.preferenceKey: 'ar',
    });
    final accounts = FakeAccounts()
      ..failure = FirebaseAuthException(code: 'invalid-credential');
    await tester.pumpWidget(
      MyApp(homeOverride: SignInScreen(accounts: accounts)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'incorrect',
    );
    await tester.tap(find.byKey(const ValueKey('account-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('تعذر تسجيل الدخول. تحقق من البريد وكلمة المرور.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('account-submit')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'Verification screen exposes no manager data and requests verification privately',
    (tester) async {
      AppLanguage? requested;
      var refreshes = 0;
      await tester.pumpWidget(
        MyApp(
          homeOverride: EmailVerificationScreen(
            email: 'user@example.com',
            send: (language) async => requested = language,
            refresh: () async => refreshes++,
            signOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('المالية'), findsNothing);
      expect(find.text('الديون'), findsNothing);
      await tester.tap(find.text('صيفط رسالة التحقق'));
      await tester.pumpAndSettle();
      expect(requested, AppLanguage.darija);
      await tester.tap(find.text('أكدت البريد — عاود التحقق'));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    },
  );

  testWidgets('French sign-up fits a phone screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      LanguageController.preferenceKey: 'fr',
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MyApp(homeOverride: SignInScreen(accounts: FakeAccounts())),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('switch-account-mode')),
    );
    await tester.tap(find.byKey(const ValueKey('switch-account-mode')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('account-submit')));
    expect(tester.takeException(), isNull);
  });
}
