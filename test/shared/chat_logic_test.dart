import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/utils/chat_logic.dart';

/// Coverage for H24 — marking a chat read.
///
/// markMessagesRead read every non-own message and wrote them all in ONE
/// batch. Firestore caps a batch at 500 writes, so a chat with >500 unread
/// threw an uncaught exception straight out of the conversation screen's
/// initState. The write is now chunked.
void main() {
  group('chunked', () {
    test('splits at the size boundary', () {
      expect(chunked(List.generate(401, (i) => i), 400).map((c) => c.length),
          [400, 1]);
    });

    test('exact multiples produce full chunks only', () {
      expect(chunked(List.generate(800, (i) => i), 400).map((c) => c.length),
          [400, 400]);
    });

    test('a short list is a single chunk', () {
      expect(chunked([1, 2, 3], 400), [[1, 2, 3]]);
    });

    test('empty in, empty out', () {
      expect(chunked(<int>[], 400), isEmpty);
    });
  });

  group('markMessagesReadIn', () {
    late FakeFirebaseFirestore db;
    const me = 'me';
    const them = 'them';
    const chat = 'c1';

    setUp(() => db = FakeFirebaseFirestore());

    Future<void> seed(String id, String sender, List<String> readBy) =>
        db.collection('chats').doc(chat).collection('messages').doc(id).set({
          'senderId': sender, 'text': id, 'readBy': readBy,
          'createdAt': DateTime(2026, 7, 1),
        });

    Future<List<String>> readByOf(String id) async {
      final d = await db.collection('chats').doc(chat).collection('messages')
          .doc(id).get();
      return List<String>.from(d.data()!['readBy']);
    }

    test('marks an unread message from the other person', () async {
      await seed('m1', them, const []);
      await markMessagesReadIn(db, chatId: chat, uid: me);
      expect(await readByOf('m1'), contains(me));
    });

    test('leaves my own messages untouched', () async {
      await seed('mine', me, const []);
      await markMessagesReadIn(db, chatId: chat, uid: me);
      expect(await readByOf('mine'), isNot(contains(me)));
    });

    test('does not duplicate me in an already-read message', () async {
      await seed('m1', them, const [me]);
      await markMessagesReadIn(db, chatId: chat, uid: me);
      expect(await readByOf('m1'), [me]);
    });

    test('marks far more than one batch worth without error (H24 crash)', () async {
      // 900 > the 500 batch cap and > the 400 chunk size: the old single-batch
      // write threw here. fake_cloud_firestore doesn't enforce the cap, but
      // this proves the chunked path marks every message correctly at scale.
      for (var i = 0; i < 900; i++) {
        await seed('u$i', them, const []);
      }
      await markMessagesReadIn(db, chatId: chat, uid: me);
      expect(await readByOf('u0'), contains(me));
      expect(await readByOf('u899'), contains(me));
    });
  });
}
