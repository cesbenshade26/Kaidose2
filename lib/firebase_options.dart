// firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web platform not configured');
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      default:
        throw UnsupportedError('Platform not supported for this project');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAdV0Fq7nqNngEYPgp6ZiEKCTOiqprIffg',
    appId: '1:226093347823:android:8eb36792adb570ead3c1a',
    messagingSenderId: '226093347823',
    projectId: 'kaidose2-e0a7a',
    storageBucket: 'kaidose2-e0a7a.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAdV0Fq7nqNngEYPgp6ZiEKCTOiqprIffg',
    appId: '1:226093347823:ios:a95373292315f3206755536', // Double check this ID in Firebase Console
    messagingSenderId: '226093347823',
    projectId: 'kaidose2-e0a7a',
    storageBucket: 'kaidose2-e0a7a.firebasestorage.app',
    iosBundleId: 'com.Kaidose.kaidose',
  );
}