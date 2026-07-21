import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/event_provider.dart';
import 'package:flyconnect/shared/providers/user_provider.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/features/events/event_details_screen.dart';

import '../helpers/fixtures.dart';

class _MockEventProvider extends Mock implements EventProvider {}

class _MockUserProvider extends Mock implements UserProvider {}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _MockEventProvider eventProvider,
  UserModel? organizer,
  String eventId = 'evt-1',
}) async {
  final userProvider = _MockUserProvider();
  when(() => userProvider.fetchUser(any())).thenAnswer((_) async => organizer);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<EventProvider>.value(value: eventProvider),
        ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      ],
      child: MaterialApp(home: EventDetailsScreen(eventId: eventId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _MockEventProvider eventProvider;

  setUp(() {
    eventProvider = _MockEventProvider();
  });

  group('Organizer identity (B1)', () {
    testWidgets('shows "Hosted by" row with a verified badge for a verified business organizer',
        (tester) async {
      final event = buildEvent(id: 'evt-1', createdBy: 'biz-1');
      when(() => eventProvider.events).thenReturn([event]);
      when(() => eventProvider.hasRsvped('evt-1')).thenAnswer((_) async => false);

      await _pumpScreen(tester,
          eventProvider: eventProvider,
          organizer: buildUser(uid: 'biz-1', name: 'Sky Lounge NYC', role: 'business', isVerified: true));

      expect(find.textContaining('Hosted by Sky Lounge NYC'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);
    });

    testWidgets('no organizer row when the creator cannot be resolved', (tester) async {
      final event = buildEvent(id: 'evt-1', createdBy: 'ghost-uid');
      when(() => eventProvider.events).thenReturn([event]);
      when(() => eventProvider.hasRsvped('evt-1')).thenAnswer((_) async => false);

      await _pumpScreen(tester, eventProvider: eventProvider);

      expect(find.textContaining('Hosted by'), findsNothing);
    });

    testWidgets('event not found shows the empty state, not a crash', (tester) async {
      when(() => eventProvider.events).thenReturn(const []);

      await _pumpScreen(tester, eventProvider: eventProvider, eventId: 'missing');

      expect(find.text('Event not found'), findsOneWidget);
    });
  });
}
