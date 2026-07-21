import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/utils/account_deletion.dart';

/// Coverage for B3 — account deletion completeness.
///
/// The shipped implementation deleted `users/{uid}/trips`, a subcollection that
/// does not exist: trips live in the TOP-LEVEL `trips` collection keyed by
/// `userId`. Trip history, SafeCheck check-ins (which carry lat/lng),
/// notifications and stories all survived "delete my account", while the
/// in-app dialog promised otherwise.
void main() {
  late FakeFirebaseFirestore db;
  const uid = 'doomed';
  const other = 'bystander';

  setUp(() async {
    db = FakeFirebaseFirestore();

    await db.doc('users/$uid').set({'name': 'Doomed', 'role': 'user'});
    await db.doc('users/$other').set({'name': 'Bystander', 'role': 'user'});

    // First-party subcollections
    await db.doc('users/$uid/savedPosts/p9').set({'savedAt': DateTime(2026)});
    await db.doc('users/$uid/blocked/$other').set({'at': DateTime(2026)});
    await db.doc('users/$uid/following/$other').set({'at': DateTime(2026)});
    await db.doc('users/$uid/followers/$other').set({'at': DateTime(2026)});
    await db.doc('users/$uid/private/data').set({'fcmToken': 'tok'});

    // Top-level, user-keyed collections
    await db.collection('trips').add({'userId': uid, 'destination': 'Tokyo'});
    await db.collection('trips').add({'userId': other, 'destination': 'Oslo'});
    await db.collection('safeChecks').add({'userId': uid, 'lat': 1.0, 'lng': 2.0});
    await db.collection('safeChecks').add({'userId': other, 'lat': 3.0, 'lng': 4.0});
    await db.collection('notifications').add({'userId': uid, 'type': 'like'});
    await db.collection('notifications').add({'userId': other, 'type': 'like'});
    await db.doc('stories/$uid').set({'items': []});
    await db.doc('stories/$other').set({'items': []});

    // Posts are anonymised, not destroyed (other users' replies hang off them)
    await db.collection('posts').add({
      'authorId': uid, 'authorName': 'Doomed', 'authorPhotoUrl': 'x.png',
      'caption': 'mine', 'audience': 'Everyone',
    });
    await db.collection('posts').add({
      'authorId': other, 'authorName': 'Bystander', 'caption': 'theirs',
      'audience': 'Everyone',
    });
  });

  Future<int> countWhere(String col, String uidValue) async {
    final snap = await db.collection(col).where('userId', isEqualTo: uidValue).get();
    return snap.docs.length;
  }

  group('purgeUserData', () {
    test('removes trips from the top-level collection, not a subcollection',
        () async {
      await purgeUserData(db, uid);

      expect(await countWhere('trips', uid), 0);
    });

    test('removes SafeCheck check-ins, which carry precise coordinates',
        () async {
      await purgeUserData(db, uid);

      expect(await countWhere('safeChecks', uid), 0);
    });

    test('removes notifications addressed to the user', () async {
      await purgeUserData(db, uid);

      expect(await countWhere('notifications', uid), 0);
    });

    test('removes the user story document', () async {
      await purgeUserData(db, uid);

      expect((await db.doc('stories/$uid').get()).exists, isFalse);
    });

    test('removes every first-party subcollection', () async {
      await purgeUserData(db, uid);

      for (final sub in ['savedPosts', 'blocked', 'following', 'followers', 'private']) {
        final snap = await db.collection('users/$uid/$sub').get();
        expect(snap.docs, isEmpty, reason: '$sub survived deletion');
      }
    });

    test('removes the user document itself', () async {
      await purgeUserData(db, uid);

      expect((await db.doc('users/$uid').get()).exists, isFalse);
    });

    test('anonymises the user\'s posts rather than deleting them', () async {
      await purgeUserData(db, uid);

      final snap =
          await db.collection('posts').where('authorId', isEqualTo: uid).get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.first.data()['authorName'], '[deleted user]');
      expect(snap.docs.first.data()['authorPhotoUrl'], isNull);
      expect(snap.docs.first.data()['isDeleted'], isTrue);
    });

    test('touches nothing belonging to another user', () async {
      await purgeUserData(db, uid);

      expect((await db.doc('users/$other').get()).exists, isTrue);
      expect((await db.doc('stories/$other').get()).exists, isTrue);
      expect(await countWhere('trips', other), 1);
      expect(await countWhere('safeChecks', other), 1);
      expect(await countWhere('notifications', other), 1);

      final theirPost =
          await db.collection('posts').where('authorId', isEqualTo: other).get();
      expect(theirPost.docs.first.data()['authorName'], 'Bystander');
    });

    test('removes the mirrored follow entry on profiles the user followed',
        () async {
      // Following is stored twice: users/{me}/following/{them} and
      // users/{them}/followers/{me}. Erasing only the first leaves the user
      // counted as a follower on every profile they followed.
      await db.doc('users/$other/followers/$uid').set({'at': DateTime(2026)});

      await purgeUserData(db, uid);

      expect((await db.doc('users/$other/followers/$uid').get()).exists, isFalse);
    });

    test('is safe to re-run after a partial failure', () async {
      await purgeUserData(db, uid);
      await purgeUserData(db, uid); // must not throw

      expect((await db.doc('users/$uid').get()).exists, isFalse);
    });
  });
}
