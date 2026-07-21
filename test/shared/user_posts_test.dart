import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/utils/user_posts.dart';

/// Coverage for H7 — profile header said "47 Posts", grid said "No posts yet".
///
/// The grid filtered `provider.feed` (the newest 25 posts GLOBALLY) by
/// authorId, so it showed a user's posts only if they happened to be in the
/// most recent 25 app-wide. For anyone but the most recent poster it rendered
/// the empty state directly beneath a non-zero count.
///
/// The replacement queries the user's posts directly, which drags in the B2
/// constraint: firestore.rules admits a posts query only when it is provably
/// limited to what the reader may see. Reading someone else's profile must
/// therefore pin `audience == 'Everyone'`, while reading your own must NOT —
/// you should still see your own "Only me" posts.
void main() {
  late FakeFirebaseFirestore db;
  const me = 'me';
  const them = 'them';

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('posts').add({
      'authorId': them, 'caption': 'their public',
      'audience': 'Everyone', 'createdAt': DateTime(2026, 7, 3),
    });
    await db.collection('posts').add({
      'authorId': them, 'caption': 'their private',
      'audience': 'Only me', 'createdAt': DateTime(2026, 7, 4),
    });
    await db.collection('posts').add({
      'authorId': me, 'caption': 'my public',
      'audience': 'Everyone', 'createdAt': DateTime(2026, 7, 1),
    });
    await db.collection('posts').add({
      'authorId': me, 'caption': 'my private',
      'audience': 'Only me', 'createdAt': DateTime(2026, 7, 2),
    });
  });

  Future<List<String>> captions(bool isSelf, String authorId) async {
    final snap =
        await userPostsQuery(db, authorId: authorId, isSelf: isSelf).get();
    return snap.docs.map((d) => d.data()['caption'] as String).toList();
  }

  group('viewing your own profile', () {
    test('includes your private posts', () async {
      expect(await captions(true, me), contains('my private'));
    });

    test('includes your public posts', () async {
      expect(await captions(true, me), contains('my public'));
    });

    test('never includes anyone else\'s posts', () async {
      final result = await captions(true, me);
      expect(result, isNot(contains('their public')));
      expect(result, isNot(contains('their private')));
    });

    test('is newest first', () async {
      expect(await captions(true, me), ['my private', 'my public']);
    });
  });

  group('viewing someone else\'s profile', () {
    test('includes their public posts', () async {
      expect(await captions(false, them), contains('their public'));
    });

    test('excludes their "Only me" posts', () async {
      // The whole point of B2. If this filter is dropped, firestore.rules
      // rejects the entire query rather than filtering the row out.
      expect(await captions(false, them), isNot(contains('their private')));
    });

    test('returns empty for a user with no public posts', () async {
      expect(await captions(false, 'nobody'), isEmpty);
    });
  });
}
