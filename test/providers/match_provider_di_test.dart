import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/providers/real_providers.dart';

/// Provider-level coverage of the match deck (H14/H15), unlocked by DI.
///
/// loadCandidates composes several Firestore reads — profile, blocked-in-both-
/// directions, already-acted-on, and the candidate pool — then filters. That
/// composition could only be "verified by reading"; here it runs for real.
void main() {
  late FakeFirebaseFirestore db;
  const me = 'me';

  MatchProvider newProvider() => MatchProvider(
        db: db,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: me)),
      );

  Future<void> seedUser(String uid, {String role = 'user'}) =>
      db.collection('users').doc(uid).set({'name': uid, 'role': role});

  setUp(() async {
    db = FakeFirebaseFirestore();
    await seedUser(me);
  });

  Future<List<String>> candidateIds() async {
    final p = newProvider();
    await p.loadCandidates();
    return p.candidates.map((u) => u.uid).toList();
  }

  test('shows other users and never myself', () async {
    await seedUser('alice');
    await seedUser('bob');
    final ids = await candidateIds();
    expect(ids, containsAll(['alice', 'bob']));
    expect(ids, isNot(contains(me)));
  });

  test('excludes a user I blocked', () async {
    await seedUser('alice');
    await seedUser('bob');
    await db.doc('users/$me/blocked/bob')
        .set({'blockedAt': DateTime(2026), 'blockedUid': 'bob'});
    expect(await candidateIds(), isNot(contains('bob')));
  });

  test('excludes a user who blocked me', () async {
    await seedUser('alice');
    await seedUser('carol');
    await db.doc('users/carol/blocked/$me')
        .set({'blockedAt': DateTime(2026), 'blockedUid': me});
    expect(await candidateIds(), isNot(contains('carol')));
  });

  test('excludes someone I already passed (no repeats — H15)', () async {
    await seedUser('alice');
    await seedUser('dave');
    await db.collection('matches').doc('${me}__dave').set({
      'userA': me, 'userB': 'dave', 'status': 'passed',
      'matchType': 'none', 'likedAt': DateTime(2026),
    });
    expect(await candidateIds(), isNot(contains('dave')));
  });

  test('excludes someone I already liked', () async {
    await seedUser('alice');
    await seedUser('erin');
    await db.collection('matches').doc('${me}__erin').set({
      'userA': me, 'userB': 'erin', 'status': 'pending',
      'matchType': 'buddy', 'likedAt': DateTime(2026),
    });
    expect(await candidateIds(), isNot(contains('erin')));
  });

  test('KEEPS someone whose like of me is still pending', () async {
    // They liked me; I must still see them to match back.
    await seedUser('frank');
    await db.collection('matches').doc('frank__$me').set({
      'userA': 'frank', 'userB': me, 'status': 'pending',
      'matchType': 'buddy', 'likedAt': DateTime(2026),
    });
    expect(await candidateIds(), contains('frank'));
  });

  test('business accounts are not candidates', () async {
    await seedUser('alice');
    await seedUser('acme', role: 'business');
    expect(await candidateIds(), isNot(contains('acme')));
  });
}
