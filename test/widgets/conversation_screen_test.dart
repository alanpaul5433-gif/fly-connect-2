import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/chat_provider.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/shared/widgets/cached_image.dart';
import 'package:flyconnect/features/chat/conversation_screen.dart';

import '../helpers/fixtures.dart';

class _MockChatProvider extends Mock implements ChatProvider {}

class _MockAuthProvider extends Mock implements AuthProvider {}

Future<void> _pump(WidgetTester tester, ChatProvider chatProvider, AuthProvider authProvider) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: const MaterialApp(
        home: ConversationScreen(chatId: 'chat-1', otherName: 'Sam', otherUid: 'user-b'),
      ),
    ),
  );
}

void main() {
  late _MockChatProvider chatProvider;
  late _MockAuthProvider authProvider;

  setUp(() {
    chatProvider = _MockChatProvider();
    authProvider = _MockAuthProvider();
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-a'));
    when(() => chatProvider.markAsRead(any())).thenAnswer((_) async {});
    when(() => chatProvider.markMessagesRead(any())).thenAnswer((_) async {});
    when(() => chatProvider.watchTyping(any())).thenAnswer((_) => Stream.value(const {}));
  });

  MessageModel textMessage() => MessageModel(
      id: 'm1',
      chatId: 'chat-1',
      senderId: 'user-b',
      senderName: 'Sam',
      text: 'hey there',
      createdAt: DateTime(2026, 1, 1));

  MessageModel imageMessage() => MessageModel(
      id: 'm2',
      chatId: 'chat-1',
      senderId: 'user-b',
      senderName: 'Sam',
      text: '',
      mediaUrl: 'https://example.com/photo.jpg',
      mediaType: 'image',
      createdAt: DateTime(2026, 1, 1));

  group('M-7: chat image attachments', () {
    testWidgets('a text message renders text and no image bubble', (tester) async {
      when(() => chatProvider.watchMessages(any()))
          .thenAnswer((_) => Stream.value([textMessage()]));

      await _pump(tester, chatProvider, authProvider);
      // A single bounded pump, not pumpAndSettle: this codebase deliberately
      // avoids waiting on real network-image fetches in widget tests (see
      // test/widgets/cached_image_test.dart's own doc comment).
      await tester.pump();
      await tester.pump();

      expect(find.text('hey there'), findsOneWidget);
      expect(find.byType(CachedFeedImage), findsNothing);
    });

    testWidgets('an image message renders an image bubble', (tester) async {
      when(() => chatProvider.watchMessages(any()))
          .thenAnswer((_) => Stream.value([imageMessage()]));

      await _pump(tester, chatProvider, authProvider);
      await tester.pump();
      await tester.pump();

      expect(find.byType(CachedFeedImage), findsOneWidget);
    });
  });
}
