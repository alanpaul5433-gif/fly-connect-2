import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/core/constants/app_routes.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/shared/widgets/shared_widgets.dart';
import 'package:flyconnect/features/auth/login_screen.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

/// Pumps LoginScreen behind a real GoRouter stack covering every route the
/// screen can navigate to, so context.go/push calls resolve for real instead
/// of throwing "no matching route".
Future<GoRouter> _pumpScreen(
  WidgetTester tester, {
  required _MockAuthProvider authProvider,
}) async {
  // The default 800x600 test surface clips this screen's scrollable content
  // (social buttons, Sign Up link) below the fold, causing tap hit-test
  // misses. Use a tall viewport so everything renders without scrolling.
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: AppRoutes.signup, builder: (_, __) => const Scaffold(body: Text('SIGNUP'))),
      GoRoute(path: AppRoutes.forgotPassword, builder: (_, __) => const Scaffold(body: Text('FORGOT'))),
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
  await tester.pumpAndSettle();
  return router;
}

void main() {
  late _MockAuthProvider authProvider;

  setUp(() {
    authProvider = _MockAuthProvider();
  });

  testWidgets('empty email and password shows inline error, no login call',
      (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Login'));
    await tester.pump();

    expect(find.textContaining('Please enter email and password'), findsOneWidget);
    verifyNever(() => authProvider.login(any(), any()));
  });

  testWidgets('invalid email format shows inline error, no login call',
      (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField).at(0), 'notanemail');
    await tester.enterText(find.byType(TextField).at(1), 'somepassword');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Login'));
    await tester.pump();

    expect(find.textContaining('valid email'), findsOneWidget);
    verifyNever(() => authProvider.login(any(), any()));
  });

  testWidgets('valid credentials call login and route crew to /home',
      (tester) async {
    when(() => authProvider.login('alex@delta.com', 'Password123'))
        .thenAnswer((_) async => true);
    when(() => authProvider.userRole).thenReturn('user');

    final router = await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField).at(0), 'alex@delta.com');
    await tester.enterText(find.byType(TextField).at(1), 'Password123');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Login'));
    await tester.pumpAndSettle();

    verify(() => authProvider.login('alex@delta.com', 'Password123')).called(1);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
  });

  testWidgets('business role routes to /dashboard on success', (tester) async {
    when(() => authProvider.login(any(), any())).thenAnswer((_) async => true);
    when(() => authProvider.userRole).thenReturn('business');

    final router = await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField).at(0), 'biz@delta.com');
    await tester.enterText(find.byType(TextField).at(1), 'Password123');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Login'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/dashboard');
  });

  testWidgets('admin role routes to /admin/dashboard on success', (tester) async {
    when(() => authProvider.login(any(), any())).thenAnswer((_) async => true);
    when(() => authProvider.userRole).thenReturn('admin');

    final router = await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField).at(0), 'admin@flyconnect.com');
    await tester.enterText(find.byType(TextField).at(1), 'Password123');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Login'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/admin/dashboard');
  });

  testWidgets('failed login shows AuthProvider.error and does not navigate',
      (tester) async {
    when(() => authProvider.login(any(), any())).thenAnswer((_) async => false);
    when(() => authProvider.error).thenReturn('Invalid credentials.');

    final router = await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField).at(0), 'alex@delta.com');
    await tester.enterText(find.byType(TextField).at(1), 'wrongpass');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid credentials.'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
  });

  testWidgets('Forgot password link navigates to the forgot-password route',
      (tester) async {
    // This link uses context.push (not go), which layers the destination on
    // top of the Navigator stack rather than replacing GoRouter's tracked
    // location — so assert on the pushed screen's content, not on uri.path.
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('FORGOT'), findsOneWidget);
  });

  testWidgets('Sign Up text navigates to the signup route', (tester) async {
    final router = await _pumpScreen(tester, authProvider: authProvider);

    final finder = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('Sign Up'));
    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.signup);
  });

  testWidgets('Google sign-in success calls signInWithGoogle and routes home',
      (tester) async {
    when(() => authProvider.signInWithGoogle())
        .thenAnswer((_) async => true);
    when(() => authProvider.userRole).thenReturn('user');

    final router = await _pumpScreen(tester, authProvider: authProvider);

    final finder = find.byType(SocialLoginButton).at(0);
    await tester.tap(finder);
    await tester.pumpAndSettle();

    verify(() => authProvider.signInWithGoogle()).called(1);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
  });

  testWidgets('Apple sign-in failure shows error and stays on login',
      (tester) async {
    when(() => authProvider.signInWithApple())
        .thenAnswer((_) async => false);
    when(() => authProvider.error).thenReturn('Apple sign-in cancelled.');

    final router = await _pumpScreen(tester, authProvider: authProvider);

    final finder = find.byType(SocialLoginButton).at(1);
    await tester.tap(finder);
    await tester.pumpAndSettle();

    verify(() => authProvider.signInWithApple()).called(1);
    expect(find.text('Apple sign-in cancelled.'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
  });
}
