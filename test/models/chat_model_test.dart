import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Regression coverage for the Direct-Messages crash: `_ChatTile` resolved the
/// other participant's name via `(chat as dynamic).participantNames`, a getter
/// `ChatModel` never had. The `as dynamic` hid it from the analyzer, so it only
/// surfaced at runtime as a NoSuchMethodError that took down the whole
/// Direct tab.
///
/// The name now lives on the model as a typed field, resolved through
/// `displayNameFor`.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  ChatModel buildDm({Map<String, String> participantNames = const {}}) =>
      ChatModel(
        id: 'c1',
        type: 'dm',
        participants: const ['me', 'them'],
        participantNames: participantNames,
        createdBy: 'me',
        createdAt: DateTime(2026, 1, 1),
      );

  group('ChatModel.participantNames round-trip', () {
    test('a DM round-trips the participant names map', () async {
      final chat = buildDm(
        participantNames: const {'me': 'Alex Johnson', 'them': 'Maria Chen'},
      );
      await db.collection('chats').doc('c1').set(chat.toFirestore());

      final snap = await db.collection('chats').doc('c1').get();
      final parsed = ChatModel.fromFirestore(snap);

      expect(parsed.participantNames, {'me': 'Alex Johnson', 'them': 'Maria Chen'});
    });

    test('a legacy chat doc with no participantNames parses to an empty map',
        () async {
      await db.collection('chats').doc('c1').set({
        'type': 'dm',
        'participants': ['me', 'them'],
        'createdBy': 'me',
      });

      final snap = await db.collection('chats').doc('c1').get();
      final parsed = ChatModel.fromFirestore(snap);

      expect(parsed.participantNames, isEmpty);
    });
  });

  group('ChatModel.namesMap', () {
    test('keys each name by its own uid', () {
      final names = ChatModel.namesMap(
        meUid: 'me', meName: 'Alex Johnson',
        otherUid: 'them', otherName: 'Maria Chen',
      );

      expect(names, {'me': 'Alex Johnson', 'them': 'Maria Chen'});
    });

    test('omits a missing or blank name rather than storing an empty string', () {
      final names = ChatModel.namesMap(
        meUid: 'me', meName: 'Alex Johnson',
        otherUid: 'them', otherName: '  ',
      );

      expect(names, {'me': 'Alex Johnson'});
    });

    test('a DM built from namesMap resolves back to the other participant', () {
      final chat = buildDm(
        participantNames: ChatModel.namesMap(
          meUid: 'me', meName: 'Alex Johnson',
          otherUid: 'them', otherName: 'Maria Chen',
        ),
      );

      expect(chat.displayNameFor('me'), 'Maria Chen');
    });
  });

  group('ChatModel.displayNameFor', () {
    test('a DM shows the other participant, not the viewer', () {
      final chat = buildDm(
        participantNames: const {'me': 'Alex Johnson', 'them': 'Maria Chen'},
      );

      expect(chat.displayNameFor('me'), 'Maria Chen');
      expect(chat.displayNameFor('them'), 'Alex Johnson');
    });

    test('a legacy DM with no names falls back to "User" instead of throwing',
        () {
      final chat = buildDm();

      expect(chat.displayNameFor('me'), 'User');
    });

    test('a viewer who is not a participant never gets another member\'s name',
        () {
      // firstWhere((p) => p != uid) silently returns participants.first when
      // uid isn't in the list, which rendered the viewer's own name on every
      // DM row. Refuse to guess instead.
      final chat = buildDm(
        participantNames: const {'me': 'Alex Johnson', 'them': 'Maria Chen'},
      );

      expect(chat.displayNameFor('someone-else'), 'User');
    });

    test('a group shows its group name and ignores participantNames', () {
      final chat = ChatModel(
        id: 'g1',
        type: 'group',
        participants: const ['me', 'them'],
        participantNames: const {'them': 'Maria Chen'},
        groupName: 'NYC Crew',
        createdBy: 'me',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(chat.displayNameFor('me'), 'NYC Crew');
    });

    test('a group with no groupName falls back to "Group"', () {
      final chat = ChatModel(
        id: 'g1',
        type: 'group',
        participants: const ['me', 'them'],
        createdBy: 'me',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(chat.displayNameFor('me'), 'Group');
    });
  });

  group('ChatModel.otherUidFor', () {
    /// H11. The chat list derived the other participant with a bare
    /// `firstWhere((p) => p != currentUid)`, which returns participants.first
    /// when the viewer isn't in the list — the same trap that made every DM
    /// title render the viewer's own name (B1). Here the stakes are higher:
    /// the value is passed to blockUser and reportContent, so a wrong answer
    /// blocks or reports an innocent third party.
    ChatModel dm(List<String> participants) => ChatModel(
          id: 'c1',
          type: 'dm',
          participants: participants,
          createdBy: participants.isEmpty ? 'me' : participants.first,
          createdAt: DateTime(2026, 1, 1),
        );

    test('returns the other participant of a DM', () {
      expect(dm(['me', 'them']).otherUidFor('me'), 'them');
    });

    test('is symmetric — works from either side', () {
      expect(dm(['me', 'them']).otherUidFor('them'), 'me');
    });

    test('returns null when the viewer is not a participant', () {
      // Must NOT return 'alice', who is simply first in the list.
      expect(dm(['alice', 'bob']).otherUidFor('eve'), isNull);
    });

    test('returns null for a group chat', () {
      final group = ChatModel(
        id: 'g1',
        type: 'group',
        participants: const ['me', 'them', 'other'],
        createdBy: 'me',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(group.otherUidFor('me'), isNull);
    });

    test('returns null for a self-DM rather than the viewer themselves', () {
      // Blocking yourself would erase your own content from your feed.
      expect(dm(['me']).otherUidFor('me'), isNull);
      expect(dm(['me', 'me']).otherUidFor('me'), isNull);
    });

    test('returns null when participants is empty', () {
      expect(dm(const []).otherUidFor('me'), isNull);
    });
  });
}
