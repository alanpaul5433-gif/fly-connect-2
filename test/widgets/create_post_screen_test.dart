import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/post_provider.dart';
import 'package:flyconnect/shared/providers/group_provider.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/features/home/create_post_screen.dart';

import '../helpers/fixtures.dart';

class _MockPostProvider extends Mock implements PostProvider {}

class _MockGroupProvider extends Mock implements GroupProvider {}

class _MockAuthProvider extends Mock implements AuthProvider {}

Future<void> _pump(WidgetTester tester, PostProvider postProvider,
    GroupProvider groupProvider, AuthProvider authProvider) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PostProvider>.value(value: postProvider),
        ChangeNotifierProvider<GroupProvider>.value(value: groupProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: const MaterialApp(home: CreatePostScreen()),
    ),
  );
}

void main() {
  late _MockPostProvider postProvider;
  late _MockGroupProvider groupProvider;
  late _MockAuthProvider authProvider;

  setUp(() {
    postProvider = _MockPostProvider();
    groupProvider = _MockGroupProvider();
    authProvider = _MockAuthProvider();
    when(() => groupProvider.myGroups).thenReturn(const []);
    when(() => authProvider.currentUser).thenReturn(buildUser());
  });

  group('M-10: empty Share is no longer a silent no-op', () {
    testWidgets('tapping Share with no caption and no media shows a hint, never calls createPost',
        (tester) async {
      await _pump(tester, postProvider, groupProvider, authProvider);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share'));
      await tester.pump(); // show the SnackBar

      expect(find.text('Add a caption or a photo/video before sharing.'), findsOneWidget);
      verifyNever(() => postProvider.createPost(
            caption: any(named: 'caption'),
            mediaUrls: any(named: 'mediaUrls'),
            mediaType: any(named: 'mediaType'),
            location: any(named: 'location'),
            groupId: any(named: 'groupId'),
            audience: any(named: 'audience'),
          ));
    });

    testWidgets('a caption alone is enough to submit (no hint shown)', (tester) async {
      when(() => postProvider.createPost(
            caption: any(named: 'caption'),
            mediaUrls: any(named: 'mediaUrls'),
            mediaType: any(named: 'mediaType'),
            location: any(named: 'location'),
            groupId: any(named: 'groupId'),
            audience: any(named: 'audience'),
          )).thenAnswer((_) async {});

      await _pump(tester, postProvider, groupProvider, authProvider);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Layover thoughts');
      await tester.tap(find.text('Share'));
      await tester.pump();

      expect(find.text('Add a caption or a photo/video before sharing.'), findsNothing);
      verify(() => postProvider.createPost(
            caption: 'Layover thoughts',
            mediaUrls: any(named: 'mediaUrls'),
            mediaType: any(named: 'mediaType'),
            location: any(named: 'location'),
            groupId: any(named: 'groupId'),
            audience: any(named: 'audience'),
          )).called(1);
    });
  });
}
