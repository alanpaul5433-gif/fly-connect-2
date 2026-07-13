import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/shared/providers/group_provider.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/features/common/not_found_screen.dart';
import 'package:flyconnect/features/business/group_management_screen.dart';
import 'package:flyconnect/features/business/event_management_screen.dart';

import '../helpers/fixtures.dart';

class _MockGroupProvider extends Mock implements GroupProvider {}

class _MockAuthProvider extends Mock implements AuthProvider {}

/// Replicates the exact route definitions for `/business-group-management`
/// and `/business-event-management` from lib/core/utils/app_router.dart —
/// both fall back to NotFoundScreen when `state.extra` isn't the expected
/// model type. Matches the local-router style already used by
/// test/widgets/not_found_screen_test.dart rather than pulling in the real
/// app-wide router, which needs the full provider tree to construct.
GoRouter _router() => GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, __) => const Scaffold(body: Text('START'))),
        GoRoute(
          path: '/business-group-management',
          builder: (_, state) {
            if (state.extra is GroupModel) {
              return GroupManagementScreen(group: state.extra as GroupModel);
            }
            return const NotFoundScreen(
              title: 'No group selected',
              message: 'Open a group from your dashboard to manage it.',
            );
          },
        ),
        GoRoute(
          path: '/business-event-management',
          builder: (_, state) {
            if (state.extra is EventModel) {
              return EventManagementScreen(event: state.extra as EventModel);
            }
            return const NotFoundScreen(
              title: 'No event selected',
              message: 'Open an event from your dashboard to manage it.',
            );
          },
        ),
      ],
    );

void main() {
  testWidgets('/business-group-management with extra: GroupModel renders GroupManagementScreen',
      (tester) async {
    final groupProvider = _MockGroupProvider();
    final authProvider = _MockAuthProvider();
    when(() => groupProvider.fetchMembers(any())).thenAnswer((_) async => const []);
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));

    final router = _router();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GroupProvider>.value(value: groupProvider),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/business-group-management', extra: buildGroup(createdBy: 'biz-1'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupManagementScreen), findsOneWidget);
    expect(find.byType(NotFoundScreen), findsNothing);
  });

  testWidgets('/business-group-management with missing extra renders NotFoundScreen',
      (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/business-group-management');
    await tester.pumpAndSettle();

    expect(find.text('No group selected'), findsOneWidget);
    expect(find.text('Open a group from your dashboard to manage it.'), findsOneWidget);
  });

  testWidgets('/business-group-management with wrong extra type renders NotFoundScreen',
      (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/business-group-management', extra: 'not-a-group');
    await tester.pumpAndSettle();

    expect(find.text('No group selected'), findsOneWidget);
  });

  testWidgets('/business-event-management with missing extra renders NotFoundScreen',
      (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/business-event-management');
    await tester.pumpAndSettle();

    expect(find.text('No event selected'), findsOneWidget);
    expect(find.text('Open an event from your dashboard to manage it.'), findsOneWidget);
  });

  testWidgets('/business-event-management with wrong extra type renders NotFoundScreen',
      (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/business-event-management', extra: 42);
    await tester.pumpAndSettle();

    expect(find.text('No event selected'), findsOneWidget);
  });
}
