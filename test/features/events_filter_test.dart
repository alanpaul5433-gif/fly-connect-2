import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/events/events_filter.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Coverage for H4 — the Events filter tabs did nothing.
///
/// `TabBar(... onTap: (_) {})` and the list below it was always the same
/// derivation, so All / Upcoming / Featured rendered byte-identical content
/// (confirmed by pixel-diffing screenshots during the device audit).
void main() {
  EventModel event(String id, {required DateTime date, bool featured = false}) =>
      EventModel(
        id: id,
        title: id,
        description: '',
        location: 'JFK',
        date: date,
        time: '18:00',
        createdBy: 'someone',
        createdAt: DateTime(2026, 1, 1),
        isFeatured: featured,
      );

  final past = event('past', date: DateTime(2020, 1, 1));
  final soon = event('soon', date: DateTime.now().add(const Duration(days: 3)));
  final featuredSoon =
      event('featured', date: DateTime.now().add(const Duration(days: 5)), featured: true);
  final featuredPast =
      event('featured-past', date: DateTime(2021, 1, 1), featured: true);

  final all = [past, soon, featuredSoon, featuredPast];

  List<String> ids(List<EventModel> e) => e.map((x) => x.id).toList();

  group('EventsTab.all', () {
    test('includes past events — otherwise it is not "All"', () {
      expect(ids(eventsForTab(all, EventsTab.all)), contains('past'));
    });

    test('includes featured and non-featured alike', () {
      expect(ids(eventsForTab(all, EventsTab.all)),
          containsAll(['soon', 'featured', 'past', 'featured-past']));
    });
  });

  group('EventsTab.upcoming', () {
    test('excludes past events', () {
      expect(ids(eventsForTab(all, EventsTab.upcoming)), isNot(contains('past')));
    });

    test('includes a featured event that is still upcoming', () {
      // Featured is a flag, not a separate bucket — a featured upcoming event
      // is still upcoming.
      expect(ids(eventsForTab(all, EventsTab.upcoming)), contains('featured'));
    });
  });

  group('EventsTab.featured', () {
    test('includes only featured events', () {
      expect(ids(eventsForTab(all, EventsTab.featured)), contains('featured'));
      expect(ids(eventsForTab(all, EventsTab.featured)), isNot(contains('soon')));
    });

    test('excludes featured events that have already happened', () {
      // A finished event is not something to promote.
      expect(ids(eventsForTab(all, EventsTab.featured)),
          isNot(contains('featured-past')));
    });
  });

  group('shared behaviour', () {
    test('every tab returns an empty list for empty input', () {
      for (final tab in EventsTab.values) {
        expect(eventsForTab(const [], tab), isEmpty, reason: '$tab');
      }
    });

    test('the tabs actually differ — the H4 regression guard', () {
      final a = ids(eventsForTab(all, EventsTab.all));
      final u = ids(eventsForTab(all, EventsTab.upcoming));
      final f = ids(eventsForTab(all, EventsTab.featured));
      expect(a, isNot(equals(u)));
      expect(u, isNot(equals(f)));
      expect(a, isNot(equals(f)));
    });

    test('preserves the incoming order within a tab', () {
      expect(ids(eventsForTab(all, EventsTab.upcoming)), ['soon', 'featured']);
    });
  });
}
