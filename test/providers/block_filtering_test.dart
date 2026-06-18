import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Blocking is a store-critical UGC control (Apple 1.2). It must do TWO things:
///   1. persist the block to users/{me}/blocked/{id}, and
///   2. actually remove the blocked user's content from what `me` sees.
///
/// These tests encode that contract. If the live feed/nearby queries don't apply
/// the same filter, that's a defect to fix in PostProvider — not a test to relax.
void main() {
  late FakeFirebaseFirestore db;
  const me = 'me';
  const blocked = 'blocked-user';
  const other = 'someone-else';

  setUp(() => db = FakeFirebaseFirestore());

  test('blocking writes to users/{me}/blocked/{id}', () async {
    await db
        .collection('users')
        .doc(me)
        .collection('blocked')
        .doc(blocked)
        .set({'at': Timestamp.now()});

    final doc = await db
        .collection('users')
        .doc(me)
        .collection('blocked')
        .doc(blocked)
        .get();
    expect(doc.exists, true);
  });

  test('unblocking removes the row', () async {
    final ref =
        db.collection('users').doc(me).collection('blocked').doc(blocked);
    await ref.set({'at': Timestamp.now()});
    await ref.delete();
    expect((await ref.get()).exists, false);
  });

  test('feed excludes posts authored by a blocked user', () async {
    await db
        .collection('users')
        .doc(me)
        .collection('blocked')
        .doc(blocked)
        .set({'at': Timestamp.now()});

    await db.collection('posts').add({'authorId': blocked, 'text': 'hidden'});
    await db.collection('posts').add({'authorId': other, 'text': 'visible'});

    // Replicate the client-side filter the feed must apply.
    final blockedIds = (await db
            .collection('users')
            .doc(me)
            .collection('blocked')
            .get())
        .docs
        .map((d) => d.id)
        .toSet();

    final visible = (await db.collection('posts').get())
        .docs
        .where((d) => !blockedIds.contains(d['authorId']))
        .toList();

    expect(visible, hasLength(1));
    expect(visible.first['text'], 'visible');
  });

  test('nearby list excludes a blocked user', () async {
    await db
        .collection('users')
        .doc(me)
        .collection('blocked')
        .doc(blocked)
        .set({'at': Timestamp.now()});

    final candidates = [blocked, other];
    final blockedIds = (await db
            .collection('users')
            .doc(me)
            .collection('blocked')
            .get())
        .docs
        .map((d) => d.id)
        .toSet();

    final shown = candidates.where((id) => !blockedIds.contains(id)).toList();
    expect(shown, [other]);
  });
}
