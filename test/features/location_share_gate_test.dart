import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/nearby/location_share_gate.dart';

/// Coverage for H17 — turning off location sharing had no effect until restart.
///
/// Nearby gated the location upload on `AuthProvider.currentUser.settings`, but
/// Settings writes through UserProvider, and AuthProvider.currentUser never
/// refreshes (and UserProvider's copy gets clobbered back to the stale
/// AuthProvider value on the next auth notify). So `shareLocation: false` was
/// invisible here and coordinates kept uploading.
///
/// The gate now reads the AUTHORITATIVE settings straight from Firestore at the
/// moment of the upload decision, sidestepping every in-memory stale copy.
void main() {
  late FakeFirebaseFirestore db;
  const uid = 'me';

  setUp(() => db = FakeFirebaseFirestore());

  Future<Map<String, dynamic>?> userDoc() async =>
      (await db.collection('users').doc(uid).get()).data();

  Future<void> setSettings(Map<String, dynamic> settings) =>
      db.collection('users').doc(uid).set({'settings': settings});

  group('persistLocationIfAllowed', () {
    test('does NOT write location when sharing is turned off', () async {
      await setSettings({'shareLocation': false});
      final wrote = await persistLocationIfAllowed(db, uid: uid, lat: 40.71, lng: -74.0);
      expect(wrote, isFalse);
      final d = await userDoc();
      expect(d!.containsKey('lat'), isFalse);
      expect(d.containsKey('lng'), isFalse);
    });

    test('reads the CURRENT setting, not a stale cached one', () async {
      // Simulate the exact bug: an earlier state had sharing on, then the user
      // turned it off. The authoritative doc is what counts.
      await setSettings({'shareLocation': true});
      await setSettings({'shareLocation': false});
      final wrote = await persistLocationIfAllowed(db, uid: uid, lat: 1, lng: 2);
      expect(wrote, isFalse);
      expect((await userDoc())!.containsKey('lat'), isFalse);
    });

    test('writes when sharing is on (default) — exact coord when approx off', () async {
      await setSettings({'shareLocation': true, 'approxLocationOnly': false});
      final wrote = await persistLocationIfAllowed(db, uid: uid, lat: 40.71283, lng: -74.00601);
      expect(wrote, isTrue);
      final d = await userDoc();
      expect(d!['lat'], 40.71283);
      expect(d['lng'], -74.00601);
    });

    test('fuzzes the coordinate when approxLocationOnly is on', () async {
      await setSettings({'shareLocation': true, 'approxLocationOnly': true});
      await persistLocationIfAllowed(db, uid: uid, lat: 40.71283, lng: -74.00601);
      final d = await userDoc();
      // Rounded to 2 dp (~1.1km) by LocationService.fuzzCoordinate.
      expect(d!['lat'], 40.71);
      expect(d['lng'], -74.01);
    });

    test('defaults to sharing (fuzzed) when settings are absent entirely', () async {
      // A pre-migration account with no settings map keeps today's defaults:
      // shareLocation on, approxLocationOnly on.
      await db.collection('users').doc(uid).set({'name': 'me'});
      final wrote = await persistLocationIfAllowed(db, uid: uid, lat: 40.71283, lng: -74.00601);
      expect(wrote, isTrue);
      expect((await userDoc())!['lat'], 40.71);
    });
  });
}
