import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake [FirebasePlatform] that answers `app()`/`apps`/`initializeApp()`
/// synchronously with a single in-memory `[DEFAULT]` app, never touching a
/// platform channel.
class _FakeFirebasePlatform extends FirebasePlatform {
  _FakeFirebasePlatform() : super();

  final FirebaseAppPlatform _app = FirebaseAppPlatform(
    defaultFirebaseAppName,
    const FirebaseOptions(
      apiKey: 'fake-api-key',
      appId: '1:1234567890:ios:abcdef1234567890',
      messagingSenderId: '1234567890',
      projectId: 'flyconnect-test',
    ),
  );

  @override
  List<FirebaseAppPlatform> get apps => [_app];

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _app;
}

/// Registers a fake `[DEFAULT]` Firebase app so that synchronous
/// `Firebase.app()` / `FirebaseFirestore.instance` lookups succeed inside a
/// widget test, without needing a real native Firebase SDK, emulator, or
/// platform-channel mocking.
///
/// Needed because some screens (e.g. `EventManagementScreen`) call
/// `FirebaseFirestore.instance` directly during `initState`. Without a
/// registered app that getter throws `[core/no-app]`, which aborts
/// `pumpWidget` before the tree is even built.
///
/// Implementation note: firebase_core's pigeon-based platform channel
/// (`FirebaseCoreHostApi`) can't be mocked with a plain
/// `setMockMethodCallHandler` in this SDK version — it uses a generated
/// binary codec, not `MethodChannel`. Instead this overrides
/// `Firebase.delegatePackingProperty` (an `@visibleForTesting` seam in
/// firebase_core) with an in-memory `FirebasePlatform`, which is the
/// supported way to fake Firebase app registration in tests.
///
/// This does NOT mock the cloud_firestore method channel. Empirically, an
/// actual `.get()`/`.set()` call after this does not throw — it hangs
/// forever (no reply ever arrives on the unmocked channel), so any UI that
/// depends on such a call resolving (e.g. a loading spinner driven by an
/// `await` on a direct `FirebaseFirestore.instance` read) will never settle.
/// Widget tests exercising a screen with that pattern must use bounded
/// `tester.pump(duration)` loops instead of `pumpAndSettle()`. This helper
/// only unblocks Firebase app *registration*, not Firestore reads/writes.
///
/// Call from `setUpAll()`, not `setUp()` — the fake app only needs to be
/// registered once per test-file isolate.
Future<void> setupFirebaseCoreMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Firebase.delegatePackingProperty = _FakeFirebasePlatform();
}
