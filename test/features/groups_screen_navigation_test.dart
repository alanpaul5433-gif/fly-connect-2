import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/shared/providers/group_provider.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/features/groups/groups_screen.dart';

import '../helpers/fixtures.dart';

class _MockGroupProvider extends Mock implements GroupProvider {}

class _MockAuthProvider extends Mock implements AuthProvider {}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _MockGroupProvider groupProvider,
  required _MockAuthProvider authProvider,
}) async {
  final router = GoRouter(
    initialLocation: '/groups-list',
    routes: [
      GoRoute(path: '/groups-list', builder: (_, __) => const GroupsScreen()),
      GoRoute(
        path: '/business-group-management',
        builder: (_, state) =>
            Scaffold(body: Text('MANAGEMENT:${(state.extra as GroupModel).id}')),
      ),
      GoRoute(
        path: '/groups/:groupId',
        builder: (_, state) =>
            Scaffold(body: Text('DETAILS:${state.pathParameters['groupId']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<GroupProvider>.value(value: groupProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _MockGroupProvider groupProvider;
  late _MockAuthProvider authProvider;
  late GroupModel group;

  setUp(() {
    groupProvider = _MockGroupProvider();
    authProvider = _MockAuthProvider();
    group = buildGroup(id: 'grp-1', name: 'Layover Crew', createdBy: 'biz-1');
    when(() => groupProvider.groups).thenReturn([group]);
    when(() => groupProvider.myGroups).thenReturn(const []);
    when(() => groupProvider.isMember('grp-1')).thenReturn(false);
    when(() => authProvider.userRole).thenReturn('business');
  });

  testWidgets('uid == createdBy pushes /business-group-management with extra',
      (tester) async {
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));

    await _pumpScreen(tester, groupProvider: groupProvider, authProvider: authProvider);
    await tester.tap(find.text('Layover Crew'));
    await tester.pumpAndSettle();

    expect(find.text('MANAGEMENT:grp-1'), findsOneWidget);
  });

  testWidgets('uid in admins (not createdBy) pushes /business-group-management',
      (tester) async {
    group = buildGroup(
        id: 'grp-1', name: 'Layover Crew', createdBy: 'biz-1', admins: const ['admin-1']);
    when(() => groupProvider.groups).thenReturn([group]);
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'admin-1'));

    await _pumpScreen(tester, groupProvider: groupProvider, authProvider: authProvider);
    await tester.tap(find.text('Layover Crew'));
    await tester.pumpAndSettle();

    expect(find.text('MANAGEMENT:grp-1'), findsOneWidget);
  });

  testWidgets('no ownership pushes /groups/:id details route instead',
      (tester) async {
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'crew-9'));

    await _pumpScreen(tester, groupProvider: groupProvider, authProvider: authProvider);
    await tester.tap(find.text('Layover Crew'));
    await tester.pumpAndSettle();

    expect(find.text('DETAILS:grp-1'), findsOneWidget);
  });

  testWidgets('signed-out user (uid null) always routes to details',
      (tester) async {
    when(() => authProvider.currentUser).thenReturn(null);

    await _pumpScreen(tester, groupProvider: groupProvider, authProvider: authProvider);
    await tester.tap(find.text('Layover Crew'));
    await tester.pumpAndSettle();

    expect(find.text('DETAILS:grp-1'), findsOneWidget);
  });
}
