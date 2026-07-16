import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/event_provider.dart';
import 'package:flyconnect/shared/providers/auth_provider.dart';
import 'package:flyconnect/features/business/event_management_screen.dart';

import '../helpers/fixtures.dart';
import '../helpers/firebase_mocks.dart';

class _MockEventProvider extends Mock implements EventProvider {}

class _MockAuthProvider extends Mock implements AuthProvider {}

/// `_loadAttendees` (pre-existing, direct `FirebaseFirestore.instance` call,
/// not part of this session's work) never resolves in this test environment:
/// with no mocked cloud_firestore channel, the underlying platform call
/// hangs rather than throwing, so `_loadingAttendees` never flips to false
/// and its CircularProgressIndicator animates forever. `pumpAndSettle()`
/// would time out waiting for that animation to stop, so every interaction
/// here uses a bounded pump sequence instead — long enough for Material
/// transition/animation durations (~300ms) to finish, short enough to never
/// wait on the doomed Firestore future.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Defaults [viewerUid] to the event's own creator ('biz-1') so the A4
/// ownership guard (added alongside this test file) doesn't block the
/// pre-existing edit/approve/decline tests below — those exercise the
/// owner's view. The guard itself is covered by its own tests further down.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required EventProvider eventProvider,
  String viewerUid = 'biz-1',
}) async {
  final authProvider = _MockAuthProvider();
  when(() => authProvider.currentUser).thenReturn(buildUser(uid: viewerUid));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<EventProvider>.value(value: eventProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: MaterialApp(home: EventManagementScreen(event: buildEvent(
        id: 'evt-1', title: 'Layover Meetup', description: 'Grab drinks',
        location: 'Gate 12 Lounge', createdBy: 'biz-1'))),
    ),
  );
  await _settle(tester);
}

void main() {
  setUpAll(() async => setupFirebaseCoreMocks());

  late _MockEventProvider eventProvider;

  setUp(() {
    eventProvider = _MockEventProvider();
  });

  group('Ownership guard (A4)', () {
    testWidgets('non-owner, non-admin sees permission-denied screen and no controls',
        (tester) async {
      await _pumpScreen(tester, eventProvider: eventProvider, viewerUid: 'stranger-uid');

      expect(find.text("You don't have permission to manage this event."),
          findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('Approved (0)'), findsNothing);
    });

    testWidgets('owner (createdBy == uid) sees full management UI',
        (tester) async {
      await _pumpScreen(tester, eventProvider: eventProvider, viewerUid: 'biz-1');

      expect(find.text("You don't have permission to manage this event."),
          findsNothing);
      expect(find.text('Approved (0)'), findsOneWidget);
    });
  });

  testWidgets('pumps without crashing despite the pre-existing direct Firestore call',
      (tester) async {
    await _pumpScreen(tester, eventProvider: eventProvider);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TabController has 3 tabs labeled Approved/Pending/Declined with counts',
      (tester) async {
    await _pumpScreen(tester, eventProvider: eventProvider);

    expect(find.text('Approved (0)'), findsOneWidget);
    expect(find.text('Pending (0)'), findsOneWidget);
    expect(find.text('Declined (0)'), findsOneWidget);
  });

  testWidgets('Edit Event sheet pre-fills title/description/location from widget.event',
      (tester) async {
    await _pumpScreen(tester, eventProvider: eventProvider);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await _settle(tester);

    expect(find.widgetWithText(TextField, 'Layover Meetup'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Grab drinks'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Gate 12 Lounge'), findsOneWidget);
  });

  group('Save Changes', () {
    testWidgets('calls updateEvent with trimmed fields and shows a success SnackBar',
        (tester) async {
      when(() => eventProvider.updateEvent('evt-1',
          title: any(named: 'title'),
          description: any(named: 'description'),
          location: any(named: 'location'))).thenAnswer((_) async {});

      await _pumpScreen(tester, eventProvider: eventProvider);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await _settle(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Layover Meetup'), '  New Title  ');
      await tester.tap(find.text('Save Changes'));
      await _settle(tester);

      verify(() => eventProvider.updateEvent('evt-1',
          title: 'New Title', description: 'Grab drinks', location: 'Gate 12 Lounge')).called(1);
      expect(find.text('Event updated successfully'), findsOneWidget);
    });

    testWidgets('a blanked field falls back to the previous value instead of writing empty',
        (tester) async {
      when(() => eventProvider.updateEvent('evt-1',
          title: any(named: 'title'),
          description: any(named: 'description'),
          location: any(named: 'location'))).thenAnswer((_) async {});

      await _pumpScreen(tester, eventProvider: eventProvider);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await _settle(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Layover Meetup'), '');
      await tester.tap(find.text('Save Changes'));
      await _settle(tester);

      verify(() => eventProvider.updateEvent('evt-1',
          title: 'Layover Meetup', description: 'Grab drinks', location: 'Gate 12 Lounge')).called(1);
    });

    testWidgets('updateEvent throwing shows an error SnackBar', (tester) async {
      when(() => eventProvider.updateEvent('evt-1',
          title: any(named: 'title'),
          description: any(named: 'description'),
          location: any(named: 'location'))).thenThrow(Exception('fail'));

      await _pumpScreen(tester, eventProvider: eventProvider);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await _settle(tester);
      await tester.tap(find.text('Save Changes'));
      await _settle(tester);

      expect(find.text('Could not update event. Try again.'), findsOneWidget);
    });
  });
}
