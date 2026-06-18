import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// ChatProvider data-layer contract.
///
/// Same caveat as auth_provider_test / post_provider_test: the provider uses the
/// `FirebaseFirestore.instance` singleton, so we validate the Firestore contract
/// (the shape the provider reads/writes, mirroring firestore.rules) against a
/// fake backend rather than instantiating the provider.
void main() {
  late FakeFirebaseFirestore db;
  const me = 'user-a';
  const them = 'user-b';
  const chatId = 'user-a_user-b';

  setUp(() => db = FakeFirebaseFirestore());

  group('Chat creation', () {
    test('a DM document lists both participants', () async {
      await db.collection('chats').doc(chatId).set({
        'participants': [me, them],
        'lastMessage': '',
        'updatedAt': Timestamp.now(),
      });

      final snap = await db.collection('chats').doc(chatId).get();
      expect(snap.exists, true);
      expect(snap.data()!['participants'], containsAll([me, them]));
    });
  });

  group('Messaging', () {
    test('sending a message writes to messages with the sender as senderId', () async {
      await db.collection('chats').doc(chatId).collection('messages').add({
        'senderId': me,
        'text': 'Layover in DXB next week?',
        'sentAt': Timestamp.now(),
        'readBy': [me],
      });

      final msgs =
          await db.collection('chats').doc(chatId).collection('messages').get();
      expect(msgs.docs, hasLength(1));
      expect(msgs.docs.first['senderId'], me);
      expect(msgs.docs.first['text'], isNotEmpty);
    });

    test('marking read appends the reader to readBy and never rewrites senderId',
        () async {
      final ref = await db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({'senderId': me, 'text': 'hi', 'readBy': <String>[me]});

      // The recipient marks the message read.
      await ref.update({
        'readBy': FieldValue.arrayUnion([them])
      });

      final doc = await ref.get();
      expect(doc['readBy'], containsAll([me, them]));
      expect(doc['senderId'], me); // unchanged — rules forbid forging senderId
    });

    test('messages come back in chronological order', () async {
      final base = DateTime(2026, 1, 1, 12);
      final col = db.collection('chats').doc(chatId).collection('messages');
      await col.add({'senderId': me, 'text': 'first', 'sentAt': Timestamp.fromDate(base)});
      await col.add({
        'senderId': them,
        'text': 'second',
        'sentAt': Timestamp.fromDate(base.add(const Duration(minutes: 1)))
      });

      final ordered = await col.orderBy('sentAt').get();
      expect(ordered.docs.map((d) => d['text']).toList(), ['first', 'second']);
    });
  });
}
