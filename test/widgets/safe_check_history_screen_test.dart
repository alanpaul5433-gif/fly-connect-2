import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/shared/providers/real_providers.dart';
import 'package:flyconnect/features/nearby/safe_check_history_screen.dart';

import '../helpers/fixtures.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}
class _MockSafeCheckProvider extends Mock implements SafeCheckProvider {}

SafeCheckModel _checkIn({
  required String id,
  required String userId,
  required String status,
  required DateTime createdAt,
  DateTime? expiresAt,
  String? message,
}) =>
    SafeCheckModel(
      id: id, userId: userId, userName: 'Alex', status: status,
      message: message, city: 'NYC', createdAt: createdAt, expiresAt: expiresAt,
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _MockAuthProvider authProvider,
  required _MockSafeCheckProvider safeCheckProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<SafeCheckProvider>.value(value: safeCheckProvider),
      ],
      child: const MaterialApp(home: SafeCheckHistoryScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _MockAuthProvider authProvider;
  late _MockSafeCheckProvider safeCheckProvider;

  setUp(() {
    authProvider = _MockAuthProvider();
    safeCheckProvider = _MockSafeCheckProvider();
    when(() => authProvider.currentUser).thenReturn(buildUser(uid: 'me'));
  });

  testWidgets('shows the empty state when the user has no check-ins',
      (tester) async {
    when(() => safeCheckProvider.checkIns).thenReturn(const []);

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    expect(find.text('No check-ins yet'), findsOneWidget);
  });

  testWidgets('only shows the current user\'s check-ins, not other users\'',
      (tester) async {
    when(() => safeCheckProvider.checkIns).thenReturn([
      _checkIn(id: 'mine', userId: 'me', status: 'safe', createdAt: DateTime(2026, 1, 1)),
      _checkIn(id: 'theirs', userId: 'someone-else', status: 'unsure', createdAt: DateTime(2026, 1, 1)),
    ]);

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    expect(find.text('Safe'), findsOneWidget);
    expect(find.text('Unsure'), findsNothing);
  });

  testWidgets('sorts check-ins newest first', (tester) async {
    when(() => safeCheckProvider.checkIns).thenReturn([
      _checkIn(id: 'old', userId: 'me', status: 'safe', createdAt: DateTime(2026, 1, 1)),
      _checkIn(id: 'new', userId: 'me', status: 'need_help', createdAt: DateTime(2026, 6, 1)),
    ]);

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    final statusTexts = tester.widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((t) => t == 'Safe' || t == 'Need Help')
        .toList();
    expect(statusTexts, ['Need Help', 'Safe']); // newest (need_help) first
  });

  testWidgets('active check-in shows "Active", expired shows "Expired"',
      (tester) async {
    when(() => safeCheckProvider.checkIns).thenReturn([
      _checkIn(id: 'active', userId: 'me', status: 'safe',
          createdAt: DateTime(2026, 1, 1),
          expiresAt: DateTime.now().add(const Duration(hours: 1))),
      _checkIn(id: 'expired', userId: 'me', status: 'unsure',
          createdAt: DateTime(2025, 1, 1),
          expiresAt: DateTime(2025, 1, 2)),
    ]);

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
  });

  testWidgets('shows the check-in message when present', (tester) async {
    when(() => safeCheckProvider.checkIns).thenReturn([
      _checkIn(id: 'mine', userId: 'me', status: 'safe',
          createdAt: DateTime(2026, 1, 1), message: 'All good here!'),
    ]);

    await _pumpScreen(tester, authProvider: authProvider, safeCheckProvider: safeCheckProvider);

    expect(find.text('All good here!'), findsOneWidget);
  });
}
