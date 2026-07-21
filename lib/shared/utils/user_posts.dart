import 'package:cloud_firestore/cloud_firestore.dart';

/// The query behind a profile's post grid.
///
/// Extracted so it can be tested — PostProvider hard-codes
/// `FirebaseFirestore.instance`. Same pattern as `block_list.dart`.
///
/// [isSelf] is not an optimisation, it is a correctness switch driven by
/// firestore.rules. The posts read rule admits a document when it is public,
/// owned by the reader, or the reader is an admin — and Firestore fails an
/// ENTIRE query if any matched document is denied, so the query itself must
/// prove which branch it stays inside:
///   • someone else's profile → pin `audience == 'Everyone'`
///   • your own profile       → pinning authorId to yourself already proves
///     ownership, so no audience filter, and your "Only me" posts show up.
Query<Map<String, dynamic>> userPostsQuery(
  FirebaseFirestore db, {
  required String authorId,
  required bool isSelf,
}) {
  final base = db.collection('posts').where('authorId', isEqualTo: authorId);
  final scoped =
      isSelf ? base : base.where('audience', isEqualTo: 'Everyone');
  return scoped.orderBy('createdAt', descending: true);
}
