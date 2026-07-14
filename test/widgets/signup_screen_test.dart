import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/core/constants/app_routes.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/shared/widgets/shared_widgets.dart';
import 'package:flyconnect/features/auth/signup_screen.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

Future<GoRouter> _pumpScreen(
  WidgetTester tester, {
  required _MockAuthProvider authProvider,
}) async {
  // Tall viewport so the full scrollable form (down to the social buttons)
  // renders without clipping — avoids tap hit-test misses below the fold.
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: AppRoutes.signup,
    routes: [
      GoRoute(path: AppRoutes.signup, builder: (_, __) => const SignupScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
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

/// Confirms the date picker on its pre-filled initialDate (now - 25 years),
/// which is always 18+, satisfying the age gate without needing to navigate
/// the calendar UI.
Future<void> _pickAdultDob(WidgetTester tester) async {
  await tester.tap(find.textContaining('Date of birth'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _agreeToTerms(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
}

void main() {
  late _MockAuthProvider authProvider;

  setUp(() {
    authProvider = _MockAuthProvider();
  });

  testWidgets('missing required fields (crew) shows a snackbar, stays on step 1',
      (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please fill in all required fields'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget); // still step 1's title
  });

  testWidgets('invalid email format shows a snackbar', (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField).at(0), 'Alex Pilot');
    await tester.enterText(find.byType(TextField).at(1), 'notanemail');
    await tester.enterText(find.byType(TextField).at(3), 'Password123');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid email address'), findsOneWidget);
  });

  testWidgets('password under 8 characters shows a snackbar', (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField).at(0), 'Alex Pilot');
    await tester.enterText(find.byType(TextField).at(1), 'alex@delta.com');
    await tester.enterText(find.byType(TextField).at(3), 'short');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
  });

  testWidgets('missing date of birth (crew) shows a snackbar', (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField).at(0), 'Alex Pilot');
    await tester.enterText(find.byType(TextField).at(1), 'alex@delta.com');
    await tester.enterText(find.byType(TextField).at(3), 'Password123');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your date of birth'), findsOneWidget);
  });

  testWidgets('unchecked consent shows a snackbar even with everything else valid',
      (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField).at(0), 'Alex Pilot');
    await tester.enterText(find.byType(TextField).at(1), 'alex@delta.com');
    await tester.enterText(find.byType(TextField).at(3), 'Password123');
    await _pickAdultDob(tester);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('agree to the Terms of Service'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget); // still step 1
  });

  testWidgets('valid crew signup advances to step 2 (airline/position fields)',
      (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.enterText(find.byType(TextField).at(0), 'Alex Pilot');
    await tester.enterText(find.byType(TextField).at(1), 'alex@delta.com');
    await tester.enterText(find.byType(TextField).at(3), 'Password123');
    await _pickAdultDob(tester);
    await _agreeToTerms(tester);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Your Profile'), findsOneWidget);
    expect(find.textContaining('Select your airline'), findsOneWidget);
  });

  testWidgets('business role hides name/phone/DOB and advances to business step 2',
      (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    await tester.tap(find.text('Business'));
    await tester.pump();

    // Business step 1 is just Email + Password (2 fields, not 4).
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).at(0), 'lounge@delta.com');
    await tester.enterText(find.byType(TextField).at(1), 'Password123');
    await _agreeToTerms(tester);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Your Business'), findsOneWidget);
    expect(find.text('Business Name'), findsOneWidget);
  });

  testWidgets('Google signup without consent shows a snackbar and never calls signInWithGoogle',
      (tester) async {
    await _pumpScreen(tester, authProvider: authProvider);

    final googleBtn = find.byType(SocialLoginButton).at(0);
    await tester.tap(googleBtn);
    await tester.pumpAndSettle();

    expect(find.textContaining('agree to the Terms of Service'), findsOneWidget);
    verifyNever(() => authProvider.signInWithGoogle(role: any(named: 'role')));
  });

  testWidgets('Google signup with consent calls signInWithGoogle(role) and routes home',
      (tester) async {
    when(() => authProvider.signInWithGoogle(role: any(named: 'role')))
        .thenAnswer((_) async => true);
    when(() => authProvider.userRole).thenReturn('user');

    await _pumpScreen(tester, authProvider: authProvider);
    await _agreeToTerms(tester);

    await tester.tap(find.byType(SocialLoginButton).at(0));
    await tester.pumpAndSettle();

    verify(() => authProvider.signInWithGoogle(role: 'user')).called(1);
    expect(find.text('HOME'), findsOneWidget);
  });
}
