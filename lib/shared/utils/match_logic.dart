import 'package:cloud_firestore/cloud_firestore.dart';

/// Match bookkeeping, factored out of [MatchProvider] so it can be tested —
/// the provider hard-codes `FirebaseFirestore.instance`. Same pattern as
/// `block_list.dart` and `account_deletion.dart`.

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

  await db.collection('matches').add({
    'userA': myUid,
    'userB': targetUid,
    'status': 'pending',
    'matchType': matchType,
    'likedAt': FieldValue.serverTimestamp(),
  });
  return false;
}
