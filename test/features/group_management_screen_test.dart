import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/shared/providers/group_provider.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/features/business/group_management_screen.dart';

import '../helpers/fixtures.dart';

class _MockGroupProvider extends Mock implements GroupProvider {}

class _MockAuthProvider extends Mock implements AuthProvider {}

/// Pumps GroupManagementScreen behind a real GoRouter stack (root route +
/// pushed /group route) so `GoRouter.of(context).pop()` calls inside the
/// screen (back button, successful delete) have somewhere to pop to.
Future<GoRouter> _pumpScreen(
  WidgetTester tester, {
  required GroupModel group,
  required _MockGroupProvider groupProvider,
  required _MockAuthProvider authProvider,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('ROOT'))),
      GoRoute(
        path: '/group',
        builder: (_, __) => GroupManagementScreen(group: group),
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
  router.push('/group');
  await tester.pumpAndSettle();
  return router;
}

void main() {
  late _MockGroupProvider groupProvider;
  late _MockAuthProvider authProvider;

  setUp(() {
    groupProvider = _MockGroupProvider();
    authProvider = _MockAuthProvider();
    when(() => groupProvider.fetchMembers(any()))
        .thenAnswer((_) async => const []);
  });

  testWidgets('non-owner, non-admin sees permission-denied screen',
      (tester) async {
    final group = buildGroup(createdBy: 'biz-1', admins: const []);
    when(() => authProvider.currentUser)
        .thenReturn(buildUser(uid: 'stranger-uid'));

    await _pumpScreen(tester,
        group: group, groupProvider: groupProvider, authProvider: authProvider);

    expect(find.text("You don't have permission to manage this group."),
        findsOneWidget);
    expect(find.text('Group Chat'), findsNothing);
  });

  testWidgets('owner (createdBy == uid) sees full management UI',
      (tester) async {
    final group = buildGroup(createdBy: 'biz-1');
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));

    await _pumpScreen(tester,
        group: group, groupProvider: groupProvider, authProvider: authProvider);

    expect(find.text('Group Chat'), findsOneWidget);
    expect(find.text('Broadcast Message'), findsOneWidget);
  });

  testWidgets('admin (in admins, not createdBy) sees full management UI',
      (tester) async {
    final group =
        buildGroup(createdBy: 'biz-1', admins: const ['admin-uid']);
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'admin-uid'));

    await _pumpScreen(tester,
        group: group, groupProvider: groupProvider, authProvider: authProvider);

    expect(find.text('Group Chat'), findsOneWidget);
  });

  testWidgets('initState calls fetchMembers unconditionally with group.members',
      (tester) async {
    final group = buildGroup(createdBy: 'biz-1', members: const ['m-1', 'm-2']);
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));

    await _pumpScreen(tester,
        group: group, groupProvider: groupProvider, authProvider: authProvider);

    verify(() => groupProvider.fetchMembers(['m-1', 'm-2'])).called(1);
  });

  group('Delete Group', () {
    testWidgets('cancel in confirm dialog leaves the screen in place',
        (tester) async {
      final group = buildGroup(createdBy: 'biz-1');
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Group'));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure you want to delete this group? This cannot be undone.'),
          findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(GroupManagementScreen), findsOneWidget);
      verifyNever(() => groupProvider.deleteGroup(any()));
    });

    testWidgets('confirm calls deleteGroup and pops on success', (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1');
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
      when(() => groupProvider.deleteGroup('grp-1')).thenAnswer((_) async {});

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      verify(() => groupProvider.deleteGroup('grp-1')).called(1);
      expect(find.text('ROOT'), findsOneWidget);
      expect(find.byType(GroupManagementScreen), findsNothing);
    });

    testWidgets('deleteGroup throwing shows an error SnackBar and does not pop',
        (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1');
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
      when(() => groupProvider.deleteGroup('grp-1'))
          .thenThrow(Exception('network error'));

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Could not delete group. Try again.'), findsOneWidget);
      expect(find.byType(GroupManagementScreen), findsOneWidget);
    });
  });

  group('Chat toggle', () {
    testWidgets('toggling calls setChatEnabled optimistically', (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1', chatEnabled: true);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
      when(() => groupProvider.setChatEnabled('grp-1', false))
          .thenAnswer((_) async {});

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      expect(find.text('Enabled'), findsOneWidget);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();

      verify(() => groupProvider.setChatEnabled('grp-1', false)).called(1);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('setChatEnabled throwing rolls back the switch and shows an error',
        (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1', chatEnabled: true);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
      when(() => groupProvider.setChatEnabled('grp-1', false))
          .thenThrow(Exception('fail'));

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();

      expect(find.text('Could not update chat setting.'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
    });
  });

  group('Member actions', () {
    testWidgets("'remove' calls removeMember optimistically", (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1', members: const ['m-1']);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
      when(() => groupProvider.fetchMembers(['m-1']))
          .thenAnswer((_) async => [buildUser(uid: 'm-1', name: 'Alex')]);
      when(() => groupProvider.removeMember('grp-1', 'm-1'))
          .thenAnswer((_) async {});

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      expect(find.text('Alex'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from Group'));
      await tester.pumpAndSettle();

      verify(() => groupProvider.removeMember('grp-1', 'm-1')).called(1);
      expect(find.text('Alex'), findsNothing);
      expect(find.text('Alex removed'), findsOneWidget);
    });

    testWidgets("'remove' throwing re-inserts the member and shows an error",
        (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1', members: const ['m-1']);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
      when(() => groupProvider.fetchMembers(['m-1']))
          .thenAnswer((_) async => [buildUser(uid: 'm-1', name: 'Alex')]);
      when(() => groupProvider.removeMember('grp-1', 'm-1'))
          .thenThrow(Exception('fail'));

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from Group'));
      await tester.pumpAndSettle();

      expect(find.text('Could not remove member. Try again.'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
    });

    testWidgets("'admin' calls makeAdmin and shows a success SnackBar",
        (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1', members: const ['m-1']);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
      when(() => groupProvider.fetchMembers(['m-1']))
          .thenAnswer((_) async => [buildUser(uid: 'm-1', name: 'Alex')]);
      when(() => groupProvider.makeAdmin('grp-1', 'm-1')).thenAnswer((_) async {});

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make Admin'));
      await tester.pumpAndSettle();

      verify(() => groupProvider.makeAdmin('grp-1', 'm-1')).called(1);
      expect(find.text('Alex is now an admin'), findsOneWidget);
    });

    testWidgets("'admin' throwing shows an error, no crash", (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1', members: const ['m-1']);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
      when(() => groupProvider.fetchMembers(['m-1']))
          .thenAnswer((_) async => [buildUser(uid: 'm-1', name: 'Alex')]);
      when(() => groupProvider.makeAdmin('grp-1', 'm-1'))
          .thenThrow(Exception('fail'));

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make Admin'));
      await tester.pumpAndSettle();

      expect(find.text('Could not update admin status.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Broadcast sheet', () {
    testWidgets('success pops the sheet and shows a confirmation SnackBar',
        (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1');
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
      when(() => groupProvider.sendBroadcast('grp-1', 'Meet at gate 12'))
          .thenAnswer((_) async {});

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      await tester.tap(find.text('Broadcast Message'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Meet at gate 12');
      await tester.tap(find.text('Send Broadcast'));
      await tester.pumpAndSettle();

      verify(() => groupProvider.sendBroadcast('grp-1', 'Meet at gate 12'))
          .called(1);
      expect(find.text('Broadcast saved — members will see it in the group'),
          findsOneWidget);
    });

    testWidgets('failure keeps the sheet open with an inline error',
        (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1');
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));
      when(() => groupProvider.sendBroadcast('grp-1', 'Meet at gate 12'))
          .thenThrow(Exception('fail'));

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      await tester.tap(find.text('Broadcast Message'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Meet at gate 12');
      await tester.tap(find.text('Send Broadcast'));
      await tester.pumpAndSettle();

      expect(find.text('Could not send. Try again.'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // sheet still open
    });

    testWidgets('empty text does not call sendBroadcast', (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1');
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'biz-1'));

      await _pumpScreen(tester,
          group: group, groupProvider: groupProvider, authProvider: authProvider);

      await tester.tap(find.text('Broadcast Message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Broadcast'));
      await tester.pumpAndSettle();

      verifyNever(() => groupProvider.sendBroadcast(any(), any()));
    });
  });
}
