import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/shared/providers/event_provider.dart';
import 'package:flyconnect/shared/providers/promotion_provider.dart';
import 'package:flyconnect/shared/providers/user_provider.dart';
import 'package:flyconnect/features/business/analytics_screen.dart';

import '../helpers/fixtures.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

class _MockEventProvider extends Mock implements EventProvider {}

class _MockPromotionProvider extends Mock implements PromotionProvider {}

class _MockUserProvider extends Mock implements UserProvider {}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _MockAuthProvider authProvider,
  required _MockEventProvider eventProvider,
}) async {
  final promotionProvider = _MockPromotionProvider();
  final userProvider = _MockUserProvider();
  when(() => promotionProvider.promotions).thenReturn(const []);
  when(() => userProvider.currentUser).thenReturn(null);

  final router = GoRouter(
    initialLocation: '/analytics',
    routes: [
      GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
      GoRoute(
        path: '/business-event-management',
        builder: (_, state) =>
            Scaffold(body: Text('MANAGEMENT:${(state.extra as EventModel).id}')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<EventProvider>.value(value: eventProvider),
        ChangeNotifierProvider<PromotionProvider>.value(value: promotionProvider),
        ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _MockAuthProvider authProvider;
  late _MockEventProvider eventProvider;

  setUp(() {
    authProvider = _MockAuthProvider();
    eventProvider = _MockEventProvider();
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
  });

  testWidgets('filters Event Attendance to only events created by the current uid',
      (tester) async {
    final own = buildEvent(id: 'evt-own', title: 'Own Event', createdBy: 'biz-1');
    final other =
        buildEvent(id: 'evt-other', title: 'Other Biz Event', createdBy: 'biz-2');
    when(() => eventProvider.events).thenReturn([own, other]);

    await _pumpScreen(tester, authProvider: authProvider, eventProvider: eventProvider);

    expect(find.text('Own Event'), findsOneWidget);
    expect(find.text('Other Biz Event'), findsNothing);
  });

  testWidgets('caps the list at 3 events even if more belong to the business',
      (tester) async {
    final events = List.generate(
      5,
      (i) => buildEvent(id: 'evt-$i', title: 'Event $i', createdBy: 'biz-1'),
    );
    when(() => eventProvider.events).thenReturn(events);

    await _pumpScreen(tester, authProvider: authProvider, eventProvider: eventProvider);

    expect(find.text('Event 0'), findsOneWidget);
    expect(find.text('Event 1'), findsOneWidget);
    expect(find.text('Event 2'), findsOneWidget);
    expect(find.text('Event 3'), findsNothing);
    expect(find.text('Event 4'), findsNothing);
  });

  testWidgets('shows "No events yet" when the business has zero events',
      (tester) async {
    when(() => eventProvider.events).thenReturn(const []);

    await _pumpScreen(tester, authProvider: authProvider, eventProvider: eventProvider);

    expect(find.text('No events yet'), findsOneWidget);
  });

  testWidgets('tapping an event card pushes /business-event-management with extra',
      (tester) async {
    final own = buildEvent(id: 'evt-own', title: 'Own Event', createdBy: 'biz-1');
    when(() => eventProvider.events).thenReturn([own]);

    await _pumpScreen(tester, authProvider: authProvider, eventProvider: eventProvider);
    await tester.tap(find.text('Own Event'));
    await tester.pumpAndSettle();

    expect(find.text('MANAGEMENT:evt-own'), findsOneWidget);
  });
}
