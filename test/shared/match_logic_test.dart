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
}
