import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/core/constants/app_routes.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/shared/widgets/shared_widgets.dart';
import 'package:flyconnect/features/auth/forgot_password_screen.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

/// Pumps the real ForgotPasswordScreen. A prior version of this file tested a
/// hand-rolled mirror of the screen's logic instead of the screen itself,
/// which can't catch a real regression in the actual widget — replaced with
/// a pump of the real screen, matching the rest of the auth-flow suite.
Future<GoRouter> _pumpScreen(
  WidgetTester tester, {
  required _MockAuthProvider authProvider,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.forgotPassword,
    routes: [
      GoRoute(path: AppRoutes.forgotPassword, builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
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

  testWidgets('empty email shows inline error, no resetPassword call', (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Send Reset Link'));
    await tester.pump();

    expect(find.text('Please enter your email address.'), findsOneWidget);
    verifyNever(() => authProvider.resetPassword(any()));
  });

  testWidgets('invalid email format shows inline error', (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField), 'notanemail');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Send Reset Link'));
    await tester.pump();

    expect(find.text('Please enter a valid email address.'), findsOneWidget);
    verifyNever(() => authProvider.resetPassword(any()));
  });

  testWidgets('valid email calls resetPassword and shows the success screen',
      (tester) async {
    when(() => authProvider.resetPassword('alex@delta.com'))
        .thenAnswer((_) async => true);

    await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField), 'alex@delta.com');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Send Reset Link'));
    await tester.pumpAndSettle();

    verify(() => authProvider.resetPassword('alex@delta.com')).called(1);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('alex@delta.com'), findsOneWidget);
  });

  testWidgets('resetPassword failure shows AuthProvider.error, stays on the form',
      (tester) async {
    when(() => authProvider.resetPassword(any())).thenAnswer((_) async => false);
    when(() => authProvider.error).thenReturn('No account found for that email.');

    await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField), 'nobody@delta.com');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Send Reset Link'));
    await tester.pumpAndSettle();

    expect(find.text('No account found for that email.'), findsOneWidget);
    expect(find.text('Check your email'), findsNothing);
  });

  testWidgets('"Resend email" on the success screen returns to the form',
      (tester) async {
    when(() => authProvider.resetPassword(any())).thenAnswer((_) async => true);

    await _pumpScreen(tester, authProvider: authProvider);
    await tester.enterText(find.byType(TextField), 'alex@delta.com');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Send Reset Link'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Resend email'));
    await tester.pumpAndSettle();

    expect(find.text('Send Reset Link'), findsOneWidget); // back on the form
  });

  testWidgets('back arrow navigates to login', (tester) async {
    final router = await _pumpScreen(tester, authProvider: authProvider);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
  });
}
