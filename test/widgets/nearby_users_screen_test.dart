import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/core/constants/app_routes.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/shared/providers/real_providers.dart';
import 'package:flyconnect/features/nearby/nearby_users_screen.dart';

import '../helpers/firebase_mocks.dart';
import '../helpers/fixtures.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}
class _MockSafeCheckProvider extends Mock implements SafeCheckProvider {}

/// NearbyUsersScreen calls FirebaseFirestore.instance directly in
/// _loadNearbyUsers (not provider-mediated), and an unmocked .get() call
/// hangs forever in this test environment rather than throwing (see
/// firebase_mocks.dart). _loadingUsers therefore never flips false, which
/// means the loading spinner keeps animating for the screen's entire
/// lifetime — so pumpAndSettle() never settles anywhere in this file, not
/// just on the initial pump. Use _settle() (bounded pumps) everywhere
/// instead. The map/list body itself can't be exercised without a DI
/// refactor of the screen (out of scope); what IS fully testable without
/// touching Firestore is the SafeCheck bottom sheet, which only depends on
/// the (mocked) SafeCheckProvider and AuthProvider.currentUser — and is the
/// safety-critical part of this screen anyway.
Future<void> _settle(WidgetTester tester, {int times = 10}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<GoRouter> _pumpScreen(
  WidgetTester tester, {
  required _MockAuthProvider authProvider,
  required _MockSafeCheckProvider safeCheckProvider,
}) async {
  // The SafeCheck bottom sheet's content overflows the default 800x600 test
  // surface. Use a tall viewport so it renders without clipping.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/nearby',
    routes: [
      GoRoute(path: '/nearby', builder: (_, __) => const NearbyUsersScreen()),
      GoRoute(path: AppRoutes.safeCheckHistory,
          builder: (_, __) => const Scaffold(body: Text('HISTORY'))),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<SafeCheckProvider>.value(value: safeCheckProvider),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester, times: 5);
  return router;
}

void main() {
  setUpAll(setupFirebaseCoreMocks);

  late _MockAuthProvider authProvider;
  late _MockSafeCheckProvider safeCheckProvider;

  setUp(() {
    authProvider = _MockAuthProvider();
    safeCheckProvider = _MockSafeCheckProvider();
    when(() => safeCheckProvider.latestForUser(any())).thenReturn(null);
  });

  testWidgets('renders without crashing and shows the SafeCheck FAB',
      (tester) async {
    when(() => safeCheckProvider.myLatestCheckIn).thenReturn(null);

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    expect(find.text('Nearby Users'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'SafeCheck'), findsOneWidget);
    expect(find.textContaining('Locations are approximate'), findsOneWidget);
  });

  testWidgets('FAB reads "Update Status" once the user has an active check-in',
      (tester) async {
    when(() => safeCheckProvider.myLatestCheckIn).thenReturn(
      SafeCheckModel(
        id: 'sc_1', userId: 'me', userName: 'Alex', status: 'safe',
        city: 'NYC', createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime(2026, 1, 2),
      ),
    );

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    expect(find.widgetWithText(FloatingActionButton, 'Update Status'), findsOneWidget);
  });

  testWidgets('history icon navigates to SafeCheck history', (tester) async {
    when(() => safeCheckProvider.myLatestCheckIn).thenReturn(null);

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    await tester.tap(find.byTooltip('SafeCheck History'));
    await _settle(tester);

    expect(find.text('HISTORY'), findsOneWidget);
  });

  testWidgets('SafeCheck sheet: submit is disabled until a status is picked',
      (tester) async {
    when(() => safeCheckProvider.myLatestCheckIn).thenReturn(null);

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'SafeCheck'));
    await _settle(tester);

    expect(find.text('Not an emergency service'), findsOneWidget);
    final submitBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Select a status'));
    expect(submitBtn.onPressed, isNull);
  });

  testWidgets('SafeCheck sheet: picking Safe calls checkIn with the right args '
      'and shows a success SnackBar', (tester) async {
    when(() => safeCheckProvider.myLatestCheckIn).thenReturn(null);
    when(() => authProvider.currentUser).thenReturn(
      buildUser(uid: 'me-uid', name: 'Alex Pilot', city: 'Chicago'));
    when(() => safeCheckProvider.checkIn(
          status: any(named: 'status'),
          message: any(named: 'message'),
          city: any(named: 'city'),
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
          userId: any(named: 'userId'),
          userName: any(named: 'userName'),
          userPhotoUrl: any(named: 'userPhotoUrl'),
        )).thenAnswer((_) async {});

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'SafeCheck'));
    await _settle(tester);

    await tester.tap(find.text('Safe'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Share Status'));
    await _settle(tester);

    verify(() => safeCheckProvider.checkIn(
          status: 'safe',
          message: null,
          city: 'Chicago',
          lat: 40.7128,
          lng: -74.0060,
          userId: 'me-uid',
          userName: 'Alex Pilot',
          userPhotoUrl: any(named: 'userPhotoUrl'),
        )).called(1);
    expect(find.text('SafeCheck shared!'), findsOneWidget);
  });

  testWidgets('SafeCheck sheet: checkIn throwing shows an error SnackBar',
      (tester) async {
    when(() => safeCheckProvider.myLatestCheckIn).thenReturn(null);
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'me-uid'));
    when(() => safeCheckProvider.checkIn(
          status: any(named: 'status'),
          message: any(named: 'message'),
          city: any(named: 'city'),
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
          userId: any(named: 'userId'),
          userName: any(named: 'userName'),
          userPhotoUrl: any(named: 'userPhotoUrl'),
        )).thenThrow(Exception('network error'));

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'SafeCheck'));
    await _settle(tester);
    await tester.tap(find.text('Need Help'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Share Status'));
    await _settle(tester);

    expect(find.text('Could not submit SafeCheck. Please try again.'), findsOneWidget);
  });
}
