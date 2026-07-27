import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flyconnect/core/constants/app_routes.dart';
import 'package:flyconnect/core/utils/app_router.dart';
import 'package:flyconnect/main.dart' as app;
import 'package:flyconnect/shared/providers/auth_provider.dart';

import 'finders.dart';

/// Pumps in fixed steps until [finder] matches, or fails loudly on timeout.
///
/// Used instead of [WidgetTester.pumpAndSettle] because the app has
/// continuously-running animations (splash logo, match card, spinners) that
/// would make `pumpAndSettle` hang forever.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 150),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  // Fail with a finder-named message.
  expect(finder, findsWidgets,
      reason: 'pumpUntil timed out waiting for: $finder');
}

/// Pumps for a fixed wall-ish duration in small steps (lets async provider work
/// and route transitions land without depending on any particular finder).
Future<void> pumpFor(
  WidgetTester tester,
  Duration duration, {
  Duration step = const Duration(milliseconds: 100),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    await tester.pump(step);
    elapsed += step;
  }
}

/// Reads a provider off the live element tree. Providers are ancestors of the
/// [MaterialApp], so its element can resolve any of them.
T readProvider<T>(WidgetTester tester) =>
    Provider.of<T>(tester.element(find.byType(MaterialApp)), listen: false);

/// Navigates via the app's own GoRouter (module-level singleton) — no
/// BuildContext plumbing, works for deep links like /posts/:id and /users/:id.
Future<void> deepLink(WidgetTester tester, String location) async {
  appRouter.push(location);
  await pumpFor(tester, const Duration(milliseconds: 600));
}

Future<void> goTo(WidgetTester tester, String location) async {
  appRouter.go(location);
  await pumpFor(tester, const Duration(milliseconds: 600));
}

/// Boots the app and lands on the LoginScreen, guaranteeing a clean,
/// signed-out starting point regardless of what a previous test left behind.
///
/// Splash routes an unauthenticated user to /onboarding on a fresh install, so
/// rather than depend on onboarding state we force-navigate to /login (a public
/// route) once Firebase is up.
Future<void> bootToLogin(WidgetTester tester) async {
  await app.main();
  await pumpFor(tester, const Duration(seconds: 2)); // Firebase init + splash

  if (FirebaseAuth.instance.currentUser != null) {
    await FirebaseAuth.instance.signOut();
    await pumpFor(tester, const Duration(milliseconds: 500));
  }

  appRouter.go(AppRoutes.login);
  await pumpUntil(tester, F.loginWelcome);
}

/// Enters credentials on the LoginScreen and submits. Pumps until the login
/// screen is gone (navigation to the role-appropriate landing screen). The
/// caller asserts which screen that is.
Future<void> loginAs(WidgetTester tester, String email, String password) async {
  await pumpUntil(tester, F.loginWelcome);
  await tester.enterText(F.loginEmail, email);
  await tester.enterText(F.loginPassword, password);
  await tester.tap(F.loginSubmit);
  // Login is a network round-trip + role fetch + redirect. Wait for the login
  // screen to disappear (navigation to the role-appropriate landing screen).
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (F.loginWelcome.evaluate().isEmpty) return;
  }
  expect(F.loginWelcome, findsNothing,
      reason: 'Still on LoginScreen after login as $email');
}

/// Signs the current user out through the real AuthProvider and returns to
/// /login. Uses the provider (not a raw FirebaseAuth.signOut) so app state
/// (currentUser, subscriptions) tears down the way production does.
Future<void> logout(WidgetTester tester) async {
  final auth = readProvider<AuthProvider>(tester);
  await auth.logout();
  await pumpFor(tester, const Duration(milliseconds: 400));
  appRouter.go(AppRoutes.login);
  await pumpUntil(tester, F.loginWelcome);
}

/// Drives the crew (role 'user') signup wizard end-to-end on an allowed
/// [email] domain. Assumes the caller starts on the LoginScreen.
///
/// Leaves the app wherever signup routed it (crew → /home). The DOB picker
/// opens on a 25-year-old default, so we just confirm it.
Future<void> signUpCrew(
  WidgetTester tester, {
  required String name,
  required String email,
  required String password,
}) async {
  await pumpUntil(tester, F.loginWelcome);
  // Navigate to the signup screen via the router. (The on-screen "Sign Up" link
  // is a TextSpan inside a RichText, which find.text can't target, so we drive
  // the same route the link's context.go(AppRoutes.signup) would.)
  await goTo(tester, AppRoutes.signup);
  await pumpUntil(tester, F.signupRoleUser);

  await tester.tap(F.signupRoleUser); // crew is default, tap to be explicit
  await tester.pump();
  await tester.enterText(F.signupName, name);
  await tester.enterText(F.signupEmail, email);
  await tester.enterText(F.signupPassword, password);
  await tester.pump();

  // Date of birth — open picker, confirm the 18+ default.
  await tester.tap(F.signupDob);
  await pumpUntil(tester, F.datePickerOk);
  await tester.tap(F.datePickerOk);
  await pumpFor(tester, const Duration(milliseconds: 400));

  // Consent + continue (Continue runs the domain allowlist check).
  await tester.ensureVisible(F.signupTerms);
  await tester.tap(F.signupTerms);
  await tester.pump();
  // The crew form is long — Continue can be below the fold, so scroll it into
  // view before tapping or the hit test misses.
  await tester.ensureVisible(F.signupContinue);
  await tester.tap(F.signupContinue);
  // Domain check is a Firestore round-trip; wait for step 2 to appear.
  await pumpUntil(tester, F.signupCreate);

  await tester.ensureVisible(F.signupCreate);
  await tester.tap(F.signupCreate);
  await pumpFor(tester, const Duration(seconds: 2));
}
