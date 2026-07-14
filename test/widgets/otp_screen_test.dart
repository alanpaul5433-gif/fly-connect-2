import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flyconnect/core/constants/app_routes.dart';
import 'package:flyconnect/features/auth/otp_screen.dart';

import '../helpers/firebase_mocks.dart';

/// OtpScreen calls FirebaseAuth.instance directly (no provider seam), so it
/// needs setupFirebaseCoreMocks() just to unblock app registration. There is
/// no real auth session in this test environment, so FirebaseAuth.instance
/// .currentUser resolves to null — this exercises exactly the screen's own
/// "not signed in" fallback paths (both are real, reachable behavior: a user
/// could land here with an expired/cleared session). The signed-in paths
/// (sendEmailVerification/reload against a real FirebaseUser) are out of
/// scope here, same as _approve/_decline were out of scope for
/// event_management_screen_test.dart — they need a live Firebase connection
/// to exercise for real.
Future<GoRouter> _pumpScreen(WidgetTester tester, {String email = 'alex@delta.com'}) async {
  // OtpScreen's body is a plain (non-scrolling) Column; the default 800x600
  // test surface is too short for it and triggers a RenderFlex overflow.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('ROOT'))),
      GoRoute(path: AppRoutes.otp, builder: (_, __) => OtpScreen(email: email)),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
      GoRoute(path: AppRoutes.home, builder: (_, __) => const Scaffold(body: Text('HOME'))),
    ],
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  router.push(AppRoutes.otp);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUpAll(setupFirebaseCoreMocks);

  testWidgets('renders the target email and starts the 30s resend timer',
      (tester) async {
    await _pumpScreen(tester, email: 'alex@delta.com');

    expect(find.textContaining('alex@delta.com'), findsOneWidget);
    expect(find.text('Resend link in 30s'), findsOneWidget);
    expect(find.text('Resend verification email'), findsNothing);
  });

  testWidgets('falls back to a generic label when email is empty', (tester) async {
    await _pumpScreen(tester, email: '');

    expect(find.textContaining('your email address'), findsOneWidget);
  });

  testWidgets('resend button appears once the 30s timer elapses', (tester) async {
    await _pumpScreen(tester);

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('Resend verification email'), findsOneWidget);
    expect(find.textContaining('Resend link in'), findsNothing);
  });

  testWidgets('resend with no active session shows "Please sign in first."',
      (tester) async {
    await _pumpScreen(tester);

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.tap(find.text('Resend verification email'));
    await tester.pumpAndSettle();

    expect(find.text('Please sign in first.'), findsOneWidget);
  });

  testWidgets('"I\'ve verified — continue" with no active session routes to login',
      (tester) async {
    final router = await _pumpScreen(tester);

    await tester.tap(find.text("I've verified — continue"));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
  });

  testWidgets('back arrow pops the route', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('ROOT'), findsOneWidget);
  });
}
