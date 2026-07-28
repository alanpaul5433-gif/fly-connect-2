import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flyconnect/core/constants/app_routes.dart';
import 'package:flyconnect/core/config/emulator_config.dart' show emulatorHost;

import '../support/auth_helpers.dart';
import '../support/finders.dart';
import '../support/firestore_helpers.dart';
import '../support/seed.dart';

/// End-to-end proof of the admin email-domain allowlist flow:
///   an admin ADDS a domain  →  the app admits a crew user on that domain and
///   the rules persist that user, while a user on a non-allowlisted domain is
///   blocked in both the app UI and (authoritatively) the Firestore rules.
///
/// The domain under test is injected so this can target any domain:
///   flutter test integration_test/flows/domain_allowlist_admin_test.dart \
///     --dart-define=USE_FIREBASE_EMULATOR=true --dart-define=TEST_DOMAIN=flyconnect.co
///
/// Runs against the emulator (seed sets signup_gate.enforced=true). CRITICAL:
/// the app and seeder must share ONE emulator project namespace — the app is
/// hardcoded to projectId flyconnect-ab4f2 (firebase_options.dart), so the
/// runner pins the emulator + seeder to the same id; otherwise the app reads an
/// empty DB and the gate silently reads OFF (guarded by the boot canary below).
///
/// Design note: this test never drives the app into an authenticated screen
/// (/home, /dashboard). Those mount web-oriented layouts and real-time
/// `.snapshots()` listeners whose incidental overflow / permission-denied errors
/// would fail the test for reasons unrelated to the gate. Instead it asserts:
///   (a) the client gate DECISION at the signup wizard (advance vs stay), and
///   (b) real account creation + the authoritative server rule, via isolated
///       Firebase app instances that never touch the main app's navigation.
const String kTestDomain =
    String.fromEnvironment('TEST_DOMAIN', defaultValue: 'flyconnect.co');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'admin adds $kTestDomain → app admits & rules persist a crew user on it; '
      'a disallowed domain is blocked in UI and by rules', (tester) async {
    // app.main() installs a custom ErrorWidget.builder (ErrorBoundary.install),
    // and the framework fails the FIRST test in a process if it is left
    // changed. Restore it in a finally — BEFORE the framework's end-of-body
    // check — so it can't mask the gate result (addTearDown runs too late).
    final savedErrorBuilder = ErrorWidget.builder;
    try {
      await _runDomainAllowlistFlow(tester);
    } finally {
      ErrorWidget.builder = savedErrorBuilder;
    }
  });
}

Future<void> _runDomainAllowlistFlow(WidgetTester tester) async {
  final runId = uniqueRunId();
  await bootToLogin(tester);

  // ── Canary: the app can SEE the seeded, enforced gate (same namespace) ──
  final gate = await db.collection('app_config').doc('signup_gate').get();
  expect(gate.data()?['enforced'], true,
      reason: 'gate must be enforced AND visible to the app — otherwise the '
          'app/seed emulator project namespaces are mismatched');

  // ── Admin adds the testing domain (isolated app, real isAdmin() rule) ──
  final adminApp = await _isolatedApp('domainAdminWriter');
  final adminAuth = FirebaseAuth.instanceFor(app: adminApp);
  await adminAuth.signInWithEmailAndPassword(
      email: kAdminEmail, password: kTestPassword);
  await FirebaseFirestore.instanceFor(app: adminApp)
      .collection('allowed_domains')
      .doc(kTestDomain)
      .set({
    'domain': kTestDomain, // rule: data.domain == domainId
    'enabled': true,
    'addedBy': adminAuth.currentUser!.uid, // rule: == auth.uid (must be admin)
    'addedAt': FieldValue.serverTimestamp(), // rule: == request.time
  });
  // Read back through the MAIN app (allowed_domains has public get) to prove
  // the write landed in the shared namespace.
  final domainDoc =
      await pollForDoc(db.collection('allowed_domains').doc(kTestDomain));
  expect(domainDoc.data()!['enabled'], true,
      reason: 'admin add-domain write must land and be enabled');

  // ── APP CLIENT GATE — negative first: a disallowed domain stays on step 1 ──
  await _fillCrewStep1AndContinue(tester,
      name: 'Nope Nobody', email: 'intruder_$runId@$kDisallowedDomain');
  await pumpFor(tester, const Duration(seconds: 2));
  expect(F.signupCreate, findsNothing,
      reason: 'the app must not advance a disallowed domain past step 1');
  expect(FirebaseAuth.instance.currentUser, isNull,
      reason: 'no account may be created for a disallowed domain');

  // ── APP CLIENT GATE — positive: the new domain advances to step 2 ──
  await goTo(tester, AppRoutes.login); // force a fresh wizard instance
  await _fillCrewStep1AndContinue(tester,
      name: 'Casey NewCrew', email: 'crew_$runId@$kTestDomain');
  await pumpUntil(tester, F.signupCreate);
  expect(F.signupCreate, findsOneWidget,
      reason: 'the app must admit an allowlisted domain to step 2');

  // ── SERVER RULE + REAL CREATION — positive: a crew user on the domain is
  //    actually created and persisted with role:user (authoritative gate) ──
  final crewApp = await _isolatedApp('crewWriter');
  final crewAuth = FirebaseAuth.instanceFor(app: crewApp);
  final crewFs = FirebaseFirestore.instanceFor(app: crewApp);
  await crewAuth.createUserWithEmailAndPassword(
      email: 'created_$runId@$kTestDomain', password: 'Test1234!');
  final crewUid = crewAuth.currentUser!.uid;
  await crewFs.collection('users').doc(crewUid).set(_crewDoc('Created Crew'));
  final createdSnap = await crewFs.collection('users').doc(crewUid).get();
  expect(createdSnap.data()!['role'], 'user',
      reason: 'the rules must persist a crew user on an allowlisted domain');

  // ── SERVER RULE — negative: a disallowed-domain profile create is denied ──
  final evilApp = await _isolatedApp('evilWriter');
  final evilAuth = FirebaseAuth.instanceFor(app: evilApp);
  final evilFs = FirebaseFirestore.instanceFor(app: evilApp);
  await evilAuth.createUserWithEmailAndPassword(
      email: 'blocked_$runId@$kDisallowedDomain', password: 'Test1234!');
  await expectLater(
    evilFs.collection('users').doc(evilAuth.currentUser!.uid).set(
          _crewDoc('Blocked Intruder'),
        ),
    throwsA(isA<FirebaseException>()
        .having((e) => e.code, 'code', 'permission-denied')),
    reason: 'the rules must reject a profile create on a non-allowlisted '
        'domain — this is the authoritative gate, independent of the UI',
  );
}

/// Spins up an isolated, emulator-wired Firebase app so a write can run as a
/// specific signed-in identity WITHOUT affecting the main app's auth state or
/// navigation. Never deleted during the run: on Android deleting a secondary
/// app tears down the shared Firestore emulator channel and makes the main
/// app's next read throw "FirebaseApp was deleted".
Future<FirebaseApp> _isolatedApp(String name) async {
  final a =
      await Firebase.initializeApp(name: name, options: Firebase.app().options);
  FirebaseFirestore.instanceFor(app: a).useFirestoreEmulator(emulatorHost, 8080);
  await FirebaseAuth.instanceFor(app: a).useAuthEmulator(emulatorHost, 9099);
  return a;
}

/// Drives the crew signup wizard step 1 and taps Continue (which runs the
/// client domain gate). Does NOT tap Create, so no account is made and the app
/// never navigates to /home.
Future<void> _fillCrewStep1AndContinue(
  WidgetTester tester, {
  required String name,
  required String email,
}) async {
  await goTo(tester, AppRoutes.signup);
  await pumpUntil(tester, F.signupRoleUser);
  await tester.tap(F.signupRoleUser);
  await tester.pump();
  await tester.enterText(F.signupName, name);
  await tester.enterText(F.signupEmail, email);
  await tester.enterText(F.signupPassword, 'Test1234!');
  await tester.pump();
  await tester.tap(F.signupDob);
  await pumpUntil(tester, F.datePickerOk);
  await tester.tap(F.datePickerOk);
  await pumpFor(tester, const Duration(milliseconds: 400));
  await tester.ensureVisible(F.signupTerms);
  await tester.tap(F.signupTerms);
  await tester.pump();
  await tester.ensureVisible(F.signupContinue);
  await tester.tap(F.signupContinue);
}

/// A minimal crew profile doc that satisfies every non-domain clause of the
/// users `create` rule, so a permission-denied can only be the domain gate.
Map<String, dynamic> _crewDoc(String name) => {
      'role': 'user',
      'isBanned': false,
      'isVerified': false,
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    };
