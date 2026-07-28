import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/providers/real_providers.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Regression for the "posts show a letter-initial instead of the author's
/// display picture" bug. The feed is denormalized — each post doc carries a
/// copy of the author's name and photo — but real `createPost` used to build
/// the PostModel WITHOUT `authorPhotoUrl`, so every real post was stored with
/// `authorPhotoUrl: null` and the feed fell back to the initial.
///
/// The author identity comes through an AuthProvider, so a tiny subclass with a
/// controllable currentUser (carrying a photoUrl) stands in for it — same
/// pattern as safe_check_provider_di_test.
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

  UserModel profile({String? photoUrl}) => UserModel(
        uid: me, name: 'Nouman', email: 'nouman@x.test',
        photoUrl: photoUrl, createdAt: DateTime(2026, 1, 1));

  PostProvider providerWith({UserModel? storedProfile, String? authPhotoURL}) {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: me, displayName: 'Nouman', photoURL: authPhotoURL),
    );
    final p = PostProvider(db: db, auth: auth);
    if (storedProfile != null) p.updateAuth(_FakeAuth(storedProfile, db));
    return p;
  }

  Future<Map<String, dynamic>> onlyPost() async {
    final snap = await db.collection('posts').get();
    expect(snap.docs, hasLength(1));
    return snap.docs.first.data();
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    // createPost bumps users/{uid}.postCount, so the author doc must exist.
    await db.collection('users').doc(me).set({'postCount': 0});
  });

  test('createPost denormalizes the author profile photo onto the post doc',
      () async {
    const url = 'https://cdn.test/profile_photos/me/avatar.png';
    final p = providerWith(storedProfile: profile(photoUrl: url));

    await p.createPost(caption: 'hello', audience: 'Everyone');

    final data = await onlyPost();
    expect(data['authorPhotoUrl'], url,
        reason: 'the feed reads authorPhotoUrl straight off the post doc');
    expect(data['authorName'], 'Nouman');
    expect(data['authorId'], me);
  });

  test('createPost falls back to the FirebaseAuth photoURL when no app profile '
      'is available', () async {
    const url = 'https://cdn.test/auth/me.png';
    final p = providerWith(authPhotoURL: url); // no stored profile

    await p.createPost(caption: 'hello');

    expect((await onlyPost())['authorPhotoUrl'], url);
  });

  test('the app profile photo wins, but a null one defers to FirebaseAuth',
      () async {
    const authUrl = 'https://cdn.test/auth/fallback.png';
    // Stored profile exists but has NO photo → precedence falls through to the
    // FirebaseAuth user's photoURL rather than writing null.
    final p = providerWith(
        storedProfile: profile(photoUrl: null), authPhotoURL: authUrl);

    await p.createPost(caption: 'hello');

    expect((await onlyPost())['authorPhotoUrl'], authUrl);
  });
}
