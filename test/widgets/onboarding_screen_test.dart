import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flyconnect/core/constants/app_routes.dart';
import 'package:flyconnect/features/onboarding/onboarding_screen.dart';

Future<GoRouter> _pumpScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});

  final router = GoRouter(
    initialLocation: AppRoutes.onboarding,
    routes: [
      GoRoute(path: AppRoutes.onboarding, builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const Scaffold(body: Text('LOGIN'))),
    ],
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  // The background images are real network URLs that can't resolve in a
  // test environment; a couple of pumps lets Image.network's errorBuilder
  // settle instead of leaving a pending frame from the failed load.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return router;
}

void main() {
  testWidgets('renders the first onboarding page', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Embark on a Journey'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Next'), findsOneWidget);
  });

  testWidgets('Next advances through all three pages, then shows Get Started',
      (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.pumpAndSettle();
    expect(find.text('Craft Your Journey'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Next'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.pumpAndSettle();
    expect(find.text('Seamless Connections'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Get Started'), findsOneWidget);
  });

  testWidgets('Get Started persists onboarding_seen and navigates to login',
      (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_seen'), true);
  });

  testWidgets('swiping the page view also advances the page', (tester) async {
    await _pumpScreen(tester);

    await tester.drag(find.byType(PageView), const Offset(-800, 0));
    await tester.pumpAndSettle();

    expect(find.text('Craft Your Journey'), findsOneWidget);
  });
}
