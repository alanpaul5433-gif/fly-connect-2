import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Tests for GroupProvider.deleteGroup/fetchMembers/removeMember/makeAdmin/
/// setChatEnabled/sendBroadcast.
///
/// GroupProvider hardcodes `FirebaseFirestore.instance` (no constructor DI),
/// so these tests can't instantiate the real provider — they seed a
/// FakeFirebaseFirestore and replay the exact read/write shape each method
/// performs, asserting against the fake db. Matches the existing convention
/// in test/providers/promotion_provider_test.dart.
///
/// NOTE: these tests cannot prove that the real (non-mock) provider methods
/// correctly omit notifyListeners() on their real-Firestore path — that
/// would require an actual GroupProvider instance, which isn't constructible
/// against a fake db without adding constructor DI (out of scope here).
void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  group('deleteGroup', () {
    test('removes the group document', () async {
      await db.collection('groups').doc('grp-1').set({'name': 'Crew Deals'});
      // Mirrors GroupProvider.deleteGroup.
      await db.collection('groups').doc('grp-1').delete();

      final doc = await db.collection('groups').doc('grp-1').get();
      expect(doc.exists, false);
    });
  });

  group('fetchMembers', () {
    // Mirrors GroupProvider.fetchMembers's chunk-at-30 + cap-at-60 loop.
    Future<List<Map<String, dynamic>>> fetchMembersMirror(
        List<String> memberUids) async {
      const memberFetchCap = 60;
      final capped = memberUids.take(memberFetchCap).toList();
      final results = <Map<String, dynamic>>[];
      for (var i = 0; i < capped.length; i += 30) {
        final chunk =
            capped.sublist(i, i + 30 > capped.length ? capped.length : i + 30);
        if (chunk.isEmpty) continue;
        final snap = await db
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        results.addAll(snap.docs.map((d) => d.data()));
      }
      return results;
    }

    test('returns empty list for empty input', () async {
      final result = await fetchMembersMirror(const []);
      expect(result, isEmpty);
    });

    test('chunks whereIn queries at 30 ids and merges results', () async {
      final uids = List.generate(45, (i) => 'user-$i');
      for (final uid in uids) {
        await db.collection('users').doc(uid).set({'name': uid});
      }

      final result = await fetchMembersMirror(uids);
      expect(result.length, 45);
    });

    test('caps total lookups at memberFetchCap (60)', () async {
      final uids = List.generate(100, (i) => 'user-$i');
      for (final uid in uids) {
        await db.collection('users').doc(uid).set({'name': uid});
      }

      final result = await fetchMembersMirror(uids);
      expect(result.length, 60);
    });
  });

  group('removeMember', () {
    test('removes uid from both members and admins, decrements memberCount',
        () async {
      await db.collection('groups').doc('grp-1').set({
        'members': ['user-1', 'user-2'],
        'admins': ['user-1'],
        'memberCount': 2,
      });

      // Mirrors GroupProvider.removeMember.
      await db.collection('groups').doc('grp-1').update({
        'members': FieldValue.arrayRemove(['user-1']),
        'admins': FieldValue.arrayRemove(['user-1']),
        'memberCount': FieldValue.increment(-1),
      });

      final doc = await db.collection('groups').doc('grp-1').get();
      final data = doc.data()!;
      expect(data['members'], ['user-2']);
      expect(data['admins'], isEmpty);
      expect(data['memberCount'], 1);
    });
  });

  group('makeAdmin', () {
    test('adds uid to admins via arrayUnion, no duplicate on repeat call',
        () async {
      await db.collection('groups').doc('grp-1').set({'admins': <String>[]});

      // Mirrors GroupProvider.makeAdmin, called twice.
      for (var i = 0; i < 2; i++) {
        await db.collection('groups').doc('grp-1').update({
          'admins': FieldValue.arrayUnion(['user-1']),
        });
      }

      final doc = await db.collection('groups').doc('grp-1').get();
      expect(doc.data()!['admins'], ['user-1']);
    });
  });

  group('setChatEnabled', () {
    test('writes the chatEnabled boolean field', () async {
      await db.collection('groups').doc('grp-1').set({'chatEnabled': true});

      // Mirrors GroupProvider.setChatEnabled.
      await db.collection('groups').doc('grp-1').update({'chatEnabled': false});

      final doc = await db.collection('groups').doc('grp-1').get();
      expect(doc.data()!['chatEnabled'], false);
    });
  });

  group('sendBroadcast', () {
    test('adds a document to groups/{id}/broadcasts with senderId/text/sentAt',
        () async {
      await db.collection('groups').doc('grp-1').set({'name': 'Crew Deals'});

      // Mirrors GroupProvider.sendBroadcast.
      await db.collection('groups').doc('grp-1').collection('broadcasts').add({
        'senderId': 'biz-1',
        'text': 'Layover meetup at gate 12!',
        'sentAt': FieldValue.serverTimestamp(),
      });

      final snap =
          await db.collection('groups').doc('grp-1').collection('broadcasts').get();
      expect(snap.docs.length, 1);
      final data = snap.docs.first.data();
      expect(data['senderId'], 'biz-1');
      expect(data['text'], 'Layover meetup at gate 12!');
      // fake_cloud_firestore resolves serverTimestamp() non-deterministically —
      // assert it's *a* Timestamp, not a specific value.
      expect(data['sentAt'], isA<Timestamp>());
    });
  });
}
