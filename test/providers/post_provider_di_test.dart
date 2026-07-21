import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/providers/real_providers.dart';

/// Provider-level coverage unlocked by the DI refactor.
///
/// PostProvider hard-coded FirebaseFirestore.instance, so its feed wiring — the
/// live query + client-side block filtering (H10) — could only be "verified by
/// reading". With db + auth injected it runs against FakeFirebaseFirestore and
/// a MockFirebaseAuth, exercising the real code path (isMock: false).
void main() {
  late FakeFirebaseFirestore db;
  const me = 'me';

  PostProvider newProvider() => PostProvider(
        db: db,
        auth: MockFirebaseAuth(
            signedIn: true, mockUser: MockUser(uid: me, displayName: 'Me')),
      );

  Future<void> seedPost(String id, String author, {String audience = 'Everyone'}) =>
      db.collection('posts').doc(id).set({
        'authorId': author, 'authorName': author, 'caption': id,
        'audience': audience, 'createdAt': DateTime(2026, 7, id.hashCode % 28 + 1),
        'likeCount': 0, 'commentCount': 0,
      });

  setUp(() => db = FakeFirebaseFirestore());

  Future<List<String>> feedAuthorsAfterListen(PostProvider p) async {
    await p.listenFeed();
    // Let the snapshot listener deliver at least once.
    for (var i = 0; i < 20 && p.feed.isEmpty && p.feedError == null; i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    return p.feed.map((post) => post.authorId).toList();
  }

  test('feed shows public posts from unblocked authors', () async {
    await seedPost('p1', 'alice');
    await seedPost('p2', 'bob');
    final p = newProvider();
    final authors = await feedAuthorsAfterListen(p);
    expect(authors, containsAll(['alice', 'bob']));
  });

  test('a post I blocked the author of is filtered out of the feed', () async {
    await seedPost('p1', 'alice');
    await seedPost('p2', 'bob');
    await db.doc('users/$me/blocked/bob')
        .set({'blockedAt': DateTime(2026, 7, 1), 'blockedUid': 'bob'});

    final p = newProvider();
    final authors = await feedAuthorsAfterListen(p);
    expect(authors, contains('alice'));
    expect(authors, isNot(contains('bob')),
        reason: 'H10: the feed must drop posts from a blocked author');
  });

  test('a post from someone who blocked ME is filtered out too', () async {
    await seedPost('p1', 'alice');
    await seedPost('p2', 'carol');
    // carol blocked me — her blocked/{me} doc names me via blockedUid.
    await db.doc('users/carol/blocked/$me')
        .set({'blockedAt': DateTime(2026, 7, 1), 'blockedUid': me});

    final p = newProvider();
    final authors = await feedAuthorsAfterListen(p);
    expect(authors, contains('alice'));
    expect(authors, isNot(contains('carol')));
  });

  test('blocking a visible author removes them live, without a re-query', () async {
    await seedPost('p1', 'alice');
    await seedPost('p2', 'bob');
    final p = newProvider();
    await feedAuthorsAfterListen(p);
    expect(p.feed.map((x) => x.authorId), contains('bob'));

    await p.blockUser('bob');
    expect(p.feed.map((x) => x.authorId), isNot(contains('bob')),
        reason: 'blockUser filters the in-memory feed immediately (H10)');
  });
}
