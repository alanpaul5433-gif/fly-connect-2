import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flyconnect/core/constants/app_routes.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/features/splash/splash_screen.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

/// Splash waits a fixed 2s before deciding, then (if logged in) awaits
/// authReady bounded to 3s — so tests must pump real durations rather than
/// pumpAndSettle, which would spin forever against a never-completing
/// authReady future.
Future<GoRouter> _pumpScreen(
  WidgetTester tester, {
  required _MockAuthProvider authProvider,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
      GoRoute(path: AppRoutes.onboarding, builder: (_, __) => const Scaffold(body: Text('ONBOARDING'))),
      GoRoute(path: AppRoutes.home, builder: (_, __) => const Scaffold(body: Text('HOME'))),
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold(body: Text('DASHBOARD'))),
      GoRoute(path: '/admin/dashboard', builder: (_, __) => const Scaffold(body: Text('ADMIN'))),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: authProvider,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  return router;
}

void main() {
  late _MockAuthProvider authProvider;

  setUp(() {
    authProvider = _MockAuthProvider();
  });

  testWidgets('signed out + onboarding already seen routes to login',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_seen': true});
    when(() => authProvider.isLoggedIn).thenReturn(false);

    await _pumpScreen(tester, authProvider: authProvider);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);
  });

  testWidgets('signed out + onboarding never seen routes to onboarding',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    when(() => authProvider.isLoggedIn).thenReturn(false);

    await _pumpScreen(tester, authProvider: authProvider);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('ONBOARDING'), findsOneWidget);
  });

  testWidgets('logged in crew user routes to /home once authReady resolves',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    when(() => authProvider.isLoggedIn).thenReturn(true);
    when(() => authProvider.authReady).thenAnswer((_) async {});
    when(() => authProvider.userRole).thenReturn('user');

    await _pumpScreen(tester, authProvider: authProvider);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('logged in business user routes to /dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    when(() => authProvider.isLoggedIn).thenReturn(true);
    when(() => authProvider.authReady).thenAnswer((_) async {});
    when(() => authProvider.userRole).thenReturn('business');

    await _pumpScreen(tester, authProvider: authProvider);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('logged in admin routes to /admin/dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    when(() => authProvider.isLoggedIn).thenReturn(true);
    when(() => authProvider.authReady).thenAnswer((_) async {});
    when(() => authProvider.userRole).thenReturn('admin');

    await _pumpScreen(tester, authProvider: authProvider);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('ADMIN'), findsOneWidget);
  });

  testWidgets(
      'a stuck authReady (never resolves) still routes after the 3s bound '
      'elapses instead of hanging forever', (tester) async {
    SharedPreferences.setMockInitialValues({});
    when(() => authProvider.isLoggedIn).thenReturn(true);
    when(() => authProvider.authReady).thenAnswer((_) => Completer<void>().future);
    when(() => authProvider.userRole).thenReturn('business');

    await _pumpScreen(tester, authProvider: authProvider);
    // 2s initial delay + 3s authReady bound = 5s worst case.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('AuthProvider throwing falls through to the onboarding/login path',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_seen': true});
    when(() => authProvider.isLoggedIn).thenThrow(StateError('mock mismatch'));

    await _pumpScreen(tester, authProvider: authProvider);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);
  });
}
