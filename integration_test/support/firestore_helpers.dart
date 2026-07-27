import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore read-back helpers for E2E assertions.
///
/// These use the DEFAULT `FirebaseFirestore.instance`, which `app.main()` has
/// already pointed at the emulator. Reads therefore run as whoever the app is
/// currently signed in as, so security rules apply — callers must be signed in
/// as an account allowed to read the target doc (e.g. poll a notification only
/// while signed in as its owner).
typedef JsonDoc = DocumentSnapshot<Map<String, dynamic>>;
typedef JsonQuery = QuerySnapshot<Map<String, dynamic>>;

FirebaseFirestore get db => FirebaseFirestore.instance;

/// Cloud Functions producers run asynchronously in the functions emulator, so
/// the notification/derived doc they write does NOT exist the instant the
/// triggering write returns. Poll for the specific document by id rather than
/// `pumpAndSettle`-and-hope.
///
/// Returns the snapshot once it exists; throws [StateError] on timeout so the
/// failing test names the exact doc that never appeared.
Future<JsonDoc> pollForDoc(
  DocumentReference<Map<String, dynamic>> ref, {
  Duration timeout = const Duration(seconds: 20),
  Duration interval = const Duration(milliseconds: 500),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final snap = await ref.get();
    if (snap.exists) return snap;
    await Future<void>.delayed(interval);
  }
  throw StateError('pollForDoc timed out waiting for ${ref.path}');
}

/// Like [pollForDoc] but waits until a query returns at least [minCount] docs.
/// Used where the doc id isn't deterministic (e.g. an auto-id post/comment we
/// then look up by a unique field).
Future<JsonQuery> pollForQuery(
  Query<Map<String, dynamic>> query, {
  int minCount = 1,
  Duration timeout = const Duration(seconds: 20),
  Duration interval = const Duration(milliseconds: 500),
}) async {
  final deadline = DateTime.now().add(timeout);
  JsonQuery last = await query.get();
  while (DateTime.now().isBefore(deadline)) {
    last = await query.get();
    if (last.docs.length >= minCount) return last;
    await Future<void>.delayed(interval);
  }
  throw StateError(
      'pollForQuery timed out: wanted >=$minCount, got ${last.docs.length}');
}

/// Waits until [ref] is GONE (used by unblock/delete reversals).
Future<void> pollForAbsence(
  DocumentReference<Map<String, dynamic>> ref, {
  Duration timeout = const Duration(seconds: 20),
  Duration interval = const Duration(milliseconds: 500),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final snap = await ref.get();
    if (!snap.exists) return;
    await Future<void>.delayed(interval);
  }
  throw StateError('pollForAbsence timed out: ${ref.path} still exists');
}

// ── Handles for the collections/docs the flows assert on ─────────
DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
    db.collection('users').doc(uid);

DocumentReference<Map<String, dynamic>> userPrivateDoc(String uid) =>
    db.collection('users').doc(uid).collection('private').doc('data');

DocumentReference<Map<String, dynamic>> postDoc(String postId) =>
    db.collection('posts').doc(postId);

DocumentReference<Map<String, dynamic>> postLikeDoc(
        String postId, String likerUid) =>
    db.collection('posts').doc(postId).collection('likes').doc(likerUid);

Query<Map<String, dynamic>> postCommentsBy(String postId, String authorId) =>
    db.collection('posts').doc(postId).collection('comments')
        .where('authorId', isEqualTo: authorId);

DocumentReference<Map<String, dynamic>> blockedDoc(
        String ownerUid, String blockedUid) =>
    db.collection('users').doc(ownerUid).collection('blocked').doc(blockedUid);

DocumentReference<Map<String, dynamic>> matchDoc(String matchId) =>
    db.collection('matches').doc(matchId);

DocumentReference<Map<String, dynamic>> promotionDoc(String promoId) =>
    db.collection('promotions').doc(promoId);

DocumentReference<Map<String, dynamic>> notificationDoc(String id) =>
    db.collection('notifications').doc(id);
