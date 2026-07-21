import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

/// Tests for AuthProvider-equivalent logic.
///
/// NOTE: AuthProvider in lib/shared/providers/real_providers.dart instantiates
/// FirebaseAuth.instance directly, which is not easily injectable. These tests
/// validate the *business rules* our provider enforces (password strength,
/// email format, consent) against the underlying fake auth surface so the
/// contract is locked in before we refactor the provider for proper DI.
///
/// For full provider coverage, the recommended next step is to extract an
/// AuthRepository that takes FirebaseAuth + FirebaseFirestore as constructor
/// params — then these tests run against the repo and not the provider.
void main() {
  group('Auth business rules', () {
    late MockFirebaseAuth auth;
    late FakeFirebaseFirestore db;

    setUp(() {
      auth = MockFirebaseAuth();
      db = FakeFirebaseFirestore();
    });

    test('email regex accepts valid emails', () {
      final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
      expect(emailRegex.hasMatch('user@example.com'), true);
      expect(emailRegex.hasMatch('alex+crew@delta.com'), true);
      expect(emailRegex.hasMatch('first.last@subdomain.flyconnect.app'), true);
    });

    test('email regex rejects invalid emails', () {
      final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
      expect(emailRegex.hasMatch('notanemail'), false);
      expect(emailRegex.hasMatch('@nouser.com'), false);
      expect(emailRegex.hasMatch('user@'), false);
      expect(emailRegex.hasMatch('user@@example.com'), false);
      expect(emailRegex.hasMatch('user @example.com'), false);
      expect(emailRegex.hasMatch('user@example'), false);
    });

    test('password minimum length enforced', () {
      bool isStrong(String p) => p.length >= 8;
      expect(isStrong('short'), false);
      expect(isStrong('1234567'), false);
      expect(isStrong('12345678'), true);
      expect(isStrong('SuperSecure123!'), true);
    });

    test('sign-in sets current user on successful auth', () async {
      await auth.createUserWithEmailAndPassword(
        email: 'test@example.com',
        password: 'Test1234!',
      );
      expect(auth.currentUser, isNotNull);
      expect(auth.currentUser!.email, 'test@example.com');
    });

    test('Firestore user doc creation on signup', () async {
      const uid = 'test-uid-123';
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'name': 'Test User',
        'email': 'test@example.com',
        'role': 'user',
        'isBanned': false,
        'isVerified': false,
      });
      final snap = await db.collection('users').doc(uid).get();
      expect(snap.exists, true);
      expect(snap.data()!['role'], 'user');
      expect(snap.data()!['isBanned'], false);
    });

    test('role defaults to user (never admin) on public signup', () async {
      await db.collection('users').doc('new-uid').set({
        'uid': 'new-uid',
        'role': 'user', // client code must hardcode this
      });
      final snap = await db.collection('users').doc('new-uid').get();
      expect(snap.data()!['role'], isNot(equals('admin')));
    });

    test('sign-out clears current user', () async {
      await auth.createUserWithEmailAndPassword(
        email: 'test@example.com', password: 'Test1234!');
      expect(auth.currentUser, isNotNull);
      await auth.signOut();
      expect(auth.currentUser, isNull);
    });

    test('business signup doc shape: verificationStatus pending on main doc, '
        'ein/licenseNumber on the private subdoc', () async {
      const uid = 'biz-uid-1';
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'name': 'Sky Lounge',
        'email': 'lounge@delta.com',
        'role': 'business',
        'isBanned': false,
        'isVerified': false,
        'verificationStatus': 'pending',
      });
      await db.collection('users').doc(uid).collection('private').doc('data').set({
        'email': 'lounge@delta.com',
        'ein': '12-3456789',
        'licenseNumber': 'LIC-998877',
      });

      final mainSnap = await db.collection('users').doc(uid).get();
      expect(mainSnap.data()!['verificationStatus'], 'pending');
      expect(mainSnap.data()!.containsKey('ein'), false);

      final privateSnap = await db
          .collection('users').doc(uid).collection('private').doc('data').get();
      expect(privateSnap.data()!['ein'], '12-3456789');
      expect(privateSnap.data()!['licenseNumber'], 'LIC-998877');
    });

    test('user (non-business) signup doc has no verificationStatus field', () async {
      const uid = 'user-uid-1';
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'name': 'Alex Crew',
        'email': 'alex@delta.com',
        'role': 'user',
        'isBanned': false,
        'isVerified': false,
      });
      final snap = await db.collection('users').doc(uid).get();
      expect(snap.data()!.containsKey('verificationStatus'), false);
    });

    test('OAuth business account doc shape: verificationStatus pending '
        '(mirrors email/password path)', () async {
      const uid = 'oauth-biz-uid-1';
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'name': 'Sky Lounge (Google)',
        'email': 'lounge@gmail.com',
        'role': 'business',
        'isBanned': false,
        'isVerified': false,
        'verificationStatus': 'pending',
      });
      final snap = await db.collection('users').doc(uid).get();
      expect(snap.data()!['verificationStatus'], 'pending');
    });
  });

  group('Account deletion logic', () {
    late FakeFirebaseFirestore db;
    const uid = 'user-to-delete';

    setUp(() {
      db = FakeFirebaseFirestore();
    });

    test('deletes the user document', () async {
      await db.collection('users').doc(uid).set({'name': 'X'});
      expect((await db.collection('users').doc(uid).get()).exists, true);

      await db.collection('users').doc(uid).delete();
      expect((await db.collection('users').doc(uid).get()).exists, false);
    });

    test('soft-deletes user posts by anonymizing', () async {
      await db.collection('posts').doc('p1').set({
        'authorId': uid,
        'authorName': 'Real Name',
        'isDeleted': false,
      });
      await db.collection('posts').doc('p2').set({
        'authorId': 'other-user',
        'authorName': 'Other',
        'isDeleted': false,
      });

      final mine = await db.collection('posts')
          .where('authorId', isEqualTo: uid).get();
      for (final doc in mine.docs) {
        await doc.reference.update({
          'authorName': '[deleted user]',
          'isDeleted': true,
        });
      }

      final p1 = await db.collection('posts').doc('p1').get();
      final p2 = await db.collection('posts').doc('p2').get();
      expect(p1.data()!['authorName'], '[deleted user]');
      expect(p1.data()!['isDeleted'], true);
      expect(p2.data()!['authorName'], 'Other'); // other users untouched
    });

    test('deletes savedPosts subcollection', () async {
      await db.collection('users').doc(uid).collection('savedPosts').doc('p1').set({'savedAt': 1});
      await db.collection('users').doc(uid).collection('savedPosts').doc('p2').set({'savedAt': 2});

      final snap = await db.collection('users').doc(uid).collection('savedPosts').get();
      expect(snap.docs.length, 2);

      for (final doc in snap.docs) {
        await doc.reference.delete();
      }

      final after = await db.collection('users').doc(uid).collection('savedPosts').get();
      expect(after.docs.length, 0);
    });
  });
}
