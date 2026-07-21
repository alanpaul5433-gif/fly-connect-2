import 'package:cloud_firestore/cloud_firestore.dart';

/// Match bookkeeping, factored out of [MatchProvider] so it can be tested —
/// the provider hard-codes `FirebaseFirestore.instance`. Same pattern as
/// `block_list.dart` and `account_deletion.dart`.

/// Stable document id for MY outgoing edge to [targetUid].
///
/// A user has at most ONE outgoing edge (like or pass) to any other user, so a
/// deterministic id makes both writes idempotent: re-liking or like-then-pass
/// overwrites the single doc instead of piling up contradictory rows (H15).
/// The id is only ever used as a key, never parsed back, and both uids are
/// Firestore-safe, so the separator just has to be collision-free — `__` never
/// appears in a Firebase auth uid or in the mock uids (`user_001`, `biz_001`).
String edgeId(String myUid, String targetUid) => '${myUid}__$targetUid';

/// Records [myUid] liking [targetUid], and returns whether that produced a
/// mutual match.
///
/// The return value is the point. This logic was already correct inside the
/// provider, but `likeUser` returned void, so the screen had nothing to branch
/// on and showed "It's a Match!" after every like (H1).
///
/// A match requires a *pending* like in the opposite direction: `userA` is the
/// liker, so only a doc where they are `userA` and I am `userB` counts. My own
/// earlier like has me as `userA` and must not promote itself.
Future<bool> recordLike(
  FirebaseFirestore db, {
  required String myUid,
  required String targetUid,
  required String matchType,
}) async {
  final theirLike = await db
      .collection('matches')
      .where('userA', isEqualTo: targetUid)
      .where('userB', isEqualTo: myUid)
      .where('status', isEqualTo: 'pending')
      .get();

  if (theirLike.docs.isNotEmpty) {
    await theirLike.docs.first.reference.update({
      'status': 'matched',
      'matchedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  await db.collection('matches').doc(edgeId(myUid, targetUid)).set({
    'userA': myUid,
    'userB': targetUid,
    'status': 'pending',
    'matchType': matchType,
    'likedAt': FieldValue.serverTimestamp(),
  });
  return false;
}

/// Records [myUid] passing on [targetUid]. Idempotent via [edgeId]: the old
/// implementation `add()`ed a fresh doc on every pass, so a re-pass (or a
/// pass after a like) left duplicate/contradictory rows forever (H15).
Future<void> recordPass(
  FirebaseFirestore db, {
  required String myUid,
  required String targetUid,
}) async {
  await db.collection('matches').doc(edgeId(myUid, targetUid)).set({
    'userA': myUid,
    'userB': targetUid,
    'status': 'passed',
    'matchType': 'none',
    'likedAt': FieldValue.serverTimestamp(),
  });
}

/// Every uid [myUid] has already acted on, so the deck can exclude them (H15).
/// Without this, passed profiles came straight back on the next load.
///
/// Two directions, and the second is the one that's easy to miss:
///   • outgoing — any edge where I am `userA` (my likes and passes)
///   • incoming matched — an edge where I am `userB` and it reached `matched`;
///     that doc was created by the OTHER person, so it never shows up under
///     `userA == me`, yet the person is already matched and must not reappear.
///
/// A person whose like of me is still `pending` is deliberately NOT excluded —
/// they must stay in the deck so I can match back.
Future<Set<String>> fetchActedOnUids(FirebaseFirestore db, String myUid) async {
  final results = await Future.wait([
    db.collection('matches').where('userA', isEqualTo: myUid).get(),
    db
        .collection('matches')
        .where('userB', isEqualTo: myUid)
        .where('status', isEqualTo: 'matched')
        .get(),
  ]);
  return {
    ...results[0].docs.map((d) => d.data()['userB'] as String? ?? ''),
    ...results[1].docs.map((d) => d.data()['userA'] as String? ?? ''),
  }..removeWhere((id) => id.isEmpty);
}
