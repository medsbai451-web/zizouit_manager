import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseConfig {
  static const enabled = bool.fromEnvironment('FIREBASE_ENABLED');
  static const workspace = String.fromEnvironment(
    'FIREBASE_WORKSPACE',
    defaultValue: 'zizouit',
  );
  static FirebaseOptions get options {
    const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const sender = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    final appId = kIsWeb
        ? const String.fromEnvironment('FIREBASE_WEB_APP_ID')
        : defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
        ? const String.fromEnvironment('FIREBASE_IOS_APP_ID')
        : const String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
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
