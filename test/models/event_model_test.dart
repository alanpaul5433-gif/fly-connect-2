import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Regression coverage for QA finding H-5: "Upcoming Events" showed past
/// events, and Featured duplicated the first Upcoming item.
void main() {
  EventModel eventOn(DateTime date, {bool isFeatured = false, String id = 'evt'}) {
    return EventModel(
      id: id,
      title: 'Event',
      description: '',
      location: '',
      date: date,
      time: '10:00 AM',
      createdBy: 'uid',
      isFeatured: isFeatured,
      createdAt: DateTime.now(),
    );
  }

  group('EventModel.isUpcoming', () {
    test('a date months in the past is not upcoming', () {
      expect(eventOn(DateTime.now().subtract(const Duration(days: 90))).isUpcoming, false);
    });

    test('a date months in the future is upcoming', () {
      expect(eventOn(DateTime.now().add(const Duration(days: 90))).isUpcoming, true);
    });

    test('an event scheduled for today counts as upcoming', () {
      final now = DateTime.now();
      // Same calendar day but stored at midnight, as Firestore dates often are.
      expect(eventOn(DateTime(now.year, now.month, now.day)).isUpcoming, true);
    });

    test('yesterday is not upcoming', () {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      expect(eventOn(yesterday).isUpcoming, false);
    });
  });

  group('events_screen derivation (mirrors EventsScreen.build)', () {
    // Mirrors the `upcoming`/`featured`/`upcomingList` derivation in
    // lib/features/events/events_screen.dart so past events never render
    // and a featured event never also appears in the Upcoming list.
    (List<EventModel> featured, List<EventModel> upcomingList) derive(List<EventModel> events) {
      final upcoming = events.where((e) => e.isUpcoming).toList();
      final featured = upcoming.where((e) => e.isFeatured).toList();
      final upcomingList = upcoming.where((e) => !e.isFeatured).toList();
      return (featured, upcomingList);
    }

    test('past events are excluded from both Featured and Upcoming', () {
      final past = eventOn(DateTime.now().subtract(const Duration(days: 30)), id: 'past');
      final (featured, upcomingList) = derive([past]);
      expect(featured, isEmpty);
      expect(upcomingList, isEmpty);
    });

    test('a featured upcoming event appears in Featured only, not Upcoming', () {
      final soon = eventOn(DateTime.now().add(const Duration(days: 5)),
          isFeatured: true, id: 'soon');
      final (featured, upcomingList) = derive([soon]);
      expect(featured.map((e) => e.id), ['soon']);
      expect(upcomingList, isEmpty);
    });

    test('non-featured upcoming events land only in Upcoming', () {
      final soon = eventOn(DateTime.now().add(const Duration(days: 5)), id: 'soon');
      final (featured, upcomingList) = derive([soon]);
      expect(featured, isEmpty);
      expect(upcomingList.map((e) => e.id), ['soon']);
    });
  });
}
