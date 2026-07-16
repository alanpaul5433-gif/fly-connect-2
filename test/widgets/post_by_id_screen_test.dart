import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/post_provider.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/features/home/post_by_id_screen.dart';
import 'package:flyconnect/features/home/post_details_screen.dart';
import 'package:flyconnect/features/common/not_found_screen.dart';

import '../helpers/fixtures.dart';

class _MockPostProvider extends Mock implements PostProvider {}

class _MockAuthProvider extends Mock implements AuthProvider {}

Future<void> _pump(WidgetTester tester, PostProvider postProvider, AuthProvider authProvider) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PostProvider>.value(value: postProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: const MaterialApp(home: PostByIdScreen(postId: 'post-1')),
    ),
  );
}

void main() {
  late _MockPostProvider postProvider;
  late _MockAuthProvider authProvider;

  setUp(() {
    postProvider = _MockPostProvider();
    authProvider = _MockAuthProvider();
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'user-1'));
  });

  testWidgets('shows a loading spinner before the fetch resolves', (tester) async {
    // A never-completing Completer (not Future.delayed — a real Timer would
    // still be pending when the test tears down and fail the framework's
    // "no leftover timers" invariant check).
    final completer = Completer<PostModel?>();
    when(() => postProvider.getPost(any())).thenAnswer((_) => completer.future);

    await _pump(tester, postProvider, authProvider);
    await tester.pump(); // one frame, fetch still in flight

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows a retryable error state on a thrown (network/transient) failure',
      (tester) async {
    when(() => postProvider.getPost(any())).thenThrow(Exception('network down'));

    await _pump(tester, postProvider, authProvider);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load this post"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(NotFoundScreen), findsNothing);
  });

  testWidgets('retry re-invokes getPost and can recover', (tester) async {
    var calls = 0;
    when(() => postProvider.getPost(any())).thenAnswer((_) async {
      calls++;
      if (calls == 1) throw Exception('network down');
      return buildPost();
    });

    await _pump(tester, postProvider, authProvider);
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    when(() => postProvider.isLiked(any())).thenAnswer((_) async => false);
    when(() => postProvider.isSaved(any())).thenAnswer((_) async => false);
    when(() => postProvider.watchComments(any())).thenAnswer((_) => const Stream<List<CommentModel>>.empty());

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.byType(PostDetailsScreen), findsOneWidget);
  });

  testWidgets('shows NotFoundScreen when the post genuinely does not exist', (tester) async {
    when(() => postProvider.getPost(any())).thenAnswer((_) async => null);

    await _pump(tester, postProvider, authProvider);
    await tester.pumpAndSettle();

    expect(find.byType(NotFoundScreen), findsOneWidget);
    expect(find.text('Post not found'), findsOneWidget);
  });

  testWidgets('renders PostDetailsScreen when the post is found', (tester) async {
    when(() => postProvider.getPost(any())).thenAnswer((_) async => buildPost());
    when(() => postProvider.isLiked(any())).thenAnswer((_) async => false);
    when(() => postProvider.isSaved(any())).thenAnswer((_) async => false);
    when(() => postProvider.watchComments(any())).thenAnswer((_) => const Stream<List<CommentModel>>.empty());

    await _pump(tester, postProvider, authProvider);
    await tester.pumpAndSettle();

    expect(find.byType(PostDetailsScreen), findsOneWidget);
    expect(find.byType(NotFoundScreen), findsNothing);
  });
}
