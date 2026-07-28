import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

// Firebase Emulator Suite wiring for end-to-end tests.
//
// The whole harness is gated behind a compile-time flag so normal
// `flutter run` / release builds are completely unaffected — `useEmulator`
// defaults to `false` and every guard in `main.dart` collapses to a no-op.
//
// Turn it on for an E2E run with:
//   flutter test integration_test/... --dart-define=USE_FIREBASE_EMULATOR=true
//
// Nothing here touches production Firebase: `connectToEmulators` retargets the
// default singletons at localhost/10.0.2.2, so every provider and service in
// the app (which all read `FirebaseFirestore.instance`, `FirebaseAuth.instance`,
// etc.) follows automatically with zero per-call-site changes.

/// Whether the app should connect to the local Firebase Emulator Suite.
///
/// Compile-time constant so tree-shaking removes the emulator path from
/// production binaries.
const bool useEmulator =
    bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);

/// Emulator ports — must match the `emulators` block in `firebase.json`.
const int _authPort = 9099;
const int _firestorePort = 8080;
const int _databasePort = 9000;
const int _storagePort = 9199;

/// Host the running app must dial to reach the emulators on the developer's
/// machine.
///
/// - Android emulator: the host loopback is aliased to `10.0.2.2`.
/// - iOS Simulator (and desktop/web): the emulators bind to `localhost`.
///
/// Guard `Platform` behind `!kIsWeb` — importing `dart:io` `Platform` throws on
/// web. E2E only targets iOS/Android, so this is sufficient.
String get emulatorHost =>
    (!kIsWeb && Platform.isAndroid) ? '10.0.2.2' : 'localhost';

/// Points the default Firebase singletons at the local emulator suite.
///
/// Call exactly once, immediately after `Firebase.initializeApp` and before any
/// provider/service touches a backend. Wiring is:
///   - Auth (async — must be awaited before any auth call)
///   - Firestore
///   - Realtime Database (before the first `.ref()` in presence)
///   - Storage
///
/// The Functions emulator needs no client wiring: the app never calls a
/// callable/HTTPS function directly — Cloud Functions run purely as Firestore
/// `onDocument*` triggers, which fire off the writes the emulator receives.
///
/// Each call is wrapped so a hot-restart mid-run (which would otherwise assert
/// on "instance already configured") does not crash the test binary.
Future<void> connectToEmulators() async {
  final host = emulatorHost;
  debugPrint('[emulator] connecting to Firebase emulators on $host');

  // Firestore (synchronous).
  try {
    FirebaseFirestore.instance.useFirestoreEmulator(host, _firestorePort);
  } catch (e) {
    debugPrint('[emulator] firestore already wired: $e');
  }

  // Realtime Database (synchronous) — wire before presence grabs a ref.
  try {
    FirebaseDatabase.instance.useDatabaseEmulator(host, _databasePort);
  } catch (e) {
    debugPrint('[emulator] database already wired: $e');
  }

  // Storage (synchronous).
  try {
    FirebaseStorage.instance.useStorageEmulator(host, _storagePort);
  } catch (e) {
    debugPrint('[emulator] storage already wired: $e');
  }

  // Auth (async) — must be awaited before any sign-in call.
  try {
    await FirebaseAuth.instance.useAuthEmulator(host, _authPort);
  } catch (e) {
    debugPrint('[emulator] auth already wired: $e');
  }
}
