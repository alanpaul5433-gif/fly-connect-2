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

  group('Unread counts', () {
    // Mirrors ChatProvider.sendMessage's real (non-mock) write: a batch that
    // sets the message doc and bumps unreadCount for every participant
    // other than the sender via FieldValue.increment.
    Future<void> sendAsProvider(String senderId, List<String> participants, String text) async {
      final chatRef = db.collection('chats').doc(chatId);
      final msgRef = chatRef.collection('messages').doc();
      final batch = db.batch();
      batch.set(msgRef, {'senderId': senderId, 'text': text, 'readBy': [senderId]});
      final chatUpdate = <String, dynamic>{'lastMessage': text};
      for (final uid in participants) {
        if (uid != senderId) chatUpdate['unreadCount.$uid'] = FieldValue.increment(1);
      }
      batch.update(chatRef, chatUpdate);
      await batch.commit();
    }

    test('sending a message increments the recipient\'s unreadCount, not the sender\'s',
        () async {
      await db.collection('chats').doc(chatId).set({
        'participants': [me, them],
        'unreadCount': {me: 0, them: 0},
      });

      await sendAsProvider(me, [me, them], 'Layover in DXB next week?');

      final chat = await db.collection('chats').doc(chatId).get();
      expect(chat.data()!['unreadCount'][them], 1);
      expect(chat.data()!['unreadCount'][me], 0);
    });

    test('unreadCount accumulates across multiple unread messages', () async {
      await db.collection('chats').doc(chatId).set({
        'participants': [me, them],
        'unreadCount': {me: 0, them: 0},
      });

      await sendAsProvider(me, [me, them], 'first');
      await sendAsProvider(me, [me, them], 'second');

      final chat = await db.collection('chats').doc(chatId).get();
      expect(chat.data()!['unreadCount'][them], 2);
    });

    test('marking a chat read zeroes only the reader\'s unreadCount', () async {
      await db.collection('chats').doc(chatId).set({
        'participants': [me, them],
        'unreadCount': {me: 3, them: 1},
      });

      // Mirrors ChatProvider.markAsRead.
      await db.collection('chats').doc(chatId).update({'unreadCount.$me': 0});

      final chat = await db.collection('chats').doc(chatId).get();
      expect(chat.data()!['unreadCount'][me], 0);
      expect(chat.data()!['unreadCount'][them], 1);
    });
  });

  group('Read receipts', () {
    // Mirrors ChatProvider.markMessagesRead: appends the reader to readBy
    // on every message sent by someone else that they haven't seen yet.
    Future<void> markMessagesReadAsProvider(String readerId) async {
      final unseen = await db.collection('chats').doc(chatId).collection('messages')
          .where('senderId', isNotEqualTo: readerId).get();
      final batch = db.batch();
      for (final doc in unseen.docs) {
        final readBy = List<String>.from(doc.data()['readBy'] ?? []);
        if (!readBy.contains(readerId)) {
          batch.update(doc.reference, {'readBy': FieldValue.arrayUnion([readerId])});
        }
      }
      await batch.commit();
    }

    test('opening a conversation marks the sender\'s messages read (double-check)',
        () async {
      final col = db.collection('chats').doc(chatId).collection('messages');
      final ref = await col.add({'senderId': me, 'text': 'hi', 'readBy': [me]});

      await markMessagesReadAsProvider(them);

      final doc = await ref.get();
      expect(doc.data()!['readBy'], containsAll([me, them]));
    });

    test('does not touch messages the reader already sent themselves', () async {
      final col = db.collection('chats').doc(chatId).collection('messages');
      final ref = await col.add({'senderId': me, 'text': 'hi', 'readBy': [me]});

      await markMessagesReadAsProvider(me);

      final doc = await ref.get();
      expect(doc.data()!['readBy'], [me]);
    });
  });

  group('Mute (M-7)', () {
    test('toggleMute mirror: muting adds the caller to mutedBy', () async {
      await db.collection('chats').doc(chatId).set({'participants': [me, them], 'mutedBy': <String>[]});

      // Mirrors ChatProvider.toggleMute's arrayUnion branch.
      await db.collection('chats').doc(chatId).update({
        'mutedBy': FieldValue.arrayUnion([me]),
      });

      final doc = await db.collection('chats').doc(chatId).get();
      expect(doc.data()!['mutedBy'], contains(me));
    });

    test('toggleMute mirror: unmuting removes only the caller, not other muters', () async {
      await db.collection('chats').doc(chatId).set({'participants': [me, them], 'mutedBy': [me, them]});

      // Mirrors ChatProvider.toggleMute's arrayRemove branch.
      await db.collection('chats').doc(chatId).update({
        'mutedBy': FieldValue.arrayRemove([me]),
      });

      final doc = await db.collection('chats').doc(chatId).get();
      final mutedBy = List<String>.from(doc.data()!['mutedBy']);
      expect(mutedBy, isNot(contains(me)));
      expect(mutedBy, contains(them));
    });
  });
}
