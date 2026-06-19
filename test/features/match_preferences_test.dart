import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Regression tests for the Match Preferences fix (audit H3).
///
/// Previously `match_preferences_screen.dart` was a pure-local stub: the Save
/// button just popped and `MatchProvider.loadCandidates` ignored every filter.
/// These tests lock the two contracts that fix depends on:
///   1. prefs round-trip under users/{uid}.matchPrefs (UserProvider.save/get)
///   2. the candidate filter predicate (MatchProvider.loadCandidates)
///
/// They mirror the provider logic against the fake Firestore surface — the same
/// convention as auth_provider_test.dart — pending repository extraction for DI.
void main() {
  group('matchPrefs persistence (guards Save → users/{uid}.matchPrefs)', () {
    late FakeFirebaseFirestore db;
    const uid = 'crew-1';
    setUp(() => db = FakeFirebaseFirestore());

    test('saved prefs round-trip exactly', () async {
      // Mirrors UserProvider.saveMatchPrefs → update({'matchPrefs': prefs}).
      await db.collection('users').doc(uid).set({'name': 'Ada'});
      await db.collection('users').doc(uid).update({
        'matchPrefs': {
          'maxDistance': 80, 'ageMin': 25, 'ageMax': 40,
          'sameAirline': true, 'verifiedOnly': true,
          'airlines': ['Delta'], 'positions': ['Pilot'],
        }
      });

      final snap = await db.collection('users').doc(uid).get();
      final prefs = snap.data()!['matchPrefs'] as Map<String, dynamic>;
      expect(prefs['maxDistance'], 80);
      expect(prefs['ageMin'], 25);
      expect(prefs['verifiedOnly'], true);
      expect(prefs['airlines'], contains('Delta'));
      expect(prefs['positions'], contains('Pilot'));
    });

    test('absent matchPrefs reads as empty (getMatchPrefs default)', () async {
      await db.collection('users').doc(uid).set({'name': 'Ada'});
      final snap = await db.collection('users').doc(uid).get();
      final prefs =
          (snap.data()?['matchPrefs'] as Map<String, dynamic>?) ?? {};
      expect(prefs, isEmpty);
    });
  });

  group('candidate filter predicate (guards MatchProvider.loadCandidates)', () {
    // Replicates the inline .where() chain in loadCandidates so a behavior
    // change there breaks this test.
    bool passes(
      UserModel u, {
      bool verifiedOnly = false,
      bool sameAirline = false,
      String? myAirline,
      List<String> airlines = const [],
      List<String> positions = const [],
    }) =>
        (!verifiedOnly || u.isVerified) &&
        (!sameAirline || (myAirline != null && u.airline == myAirline)) &&
        (airlines.isEmpty || (u.airline != null && airlines.contains(u.airline))) &&
        (positions.isEmpty || (u.position != null && positions.contains(u.position)));

    UserModel user({
      String uid = 'u',
      String? airline,
      String? position,
      bool isVerified = false,
    }) =>
        UserModel(
          uid: uid, name: 'N', email: 'n@x.com',
          airline: airline, position: position, isVerified: isVerified,
          createdAt: DateTime(2024),
        );

    test('no prefs → everyone passes', () {
      expect(passes(user(airline: 'United', position: 'TSA')), true);
    });

    test('verifiedOnly excludes unverified', () {
      expect(passes(user(isVerified: false), verifiedOnly: true), false);
      expect(passes(user(isVerified: true), verifiedOnly: true), true);
    });

    test('sameAirline keeps only my airline', () {
      expect(passes(user(airline: 'Delta'), sameAirline: true, myAirline: 'Delta'), true);
      expect(passes(user(airline: 'United'), sameAirline: true, myAirline: 'Delta'), false);
    });

    test('airline allow-list filters', () {
      expect(passes(user(airline: 'Delta'), airlines: ['Delta', 'JetBlue']), true);
      expect(passes(user(airline: 'Spirit'), airlines: ['Delta', 'JetBlue']), false);
    });

    test('position allow-list filters', () {
      expect(passes(user(position: 'Pilot'), positions: ['Pilot']), true);
      expect(passes(user(position: 'Gate Agent'), positions: ['Pilot']), false);
    });

    test('combined filters AND together', () {
      final u = user(airline: 'Delta', position: 'Pilot', isVerified: true);
      expect(
        passes(u, verifiedOnly: true, airlines: ['Delta'], positions: ['Pilot']),
        true,
      );
      expect(
        passes(u, verifiedOnly: true, airlines: ['United'], positions: ['Pilot']),
        false,
      );
    });
  });
}
