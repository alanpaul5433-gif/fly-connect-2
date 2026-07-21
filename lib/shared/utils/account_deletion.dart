import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore-only half of "delete my account" (B3).
///
/// Extracted from `AuthProvider.deleteAccount` so the erasure can be unit
/// tested against `fake_cloud_firestore` — the original wiped
/// `users/{uid}/trips`, a subcollection that does not exist (trips are
/// top-level, keyed by `userId`), so trip history survived deletion along with
/// SafeCheck check-ins, notifications and stories. Nothing caught it because
/// nothing could run it.
///
/// The caller owns the FirebaseAuth side; see `deleteAccount`.

/// Top-level collections holding documents owned by a single user, keyed by a
/// `userId` field. Add to this list when a new user-owned collection appears —
/// `account_deletion_test.dart` asserts each one is erased.
const List<String> userOwnedCollections = [
  'trips',
  'safeChecks',
  'notifications',
];

/// Subcollections under `users/{uid}`.
const List<String> userSubcollections = [
  'savedPosts',
  'blocked',
  'following',
  'followers',
  'trips', // legacy: written by older builds before trips moved top-level
  'private',
];

/// Erases every Firestore trace of [uid] except their posts, which are
/// anonymised in place because other users' comments and likes hang off them.
///
/// The `users/{uid}` document is deleted **last**. If an earlier step throws,
/// the account still resolves and the operation can be retried; deleting it
/// first (as the original did) left a signed-in user with no profile whenever
/// a later step failed. Idempotent — safe to re-run after a partial failure.
Future<void> purgeUserData(FirebaseFirestore db, String uid) async {
  // Before dropping our own `following` list, use it to remove the mirrored
  // `users/{followed}/followers/{uid}` docs — otherwise the departing user
  // stays counted as a follower on every profile they followed.
  await _removeMirroredFollows(db, uid);

  for (final name in userSubcollections) {
    await _deleteAll(db, db.collection('users').doc(uid).collection(name));
  }

  for (final name in userOwnedCollections) {
    await _deleteAll(db, db.collection(name).where('userId', isEqualTo: uid));
  }

  // Stories are keyed by uid rather than carrying a userId field.
  await db.collection('stories').doc(uid).delete();

  await _anonymisePosts(db, uid);

  // Last, so a failure above leaves a recoverable account rather than an
  // authenticated user with no profile document.
  await db.collection('users').doc(uid).delete();
}

/// Anonymises the user's authored posts. Content is retained — deleting it
/// would take other people's replies with it — but every identifying field is
/// cleared.
Future<void> _anonymisePosts(FirebaseFirestore db, String uid) async {
  final snap =
      await db.collection('posts').where('authorId', isEqualTo: uid).get();
  if (snap.docs.isEmpty) return;

  for (var i = 0; i < snap.docs.length; i += _batchLimit) {
    final end = (i + _batchLimit).clamp(0, snap.docs.length);
    final batch = db.batch();
    for (final doc in snap.docs.sublist(i, end)) {
      batch.update(doc.reference, {
        'authorName': '[deleted user]',
        'authorPhotoUrl': null,
        'isDeleted': true,
      });
    }
    await batch.commit();
  }
}

/// Removes `users/{followed}/followers/{uid}` for everyone [uid] followed.
///
/// The rules permit this because the doc id is the departing user's own uid.
/// The reverse direction — `users/{follower}/following/{uid}`, written by
/// people who followed *them* — cannot be cleaned from the client at all: that
/// document is owned by the other user. Those entries are left behind and need
/// a privileged cleanup (Cloud Function on user delete), which does not exist
/// yet. See docs/device-qa-report-2026-07-21.md (B3).
Future<void> _removeMirroredFollows(FirebaseFirestore db, String uid) async {
  final following =
      await db.collection('users').doc(uid).collection('following').get();
  if (following.docs.isEmpty) return;

  for (var i = 0; i < following.docs.length; i += _batchLimit) {
    final end = (i + _batchLimit).clamp(0, following.docs.length);
    final batch = db.batch();
    for (final doc in following.docs.sublist(i, end)) {
      batch.delete(
          db.collection('users').doc(doc.id).collection('followers').doc(uid));
    }
    await batch.commit();
  }
}

const int _batchLimit = 400; // Firestore hard-caps a batch at 500 writes.

/// Deletes every document matched by [query], paging so a large collection
/// can't exceed the batch limit.
Future<void> _deleteAll(FirebaseFirestore db, Query query) async {
  for (;;) {
    final snap = await query.limit(_batchLimit).get();
    if (snap.docs.isEmpty) return;

    final batch = db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    if (snap.docs.length < _batchLimit) return;
  }
}
