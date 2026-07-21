import '../../shared/models/models.dart';

/// The three Events filter tabs, in display order.
enum EventsTab { all, upcoming, featured }

/// The events a given [tab] should show.
///
/// Extracted as a pure function so the tabs can be tested — H4 shipped with
/// `onTap: (_) {}` and a single hardcoded derivation, so all three tabs
/// rendered identical content.
///
/// `featured` is a flag rather than a bucket: a featured upcoming event
/// legitimately appears under both Upcoming and Featured. Only "All" includes
/// events that have already happened.
List<EventModel> eventsForTab(List<EventModel> events, EventsTab tab) =>
    switch (tab) {
      EventsTab.all => events,
      EventsTab.upcoming => events.where((e) => e.isUpcoming).toList(),
      // Past events are dropped here too — a finished event is not something
      // worth promoting at the top of the screen.
      EventsTab.featured =>
        events.where((e) => e.isFeatured && e.isUpcoming).toList(),
    };
