import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/shared/providers/user_provider.dart';
import 'package:flyconnect/shared/providers/post_provider.dart';
import 'package:flyconnect/shared/providers/chat_provider.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/features/profile/profile_screen.dart';

import '../helpers/fixtures.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

class _MockUserProvider extends Mock implements UserProvider {}

class _MockPostProvider extends Mock implements PostProvider {}

class _MockChatProvider extends Mock implements ChatProvider {}

/// Own-profile (isOwner:true) path only — the third-party (isOwner:false)
/// path also calls raw `FirebaseFirestore.instance` inside
/// `_checkBlockedRelationship` with no mocked plugin channel, which hangs
/// forever in this test environment (same pre-existing limitation noted in
/// event_management_screen_test.dart's `_settle` helper). That path is
/// covered by the manual "Business Dashboard Walkthrough" checklist instead.
Future<void> _pumpOwnProfile(WidgetTester tester, {required UserModel currentUser}) async {
  final authProvider = _MockAuthProvider();
  final userProvider = _MockUserProvider();
  final postProvider = _MockPostProvider();
  final chatProvider = _MockChatProvider();

  when(() => authProvider.currentUser).thenReturn(currentUser);
  when(() => userProvider.currentUser).thenReturn(currentUser);
  when(() => userProvider.getMyStory(any())).thenAnswer((_) async => null);
  when(() => postProvider.feed).thenReturn(const []);
  when(() => postProvider.likedPostIds).thenReturn(const {});

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ChangeNotifierProvider<PostProvider>.value(value: postProvider),
        ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
      ],
      child: const MaterialApp(home: ProfileScreen(isOwner: true)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Role-aware profile header (B1)', () {
    testWidgets('shows a verified badge and a business pill for a verified business account',
        (tester) async {
      await _pumpOwnProfile(tester,
          currentUser: buildUser(uid: 'biz-1', name: 'Sky Lounge NYC', role: 'business', isVerified: true));

      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);
    });

    testWidgets('shows neither badge nor business pill for a plain unverified user',
        (tester) async {
      await _pumpOwnProfile(tester,
          currentUser: buildUser(uid: 'user-1', name: 'Alex Johnson'));

      expect(find.byIcon(Icons.verified), findsNothing);
      expect(find.text('Business'), findsNothing);
    });
  });
}
