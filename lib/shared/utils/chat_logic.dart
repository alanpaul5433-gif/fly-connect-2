import 'package:cloud_firestore/cloud_firestore.dart';

/// Splits [items] into consecutive chunks of at most [size].
///
/// Firestore caps a batched write at 500 operations. deletePost and
/// markMessagesRead both cascade over an unbounded number of docs, so their
/// writes are chunked below that cap — H13's viral post, H24's >500-unread
/// chat.
List<List<T>> chunked<T>(List<T> items, int size) {
  final out = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    out.add(items.sublist(i, i + size > items.length ? items.length : i + size));
  }
  return out;
}

/// Batch limit kept comfortably under Firestore's 500-write cap.
const int kWriteBatchLimit = 400;

/// Marks every message in [chatId] not sent by [uid] as read by [uid].
///
/// H24: the old implementation wrote every unread message in ONE batch, so a
/// chat with >500 unread threw straight out of the conversation screen's
/// initState. The writes are now chunked at [kWriteBatchLimit].
///
/// Extracted from ChatProvider (which hard-codes FirebaseFirestore.instance)
/// so it can be tested. Mirrors the account_deletion / block_list pattern.
Future<void> markMessagesReadIn(
  FirebaseFirestore db, {
  required String chatId,
  required String uid,
}) async {
  final unseen = await db
      .collection('chats').doc(chatId).collection('messages')
      .where('senderId', isNotEqualTo: uid)
      .get();

  final toMark = unseen.docs.where((doc) {
    final readBy = List<String>.from(doc.data()['readBy'] ?? const []);
    return !readBy.contains(uid);
  }).toList();

  for (final group in chunked(toMark, kWriteBatchLimit)) {
    final batch = db.batch();
    for (final doc in group) {
      batch.update(doc.reference, {'readBy': FieldValue.arrayUnion([uid])});
    }
    await batch.commit();
  }
}
