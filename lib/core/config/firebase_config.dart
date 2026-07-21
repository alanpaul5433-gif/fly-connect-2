import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseConfig {
  // ── Web config (from Firebase Console) ─────────────────────
  static const String apiKey = 'AIzaSyATy7l4IIgxxZ0J7iFqQHLO9hCqIeh1CHs';
  static const String authDomain = 'flyconnect-ab4f2.firebaseapp.com';
  static const String databaseURL = 'https://flyconnect-ab4f2-default-rtdb.firebaseio.com';
  static const String projectId = 'flyconnect-ab4f2';
  static const String storageBucket = 'flyconnect-ab4f2.firebasestorage.app';
  static const String messagingSenderId = '361504801284';
  /// Web client app ID (`app_id` in the Web app snippet).
  static const String webAppId = '1:361504801284:web:891ccdee6e7143f3c0ab51';
  static const String measurementId = 'G-DBSSBSMEVR';

  /// Android client app ID: `mobilesdk_app_id` in `android/app/google-services.json`
  /// after you register package [androidPackageName] in Firebase Console.
  /// Native Analytics / Crashlytics need this (Web `app_id` causes 404 / missing google_app_id).
  static const String androidAppId = '1:361504801284:android:7b9682e73d98c7fbc0ab51';

  /// iOS client app ID: `GOOGLE_APP_ID` in `GoogleService-Info.plist`.
  static const String iosAppId = '1:361504801284:ios:8a69029e723e238dc0ab51';

  // ── App config ─────────────────────────────────────────────
  // Canonical bundle ID used across google-services.json, AndroidManifest,
  // and iOS Info.plist. Must stay in sync with Firebase Console.
  static const String androidPackageName = 'com.urbansyncinnovations.flyconnect';
  static const String iosBundleId = 'com.urbansyncinnovations.flyconnect';

  // ── Deep link scheme ───────────────────────────────────────
  static const String deepLinkScheme = 'flyconnect';
  static const String deepLinkHost = 'app.flyconnect.com';

  // ── Admin role identifier ──────────────────────────────────
  static const String adminRole = 'admin';

  /// [Firebase.initializeApp] options for the current platform (correct native `appId`).
  static FirebaseOptions get currentPlatformOptions {
    if (kIsWeb) {
      return const FirebaseOptions(
        apiKey: apiKey,
        appId: webAppId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        authDomain: authDomain,
        storageBucket: storageBucket,
        measurementId: measurementId,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final resolved = androidAppId.isNotEmpty ? androidAppId : webAppId;
        if (androidAppId.isEmpty && kDebugMode) {
          debugPrint(
            '[FirebaseConfig] androidAppId is empty — using web app id; '
            'native Analytics/Crashlytics will misbehave. Set androidAppId to '
            'mobilesdk_app_id from google-services.json (or run flutterfire configure).',
          );
        }
        return FirebaseOptions(
          apiKey: apiKey,
          appId: resolved,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          authDomain: authDomain,
          storageBucket: storageBucket,
        );
      case TargetPlatform.iOS:
        final resolved = iosAppId.isNotEmpty ? iosAppId : webAppId;
        if (iosAppId.isEmpty && kDebugMode) {
          debugPrint(
            '[FirebaseConfig] iosAppId is empty — using web app id; '
            'set iosAppId from GoogleService-Info.plist for native SDKs.',
          );
        }
        return FirebaseOptions(
          apiKey: apiKey,
          appId: resolved,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          authDomain: authDomain,
          storageBucket: storageBucket,
        );
      default:
        return const FirebaseOptions(
          apiKey: apiKey,
          appId: webAppId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          authDomain: authDomain,
          storageBucket: storageBucket,
          measurementId: measurementId,
        );
    }
  }
}
