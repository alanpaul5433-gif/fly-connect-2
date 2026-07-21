import 'package:cloud_firestore/cloud_firestore.dart';

/// Block-list reads, factored out of the providers so they can be tested.
///
/// [PostProvider] and [MatchProvider] hard-code `FirebaseFirestore.instance`,
/// so anything living inside them is untestable. These functions take `db` as
/// a parameter instead — the same pattern as `account_deletion.dart`.

/// Every uid the viewer must not see content from, in either direction:
/// people [uid] blocked, and people who blocked [uid].
///
/// Both directions matter. Hiding only the first lets a harasser keep watching
/// someone who blocked them; hiding only the second is not blocking at all.
///
/// Throws if either read fails. That is deliberate: callers decide what an
/// unknown block list means for their surface, and silently returning an empty
/// set would mean "show everything", which is the wrong direction to fail for a
/// safety control. (The previous Nearby implementation did exactly that.)
Future<Set<String>> fetchBlockedUids(FirebaseFirestore db, String uid) async {
  final results = await Future.wait([
    // My own list: keyed by document id, so legacy rows written before
    // `blockedUid` existed still resolve here.
    db.collection('users').doc(uid).collection('blocked').get(),
    // Who blocked me. This MUST filter on the denormalised `blockedUid` field:
    // a collection group query cannot constrain on document ids (documentId()
    // compares full paths there), and firestore.rules only admits the query
    // when it is pinned to the caller's own uid.
    db.collectionGroup('blocked').where('blockedUid', isEqualTo: uid).get(),
  ]);

  final blocked = <String>{
    ...results[0].docs.map((d) => d.id),
    // The blocker is the grandparent: users/{blocker}/blocked/{me}
    ...results[1].docs
        .map((d) => d.reference.parent.parent?.id ?? '')
        .where((id) => id.isNotEmpty),
  };

  // A self-block is meaningless and would erase the user from their own feed.
  blocked.remove(uid);
  return blocked;
}

/// Removes items whose uid (via [uidOf]) is in [blocked], preserving order.
///
/// Filtering happens client-side because Firestore cannot express it: `not-in`
/// caps at 10 values and cannot combine with the feed's existing ordering.
List<T> withoutBlocked<T>(
  List<T> items,
  Set<String> blocked,
  String Function(T) uidOf,
) {
  if (blocked.isEmpty) return items;
  return items.where((item) => !blocked.contains(uidOf(item))).toList();
}
