import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'firebase_defaults.dart';

class FirebaseConfig {
  static const enabled = bool.fromEnvironment(
    'FIREBASE_ENABLED',
    defaultValue: true,
  );
  static const workspace = String.fromEnvironment(
    'FIREBASE_WORKSPACE',
    defaultValue: 'zizouit',
  );
  static FirebaseOptions get options {
    const project = String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: FirebaseDefaults.projectId,
    );
    const fallbackKey = String.fromEnvironment('FIREBASE_API_KEY');
    final platformKey = kIsWeb
        ? const String.fromEnvironment('FIREBASE_WEB_API_KEY')
        : defaultTargetPlatform == TargetPlatform.android
        ? const String.fromEnvironment('FIREBASE_ANDROID_API_KEY')
        : const String.fromEnvironment('FIREBASE_IOS_API_KEY');
    final platformDefault = kIsWeb
        ? FirebaseDefaults.webApiKey
        : defaultTargetPlatform == TargetPlatform.android
        ? FirebaseDefaults.androidApiKey
        : FirebaseDefaults.iosApiKey;
    final apiKey = platformKey.isNotEmpty
        ? platformKey
        : fallbackKey.isNotEmpty
        ? fallbackKey
        : platformDefault;
    const sender = String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: FirebaseDefaults.messagingSenderId,
    );
    final appId = kIsWeb
        ? const String.fromEnvironment(
            'FIREBASE_WEB_APP_ID',
            defaultValue: FirebaseDefaults.webAppId,
          )
        : defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
        ? const String.fromEnvironment(
            'FIREBASE_IOS_APP_ID',
            defaultValue: FirebaseDefaults.iosAppId,
          )
        : const String.fromEnvironment(
            'FIREBASE_ANDROID_APP_ID',
            defaultValue: FirebaseDefaults.androidAppId,
          );
    if ([project, apiKey, sender, appId].any((value) => value.isEmpty)) {
      throw StateError(
        'Firebase غير مهيأ. كمّل firebase_config.json حسب تعليمات الإعداد.',
      );
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: sender,
      projectId: project,
      authDomain: '$project.firebaseapp.com',
      storageBucket: '$project.firebasestorage.app',
      iosBundleId: const String.fromEnvironment(
        'FIREBASE_IOS_BUNDLE_ID',
        defaultValue: 'com.example.zizouitManager',
      ),
    );
  }
}
