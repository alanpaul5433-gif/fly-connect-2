import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/post_provider.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/features/common/not_found_screen.dart';
import 'package:flyconnect/features/home/post_by_id_screen.dart';

class _MockPostProvider extends Mock implements PostProvider {}

/// Replicates the `/posts/:postId` route and the router-level `errorBuilder`
/// from lib/core/utils/app_router.dart (C-4) — kept as a local router rather
/// than the real app-wide one, same reasoning as app_router_fallback_test.dart
/// (the real router needs the full provider tree to construct).
///
/// Two concerns are tested separately on purpose (a review finding on the
/// original design draft): route *registration* (does `/posts/:postId`
/// resolve to PostByIdScreen at all) is a different assertion from
/// errorBuilder *behavior* (does a genuinely unmatched location render the
/// fallback) — folding both into one test risks "the router builds without
/// throwing" standing in for "the errorBuilder actually renders it".
GoRouter _router() => GoRouter(
      initialLocation: '/start',
      errorBuilder: (_, __) => const NotFoundScreen(),
      routes: [
        GoRoute(path: '/start', builder: (_, __) => const Scaffold(body: Text('START'))),
        GoRoute(path: '/posts/:postId',
            builder: (_, state) => PostByIdScreen(postId: state.pathParameters['postId'] ?? '')),
      ],
    );

void main() {
  testWidgets('/posts/:postId resolves to PostByIdScreen', (tester) async {
    final postProvider = _MockPostProvider();
    // Never resolves — only route resolution matters here, not fetch outcome.
    when(() => postProvider.getPost(any())).thenAnswer((_) => Completer<PostModel?>().future);

    final router = _router();
    await tester.pumpWidget(
      ChangeNotifierProvider<PostProvider>.value(
        value: postProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.go('/posts/post-42');
    await tester.pump();
    await tester.pump(); // GoRouter's default page transition needs a second frame

    expect(find.byType(PostByIdScreen), findsOneWidget);
    expect(find.byType(NotFoundScreen), findsNothing);

    final widget = tester.widget<PostByIdScreen>(find.byType(PostByIdScreen));
    expect(widget.postId, 'post-42');
  });

  testWidgets('an unregistered path renders NotFoundScreen via errorBuilder, not a raw router error',
      (tester) async {
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go('/this-route-does-not-exist');
    await tester.pumpAndSettle();

    expect(find.byType(NotFoundScreen), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
