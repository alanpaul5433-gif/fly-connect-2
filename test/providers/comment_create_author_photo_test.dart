import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/providers/real_providers.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Regression for the comment half of the "avatars show a letter-initial"
/// bug. Comments are denormalized exactly like posts — `post_details_screen`
/// renders `CachedAvatar(url: c.authorPhotoUrl)` — but `addComment` wrote its
/// payload by hand and simply never included `authorPhotoUrl`, so every
/// comment fell back to the initial forever.
///
/// It also read the author name off FirebaseAuth's `displayName` rather than
/// the app profile, which is the source of truth, so a user with no
/// `displayName` was labelled the literal string 'User'.
class _FakeAuth extends AuthProvider {
  final UserModel? _user;
  _FakeAuth(this._user, FakeFirebaseFirestore db)
      : super(isMock: true, db: db, auth: MockFirebaseAuth());
  @override
  UserModel? get currentUser => _user;
}

void main() {
  late FakeFirebaseFirestore db;
  const me = 'me';
  const postId = 'post_1';
  const postAuthorId = 'someone_else';

  UserModel profile({String? photoUrl, String name = 'Nouman'}) => UserModel(
      uid: me, name: name, email: 'nouman@x.test',
      photoUrl: photoUrl, createdAt: DateTime(2026, 1, 1));

  PostProvider providerWith({
    UserModel? storedProfile,
    String? authPhotoURL,
    String? authDisplayName = 'Nouman',
  }) {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
          uid: me, displayName: authDisplayName, photoURL: authPhotoURL),
    );
    final p = PostProvider(db: db, auth: auth);
    if (storedProfile != null) p.updateAuth(_FakeAuth(storedProfile, db));
    return p;
  }

  Future<Map<String, dynamic>> onlyComment() async {
    final snap =
        await db.collection('posts').doc(postId).collection('comments').get();
    expect(snap.docs, hasLength(1));
    return snap.docs.first.data();
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    // addComment bumps posts/{postId}.commentCount, so the post must exist.
    await db.collection('posts').doc(postId).set({'commentCount': 0});
  });

  test('addComment denormalizes the author profile photo onto the comment doc',
      () async {
    const url = 'https://cdn.test/profile_photos/me/avatar.png';
    final p = providerWith(storedProfile: profile(photoUrl: url));

    await p.addComment(postId, 'nice shot', postAuthorId: postAuthorId);

    final data = await onlyComment();
    expect(data['authorPhotoUrl'], url,
        reason: 'post_details_screen reads authorPhotoUrl off the comment doc');
    expect(data['authorId'], me);
    expect(data['text'], 'nice shot');
  });

  test('addComment falls back to the FirebaseAuth photoURL when no app profile '
      'is available', () async {
    const url = 'https://cdn.test/auth/me.png';
    final p = providerWith(authPhotoURL: url); // no stored profile

    await p.addComment(postId, 'hi', postAuthorId: postAuthorId);

    expect((await onlyComment())['authorPhotoUrl'], url);
  });

  test('addComment prefers the app profile name over the FirebaseAuth '
      'displayName', () async {
    // The app profile is the source of truth for the display name; without it
    // a user whose Auth record has no displayName is labelled 'User'.
    final p = providerWith(
        storedProfile: profile(name: 'Real Name'), authDisplayName: null);

    await p.addComment(postId, 'hi', postAuthorId: postAuthorId);

    expect((await onlyComment())['authorName'], 'Real Name');
  });
}
