import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/utils/block_list.dart';

/// Coverage for H10 — blocking that actually blocks.
///
/// `blockUser` wrote `users/{me}/blocked/{uid}` and showed "You will not see
/// their content", but the feed and match candidates never read that list, so
/// the blocked user's posts kept arriving. Nearby *tried* to also hide users
/// who had blocked me, using
/// `collectionGroup('blocked').where(FieldPath.documentId, '==', myUid)` —
/// which is invalid rather than merely denied, because a collection group
/// query compares documentId() against a full path. It threw, and the
/// surrounding `catch (_) {/* fail open */}` turned the failure into "show
/// everyone".
///
/// The blocked uid is therefore denormalised into a `blockedUid` field so the
/// reverse direction is expressible at all.
void main() {
  late FakeFirebaseFirestore db;
  const me = 'me';
  const iBlockedThem = 'noisy';
  const theyBlockedMe = 'hostile';
  const stranger = 'stranger';

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.doc('users/$me/blocked/$iBlockedThem')
        .set({'blockedAt': DateTime(2026, 7, 1), 'blockedUid': iBlockedThem});
    await db.doc('users/$theyBlockedMe/blocked/$me')
        .set({'blockedAt': DateTime(2026, 7, 2), 'blockedUid': me});
    // Noise: a block between two other people must not affect me at all.
    await db.doc('users/$stranger/blocked/$iBlockedThem')
        .set({'blockedAt': DateTime(2026, 7, 3), 'blockedUid': iBlockedThem});
  });

  group('fetchBlockedUids', () {
    test('includes users I blocked', () async {
      expect(await fetchBlockedUids(db, me), contains(iBlockedThem));
    });

    test('includes users who blocked me', () async {
      expect(await fetchBlockedUids(db, me), contains(theyBlockedMe));
    });

    test('excludes unrelated blocks between other people', () async {
      expect(await fetchBlockedUids(db, me), isNot(contains(stranger)));
    });

    test('returns exactly the two directions and nothing else', () async {
      expect(await fetchBlockedUids(db, me), {iBlockedThem, theyBlockedMe});
    });

    test('is empty for a user with no blocks in either direction', () async {
      // Not `stranger` — the fixture has them blocking someone.
      expect(await fetchBlockedUids(db, 'uninvolved'), isEmpty);
    });

    test('a block I made is mine alone, not inherited by others', () async {
      // stranger blocked `iBlockedThem` too; that must not leak into my set as
      // anything more than the block I made myself.
      expect(await fetchBlockedUids(db, stranger), {iBlockedThem});
    });

    test('never includes the viewer themselves', () async {
      // A self-block would filter the user out of their own feed.
      await db.doc('users/$me/blocked/$me')
          .set({'blockedAt': DateTime(2026), 'blockedUid': me});
      expect(await fetchBlockedUids(db, me), isNot(contains(me)));
    });

    test('ignores legacy docs that predate the blockedUid field', () async {
      // Written before the field existed. Reachable via the owner's own
      // subcollection (by id), but invisible to the reverse lookup.
      await db.doc('users/$me/blocked/legacy').set({'blockedAt': DateTime(2025)});
      await db.doc('users/oldfoe/blocked/$me').set({'blockedAt': DateTime(2025)});

      final blocked = await fetchBlockedUids(db, me);
      expect(blocked, contains('legacy'),
          reason: 'my own list is read by document id, so legacy rows still work');
      expect(blocked, isNot(contains('oldfoe')),
          reason: 'the reverse lookup needs blockedUid; backfill covers this');
    });
  });

  group('withoutBlocked', () {
    test('drops items authored by a blocked uid', () {
      final kept = withoutBlocked(
        const ['a', 'b', 'c'], {'b'}, (s) => s);
      expect(kept, ['a', 'c']);
    });

    test('keeps everything when nothing is blocked', () {
      final kept = withoutBlocked(const ['a', 'b'], <String>{}, (s) => s);
      expect(kept, ['a', 'b']);
    });

    test('preserves the original order of the kept items', () {
      final kept = withoutBlocked(
        const ['z', 'y', 'x', 'w'], {'y'}, (s) => s);
      expect(kept, ['z', 'x', 'w']);
    });

    test('returns empty when every item is blocked', () {
      expect(withoutBlocked(const ['a', 'b'], {'a', 'b'}, (s) => s), isEmpty);
    });
  });
}
