import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/real_providers.dart';
import 'package:flyconnect/shared/widgets/shared_widgets.dart';

// TopBarActions renders the notification + chat badges from live provider
// state. Regression guard for the bug where both counts were hardcoded to 15,
// so every screen showed a phantom "9+" regardless of real unread state.
class _MockNotificationProvider extends Mock implements NotificationProvider {}

class _MockChatProvider extends Mock implements ChatProvider {}

Future<void> _pump(
  WidgetTester tester, {
  required int notifCount,
  required int chatCount,
}) async {
  final notif = _MockNotificationProvider();
  final chat = _MockChatProvider();
  when(() => notif.unreadCount).thenReturn(notifCount);
  when(() => chat.totalUnread).thenReturn(chatCount);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          appBar: AppTopBar(actions: [TopBarActions()]),
          body: SizedBox.shrink(),
        ),
      ),
      GoRoute(path: '/search', builder: (_, __) => const SizedBox.shrink()),
      GoRoute(path: '/notifications', builder: (_, __) => const SizedBox.shrink()),
      GoRoute(path: '/chat', builder: (_, __) => const SizedBox.shrink()),
    ],
  );

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationProvider>.value(value: notif),
      ChangeNotifierProvider<ChatProvider>.value(value: chat),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
}

void main() {
  testWidgets('shows no badge text when nothing is unread', (tester) async {
    await _pump(tester, notifCount: 0, chatCount: 0);
    // An empty inbox must not render any badge number — not "0", not "9+".
    expect(find.text('0'), findsNothing);
    expect(find.text('9+'), findsNothing);
  });

  testWidgets('renders the exact unread count below 10', (tester) async {
    await _pump(tester, notifCount: 3, chatCount: 7);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('9+'), findsNothing);
  });

  testWidgets('caps large counts at 9+', (tester) async {
    await _pump(tester, notifCount: 42, chatCount: 11);
    // Both exceed 9, so both badges read "9+".
    expect(find.text('9+'), findsNWidgets(2));
    expect(find.text('42'), findsNothing);
  });
}
