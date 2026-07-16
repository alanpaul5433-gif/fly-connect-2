import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/group_provider.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/shared/providers/post_provider.dart';
import 'package:flyconnect/shared/providers/user_provider.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/features/groups/group_details_screen.dart';

import '../helpers/fixtures.dart';

class _MockGroupProvider extends Mock implements GroupProvider {}

class _MockAuthProvider extends Mock implements AuthProvider {}

class _MockPostProvider extends Mock implements PostProvider {}

class _MockUserProvider extends Mock implements UserProvider {}

Future<GoRouter> _pumpScreen(
  WidgetTester tester, {
  required _MockGroupProvider groupProvider,
  required _MockAuthProvider authProvider,
  required _MockPostProvider postProvider,
  String groupId = 'grp-1',
  UserModel? organizer,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('ROOT'))),
      GoRoute(
        path: '/group-details',
        builder: (_, __) => GroupDetailsScreen(groupId: groupId),
      ),
    ],
  );

  final userProvider = _MockUserProvider();
  when(() => userProvider.fetchUser(any())).thenAnswer((_) async => organizer);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<GroupProvider>.value(value: groupProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<PostProvider>.value(value: postProvider),
        ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.push('/group-details');
  await tester.pumpAndSettle();
  return router;
}

void main() {
  late _MockGroupProvider groupProvider;
  late _MockAuthProvider authProvider;
  late _MockPostProvider postProvider;

  setUp(() {
    groupProvider = _MockGroupProvider();
    authProvider = _MockAuthProvider();
    postProvider = _MockPostProvider();
    when(() => postProvider.feed).thenReturn(const []);
  });

  testWidgets('non-member sees "Join Group" button; tapping calls joinGroup',
      (tester) async {
    final group = buildGroup(id: 'grp-1');
    when(() => groupProvider.getGroup('grp-1')).thenAnswer((_) async => group);
    when(() => groupProvider.isMember('grp-1')).thenReturn(false);
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));
    when(() => groupProvider.joinGroup('grp-1')).thenAnswer((_) async {});

    await _pumpScreen(tester,
        groupProvider: groupProvider,
        authProvider: authProvider,
        postProvider: postProvider);

    expect(find.text('Join Group'), findsOneWidget);
    await tester.tap(find.text('Join Group'));
    await tester.pumpAndSettle();

    verify(() => groupProvider.joinGroup('grp-1')).called(1);
  });

  testWidgets('member sees "Leave Group" button; tapping opens a confirm dialog',
      (tester) async {
    final group = buildGroup(id: 'grp-1');
    when(() => groupProvider.getGroup('grp-1')).thenAnswer((_) async => group);
    when(() => groupProvider.isMember('grp-1')).thenReturn(true);
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));

    await _pumpScreen(tester,
        groupProvider: groupProvider,
        authProvider: authProvider,
        postProvider: postProvider);

    expect(find.text('Leave Group'), findsOneWidget);
    await tester.tap(find.text('Leave Group'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Leave "'), findsOneWidget);
    verifyNever(() => groupProvider.leaveGroup(any()));
  });

  testWidgets('leave confirmed calls leaveGroup', (tester) async {
    final group = buildGroup(id: 'grp-1');
    when(() => groupProvider.getGroup('grp-1')).thenAnswer((_) async => group);
    when(() => groupProvider.isMember('grp-1')).thenReturn(true);
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));
    when(() => groupProvider.leaveGroup('grp-1')).thenAnswer((_) async {});

    await _pumpScreen(tester,
        groupProvider: groupProvider,
        authProvider: authProvider,
        postProvider: postProvider);

    await tester.tap(find.text('Leave Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();

    verify(() => groupProvider.leaveGroup('grp-1')).called(1);
  });

  testWidgets('leave cancelled never calls leaveGroup', (tester) async {
    final group = buildGroup(id: 'grp-1');
    when(() => groupProvider.getGroup('grp-1')).thenAnswer((_) async => group);
    when(() => groupProvider.isMember('grp-1')).thenReturn(true);
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));

    await _pumpScreen(tester,
        groupProvider: groupProvider,
        authProvider: authProvider,
        postProvider: postProvider);

    await tester.tap(find.text('Leave Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => groupProvider.leaveGroup(any()));
  });

  group('_MembersTab', () {
    testWidgets('non-admin does not see the remove-member icon', (tester) async {
      final group = buildGroup(
          id: 'grp-1', members: const ['m-1'], admins: const ['other-admin']);
      when(() => groupProvider.getGroup('grp-1')).thenAnswer((_) async => group);
      when(() => groupProvider.isMember('grp-1')).thenReturn(false);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));

      await _pumpScreen(tester,
          groupProvider: groupProvider,
          authProvider: authProvider,
          postProvider: postProvider);

      await tester.tap(find.text('Members'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
    });

    testWidgets('admin (uid in admins) sees the remove-member icon',
        (tester) async {
      final group = buildGroup(
          id: 'grp-1', members: const ['m-1'], admins: const ['user-1']);
      when(() => groupProvider.getGroup('grp-1')).thenAnswer((_) async => group);
      when(() => groupProvider.isMember('grp-1')).thenReturn(true);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));

      await _pumpScreen(tester,
          groupProvider: groupProvider,
          authProvider: authProvider,
          postProvider: postProvider);

      await tester.tap(find.text('Members'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    });

    testWidgets('remove confirmed calls GroupProvider.removeMember optimistically',
        (tester) async {
      final group = buildGroup(
          id: 'grp-1', members: const ['m-1'], admins: const ['user-1']);
      when(() => groupProvider.getGroup('grp-1')).thenAnswer((_) async => group);
      when(() => groupProvider.isMember('grp-1')).thenReturn(true);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));
      when(() => groupProvider.removeMember('grp-1', 'm-1'))
          .thenAnswer((_) async {});

      await _pumpScreen(tester,
          groupProvider: groupProvider,
          authProvider: authProvider,
          postProvider: postProvider);

      await tester.tap(find.text('Members'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      verify(() => groupProvider.removeMember('grp-1', 'm-1')).called(1);
      expect(find.text('Member removed'), findsOneWidget);
    });

    testWidgets('removeMember throwing re-inserts the uid and shows an error',
        (tester) async {
      final group = buildGroup(
          id: 'grp-1', members: const ['m-1'], admins: const ['user-1']);
      when(() => groupProvider.getGroup('grp-1')).thenAnswer((_) async => group);
      when(() => groupProvider.isMember('grp-1')).thenReturn(true);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));
      when(() => groupProvider.removeMember('grp-1', 'm-1'))
          .thenThrow(Exception('fail'));

      await _pumpScreen(tester,
          groupProvider: groupProvider,
          authProvider: authProvider,
          postProvider: postProvider);

      await tester.tap(find.text('Members'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Could not remove member. Try again.'), findsOneWidget);
      // The uid is re-inserted, so the member row (and its remove icon,
      // still visible since this viewer is an admin) should be back.
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    });
  });

  group('Organizer identity (B1)', () {
    testWidgets('shows "Hosted by" row with a verified badge for a verified business creator',
        (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'biz-1');
      when(() => groupProvider.getGroup('grp-1')).thenAnswer((_) async => group);
      when(() => groupProvider.isMember('grp-1')).thenReturn(false);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));

      await _pumpScreen(tester,
          groupProvider: groupProvider,
          authProvider: authProvider,
          postProvider: postProvider,
          organizer: buildUser(uid: 'biz-1', name: 'Sky Lounge NYC', role: 'business', isVerified: true));

      expect(find.textContaining('Hosted by Sky Lounge NYC'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);
    });

    testWidgets('no organizer row when the creator cannot be resolved',
        (tester) async {
      final group = buildGroup(id: 'grp-1', createdBy: 'ghost-uid');
      when(() => groupProvider.getGroup('grp-1')).thenAnswer((_) async => group);
      when(() => groupProvider.isMember('grp-1')).thenReturn(false);
      when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));

      await _pumpScreen(tester,
          groupProvider: groupProvider,
          authProvider: authProvider,
          postProvider: postProvider);

      expect(find.textContaining('Hosted by'), findsNothing);
    });
  });
}
