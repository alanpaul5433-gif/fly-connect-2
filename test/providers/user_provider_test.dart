import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/features/nearby/nearby_users_screen.dart'
    show shouldShareLocation, resolveCoordinateToPersist;

/// Tests for UserProvider.saveSettings — the persistence fix for H-1
/// (Settings toggles were setState-only and never survived a re-open).
/// Same caveat as post_provider_test: our provider uses singleton Firestore,
/// so we validate the data-layer contract directly against fake Firestore.
void main() {
  late FakeFirebaseFirestore db;
  const uid = 'test-user-123';

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  group('Settings persistence', () {
    test('saving settings writes the whole map to users/{uid}.settings', () async {
      await db.collection('users').doc(uid).set({'name': 'Alex'});

      // Mirrors UserProvider.saveSettings -> updateProfile(uid, {'settings': settings}).
      await db.collection('users').doc(uid).update({
        'settings': {
          'showOnNearby': false,
          'showAirline': true,
          'nearbyVisibility': 'friends',
        },
      });

      final doc = await db.collection('users').doc(uid).get();
      final settings = doc.data()!['settings'] as Map<String, dynamic>;
      expect(settings['showOnNearby'], false);
      expect(settings['nearbyVisibility'], 'friends');
    });

    test('a settings update does not clobber unrelated profile fields', () async {
      await db.collection('users').doc(uid).set({'name': 'Alex', 'bio': 'Pilot'});
      await db.collection('users').doc(uid).update({
        'settings': {'pushLikes': false},
      });

      final doc = await db.collection('users').doc(uid).get();
      expect(doc.data()!['name'], 'Alex');
      expect(doc.data()!['bio'], 'Pilot');
    });
  });

  group('UserModel.settings default', () {
    test('fromMap defaults to an empty map when settings is missing', () {
      final user = UserModel.fromMap({
        'name': 'Alex', 'email': 'alex@flyconnect.co', 'createdAt': DateTime.now(),
      }, uid);
      expect(user.settings, isEmpty);
    });

    test('fromMap round-trips a populated settings map', () {
      final user = UserModel.fromMap({
        'name': 'Alex', 'email': 'alex@flyconnect.co', 'createdAt': DateTime.now(),
        'settings': {'profilePublic': false, 'nearbyVisibility': 'verified'},
      }, uid);
      expect(user.settings['profilePublic'], false);
      expect(user.settings['nearbyVisibility'], 'verified');
    });

    test('toMap includes settings for a round trip through Firestore', () {
      final user = UserModel(
        uid: uid, name: 'Alex', email: 'alex@flyconnect.co', createdAt: DateTime.now(),
        settings: const {'showOnNearby': false},
      );
      expect(user.toMap()['settings'], {'showOnNearby': false});
    });
  });

  group('H-2: PII lives in the owner-only private subdoc', () {
    test('writing to users/{uid}/private/data does not touch the main doc', () async {
      await db.collection('users').doc(uid).set({'name': 'Alex'});

      // Mirrors AuthProvider.signup()'s split write.
      await db.collection('users').doc(uid).collection('private').doc('data').set({
        'email': 'alex@flyconnect.co', 'phone': '+15551234567',
      });

      final mainDoc = await db.collection('users').doc(uid).get();
      expect(mainDoc.data()!.containsKey('email'), false);
      expect(mainDoc.data()!.containsKey('phone'), false);

      final privateDoc = await db.collection('users').doc(uid)
          .collection('private').doc('data').get();
      expect(privateDoc.data()!['email'], 'alex@flyconnect.co');
      expect(privateDoc.data()!['phone'], '+15551234567');
    });

    test('a main-doc-only fetch (viewing another user) never exposes PII', () async {
      // Once email/phone/fcmToken are absent from the main doc, fetching
      // someone else's doc (UserProvider.fetchUser) simply can't see them —
      // no code needs to filter anything, it's safe by omission.
      await db.collection('users').doc('other-user').set({'name': 'Sam'});
      await db.collection('users').doc('other-user').collection('private').doc('data')
          .set({'email': 'sam@flyconnect.co'});

      final doc = await db.collection('users').doc('other-user').get();
      final user = UserModel.fromFirestore(doc);
      expect(user.email, '');
      expect(user.phone, null);
    });

    test('merging main doc + private/data reproduces the full self UserModel', () async {
      // Mirrors AuthProvider._fetchSelfWithPrivate's merge.
      await db.collection('users').doc(uid).set({'name': 'Alex', 'bio': 'Pilot'});
      await db.collection('users').doc(uid).collection('private').doc('data').set({
        'email': 'alex@flyconnect.co', 'phone': '+15551234567', 'fcmToken': 'tok123',
      });

      final mainDoc = await db.collection('users').doc(uid).get();
      final data = Map<String, dynamic>.from(mainDoc.data()!);
      final privateDoc = await db.collection('users').doc(uid)
          .collection('private').doc('data').get();
      data.addAll(privateDoc.data()!);
      final user = UserModel.fromMap(data, uid);

      expect(user.name, 'Alex');
      expect(user.email, 'alex@flyconnect.co');
      expect(user.phone, '+15551234567');
      expect(user.fcmToken, 'tok123');
    });
  });

  group('Nearby enforcement contract', () {
    test('a user with showOnNearby=false is excluded from the nearby query results', () async {
      await db.collection('users').doc('visible-user').set({
        'role': 'user', 'name': 'Visible', 'settings': {'showOnNearby': true},
      });
      await db.collection('users').doc('hidden-user').set({
        'role': 'user', 'name': 'Hidden', 'settings': {'showOnNearby': false},
      });

      final snap = await db.collection('users').where('role', isEqualTo: 'user').get();
      // Mirrors the filter added to NearbyUsersScreen._loadNearbyUsers.
      final visible = snap.docs.where((d) {
        final settings = d.data()['settings'] as Map<String, dynamic>? ?? {};
        return settings['showOnNearby'] != false;
      }).map((d) => d.id).toList();

      expect(visible, contains('visible-user'));
      expect(visible, isNot(contains('hidden-user')));
    });

    test('a user with no stored lat/lng is excluded even if showOnNearby is true', () async {
      // Mirrors the H-4 filter: a user who's never shared a real position
      // has nothing honest to show, so they're skipped rather than given a
      // fake distance.
      await db.collection('users').doc('has-location').set({
        'role': 'user', 'name': 'Has Location', 'lat': 40.71, 'lng': -74.0,
      });
      await db.collection('users').doc('no-location').set({
        'role': 'user', 'name': 'No Location',
      });

      final snap = await db.collection('users').where('role', isEqualTo: 'user').get();
      final withLocation = snap.docs.where((d) {
        final data = d.data();
        return data['lat'] != null && data['lng'] != null;
      }).map((d) => d.id).toList();

      expect(withLocation, contains('has-location'));
      expect(withLocation, isNot(contains('no-location')));
    });
  });

  group('UserModel.lat/lng', () {
    test('fromMap round-trips a stored position', () {
      final user = UserModel.fromMap({
        'name': 'Alex', 'email': 'alex@flyconnect.co', 'createdAt': DateTime.now(),
        'lat': 40.7128, 'lng': -74.0060,
      }, uid);
      expect(user.lat, 40.7128);
      expect(user.lng, -74.0060);
    });

    test('fromMap defaults lat/lng to null when never shared', () {
      final user = UserModel.fromMap({
        'name': 'Alex', 'email': 'alex@flyconnect.co', 'createdAt': DateTime.now(),
      }, uid);
      expect(user.lat, null);
      expect(user.lng, null);
    });

    test('toMap includes lat/lng for a round trip through Firestore', () {
      final user = UserModel(
        uid: uid, name: 'Alex', email: 'alex@flyconnect.co', createdAt: DateTime.now(),
        lat: 40.7128, lng: -74.0060,
      );
      expect(user.toMap()['lat'], 40.7128);
      expect(user.toMap()['lng'], -74.0060);
    });
  });

  group('H-4: UserProvider.updateMyLocation write shape', () {
    test('writes lat/lng onto the main user doc without touching other fields', () async {
      await db.collection('users').doc(uid).set({'name': 'Alex', 'bio': 'Pilot'});

      // Mirrors UserProvider.updateMyLocation -> updateProfile(uid, {'lat':..,'lng':..}).
      await db.collection('users').doc(uid).update({'lat': 40.7128, 'lng': -74.0060});

      final doc = await db.collection('users').doc(uid).get();
      expect(doc.data()!['lat'], 40.7128);
      expect(doc.data()!['lng'], -74.0060);
      expect(doc.data()!['name'], 'Alex');
      expect(doc.data()!['bio'], 'Pilot');
    });
  });

  group('H-4: location privacy gating (nearby_users_screen helpers)', () {
    test('shouldShareLocation defaults to true when the setting is absent', () {
      expect(shouldShareLocation({}), true);
    });

    test('shouldShareLocation is false only when explicitly turned off', () {
      expect(shouldShareLocation({'shareLocation': false}), false);
      expect(shouldShareLocation({'shareLocation': true}), true);
    });

    test('resolveCoordinateToPersist fuzzes by default (approxLocationOnly defaults on)', () {
      final (lat, lng) = resolveCoordinateToPersist(40.71283, -74.00601, {});
      expect(lat, 40.71);
      expect(lng, -74.01);
    });

    test('resolveCoordinateToPersist passes the exact coordinate through when disabled', () {
      final (lat, lng) = resolveCoordinateToPersist(
          40.71283, -74.00601, {'approxLocationOnly': false});
      expect(lat, 40.71283);
      expect(lng, -74.00601);
    });
  });
}
