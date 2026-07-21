import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/utils/match_logic.dart';

/// Coverage for H1 — "It's a Match!" fired on every single like.
///
/// The provider's mutual-like check was already correct; the screen simply
/// ignored it and showed the banner unconditionally:
///
///   await context.read<MatchProvider>().likeUser(...);
///   setState(() => _showMatchBanner = true);   // <- always
///
/// `likeUser` returned void, so the screen had nothing to branch on. These
/// tests pin the decision itself: a like is a match only when the other person
/// already liked you and that like is still pending.
void main() {
  late FakeFirebaseFirestore db;
  const me = 'me';
  const them = 'them';

  setUp(() => db = FakeFirebaseFirestore());

  Future<int> matchCount() async =>
      (await db.collection('matches').get()).docs.length;

  group('recordLike — no prior interest', () {
    test('is not a match when they have not liked me', () async {
      expect(await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy'),
          isFalse);
    });

    test('records my like as pending so they can match it later', () async {
      await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy');
      final docs = (await db.collection('matches').get()).docs;
      expect(docs, hasLength(1));
      expect(docs.first.data()['userA'], me);
      expect(docs.first.data()['userB'], them);
      expect(docs.first.data()['status'], 'pending');
      expect(docs.first.data()['matchType'], 'buddy');
    });
  });

  group('recordLike — they liked me first', () {
    setUp(() async {
      await db.collection('matches').add({
        'userA': them, 'userB': me, 'status': 'pending',
        'matchType': 'buddy', 'likedAt': DateTime(2026, 7, 1),
      });
    });

    test('is a match', () async {
      expect(await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy'),
          isTrue);
    });

    test('promotes the existing doc instead of creating a second one', () async {
      await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy');
      expect(await matchCount(), 1);
      final doc = (await db.collection('matches').get()).docs.first;
      expect(doc.data()['status'], 'matched');
      expect(doc.data()['matchedAt'], isNotNull);
    });
  });

  group('recordLike — states that must NOT count as a match', () {
    test('my own earlier like of them does not match me with myself', () async {
      // Direction matters: userA is the liker. A doc where I am userA is my
      // own pending like, not theirs, and must not promote.
      await db.collection('matches').add({
        'userA': me, 'userB': them, 'status': 'pending',
        'matchType': 'buddy', 'likedAt': DateTime(2026, 7, 1),
      });
      expect(await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy'),
          isFalse);
    });

    test('an already-matched pair does not re-fire the banner', () async {
      await db.collection('matches').add({
        'userA': them, 'userB': me, 'status': 'matched',
        'matchType': 'buddy', 'likedAt': DateTime(2026, 7, 1),
      });
      expect(await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy'),
          isFalse);
    });

    test('a third party liking me is not a match with this target', () async {
      await db.collection('matches').add({
        'userA': 'someone_else', 'userB': me, 'status': 'pending',
        'matchType': 'buddy', 'likedAt': DateTime(2026, 7, 1),
      });
      expect(await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy'),
          isFalse);
    });

    test('their like of a third party is not a match with me', () async {
      await db.collection('matches').add({
        'userA': them, 'userB': 'someone_else', 'status': 'pending',
        'matchType': 'buddy', 'likedAt': DateTime(2026, 7, 1),
      });
      expect(await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy'),
          isFalse);
    });
  });

  group('recordLike — idempotency (H15)', () {
    test('liking the same person twice leaves a single pending edge', () async {
      await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy');
      await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy');
      expect(await matchCount(), 1);
    });

    test('a like then a pass of the same person do not both persist', () async {
      // The old passUser add()ed a fresh doc every time, so a like followed
      // by a pass left two contradictory edges. One outgoing edge per pair.
      await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy');
      await recordPass(db, myUid: me, targetUid: them);
      expect(await matchCount(), 1);
      final doc = (await db.collection('matches').get()).docs.first;
      expect(doc.data()['status'], 'passed');
    });
  });

  group('recordPass', () {
    test('writes a single passed edge', () async {
      await recordPass(db, myUid: me, targetUid: them);
      final docs = (await db.collection('matches').get()).docs;
      expect(docs, hasLength(1));
      expect(docs.first.data()['status'], 'passed');
      expect(docs.first.data()['userA'], me);
      expect(docs.first.data()['userB'], them);
    });

    test('passing twice does not duplicate', () async {
      await recordPass(db, myUid: me, targetUid: them);
      await recordPass(db, myUid: me, targetUid: them);
      expect(await matchCount(), 1);
    });
  });

  group('fetchActedOnUids (H15)', () {
    test('is empty with no history', () async {
      expect(await fetchActedOnUids(db, me), isEmpty);
    });

    test('includes someone I passed', () async {
      await recordPass(db, myUid: me, targetUid: them);
      expect(await fetchActedOnUids(db, me), contains(them));
    });

    test('includes someone I liked (pending)', () async {
      await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy');
      expect(await fetchActedOnUids(db, me), contains(them));
    });

    test('includes someone I matched with via their incoming doc', () async {
      // The subtle case: they liked me first (their doc, userA=them), I liked
      // back, which PROMOTES their doc to matched. My own uid never appears as
      // userA there, so a naive `where userA == me` scan would miss them and
      // they would resurface in my deck after a reload.
      await db.collection('matches').add({
        'userA': them, 'userB': me, 'status': 'pending',
        'matchType': 'buddy', 'likedAt': DateTime(2026, 7, 1),
      });
      await recordLike(db, myUid: me, targetUid: them, matchType: 'buddy');
      expect(await fetchActedOnUids(db, me), contains(them));
    });

    test('does NOT include someone whose like of me is still pending', () async {
      // They liked me but I have not reciprocated. They must stay in my deck
      // so I can match back — excluding them would make matching impossible.
      await db.collection('matches').add({
        'userA': them, 'userB': me, 'status': 'pending',
        'matchType': 'buddy', 'likedAt': DateTime(2026, 7, 1),
      });
      expect(await fetchActedOnUids(db, me), isNot(contains(them)));
    });

    test('ignores edges between other people', () async {
      await db.collection('matches').add({
        'userA': 'a', 'userB': 'b', 'status': 'passed',
        'matchType': 'none', 'likedAt': DateTime(2026, 7, 1),
      });
      expect(await fetchActedOnUids(db, me), isEmpty);
    });
  });
}
