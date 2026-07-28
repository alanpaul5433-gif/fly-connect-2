import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/admin/admin_reports_page.dart';

/// Two field-name divergences on the reports queue, both verified against
/// production documents, which store:
///   createdAt, description, reason, reporterId, reporterName, severity,
///   status, targetId, targetName, type
///
/// 1. **Two schemas are live at once.** The app writes `targetType`
///    (real_providers.dart:1442 and :1545), while the seeded documents in
///    production carry `type`. The page mixed the two: "view target" switched
///    on `targetType` — dead for every seeded report — while the type filter
///    and the type badge read `type` — blank or "unknown" for every
///    app-created report. Whichever report you looked at, one of the two was
///    wrong, which is why neither symptom was obviously systemic.
///
///    So neither name can be dropped: both are real data that predates any
///    fix. Reads accept both, preferring `type`.
///
/// 2. The queue sorted by `severity` then `reportCount`. Reports carry no
///    `reportCount` under either schema, so the tiebreaker compared 0 against
///    0 and the order within a severity band was whatever Firestore returned —
///    arbitrary, but presented as deliberate.
void main() {
  Timestamp at(int day) => Timestamp.fromDate(DateTime(2026, 7, day));

  group('reportTargetType', () {
    test('reads `type` — what reports documents actually store', () {
      expect(reportTargetType({'type': 'post'}), 'post');
    });

    test('accepts `targetType`, the name audit_log uses', () {
      expect(reportTargetType({'targetType': 'chat'}), 'chat');
    });

    test('prefers `type` when a document somehow carries both', () {
      expect(reportTargetType({'type': 'post', 'targetType': 'chat'}), 'post');
    });

    test('returns empty string when neither is present', () {
      expect(reportTargetType({'targetId': 'abc'}), '');
    });

    test('does not throw on a non-string value', () {
      expect(reportTargetType({'type': 42}), '');
    });
  });

  /// "View Target" pushed `/posts/:id`, `/users/:id`, `/groups/:id` and
  /// `/conversation/:id` — none of which exist in `adminRouter`. The admin
  /// build deliberately strips every consumer route, so the push fell through
  /// to GoRouter's `errorBuilder`, which sits OUTSIDE the ShellRoute: the
  /// sidebar and the whole admin frame were replaced by a bare "Page not
  /// found" screen, recoverable only with browser-back.
  ///
  /// Verified against production: 14 of the 20 live reports (post/chat/user)
  /// hit that dead route. The remaining 6 (comment/trip) fell to the default
  /// branch and merely showed a snackbar.
  ///
  /// So the destination must be a route this router actually registers.
  /// `/admin/users` searches by name and email (applyUsersFilter), and
  /// `/admin/content` is the reported-posts queue — neither takes a document
  /// id, which is why the dialog also offers the target's name for pasting
  /// into that search box.
  group('adminRouteForTargetType', () {
    test('user targets go to the admin users queue', () {
      expect(adminRouteForTargetType('user'), '/admin/users');
    });

    test('post and comment targets go to the content queue', () {
      expect(adminRouteForTargetType('post'), '/admin/content');
      expect(adminRouteForTargetType('comment'), '/admin/content');
    });

    test('chat has no admin page, so it offers no destination', () {
      // Returning a route here would recreate the original bug in a new
      // costume: navigation that looks available and goes nowhere useful.
      expect(adminRouteForTargetType('chat'), isNull);
    });

    test('trip has no admin page either', () {
      expect(adminRouteForTargetType('trip'), isNull);
    });

    test('an absent type resolves to no destination rather than throwing', () {
      expect(adminRouteForTargetType(''), isNull);
    });

    test('an unrecognised type is not routed', () {
      expect(adminRouteForTargetType('spaceship'), isNull);
    });

    test('never returns a consumer route — the crash the fix exists for', () {
      const dead = ['/posts', '/users/', '/groups', '/conversation'];
      for (final type in ['user', 'post', 'comment', 'chat', 'trip', '']) {
        final route = adminRouteForTargetType(type);
        if (route == null) continue;
        expect(route.startsWith('/admin/'), isTrue,
            reason: '"$type" resolved to "$route", which adminRouter does not '
                'register — that is the "Page not found" bug.');
        for (final bad in dead) {
          expect(route.startsWith(bad), isFalse);
        }
      }
    });
  });

  group('compareReports', () {
    test('orders high severity before medium before low', () {
      final high = {'severity': 'high', 'createdAt': at(1)};
      final medium = {'severity': 'medium', 'createdAt': at(1)};
      final low = {'severity': 'low', 'createdAt': at(1)};

      final list = [low, high, medium]..sort(compareReports);
      expect(list.map((r) => r['severity']), ['high', 'medium', 'low']);
    });

    test('breaks ties by newest first, which the old sort could not do', () {
      final older = {'severity': 'high', 'createdAt': at(1)};
      final newer = {'severity': 'high', 'createdAt': at(9)};

      final list = [older, newer]..sort(compareReports);
      expect(list.first, same(newer),
          reason: 'Within a severity band the newest unhandled report should '
              'surface first. The old tiebreaker read reportCount, which '
              'reports do not have, so this was pure luck before.');
    });

    test('severity outranks recency', () {
      final oldHigh = {'severity': 'high', 'createdAt': at(1)};
      final newLow = {'severity': 'low', 'createdAt': at(28)};

      final list = [newLow, oldHigh]..sort(compareReports);
      expect(list.first, same(oldHigh));
    });

    test('a missing timestamp sorts last rather than throwing', () {
      final dated = {'severity': 'high', 'createdAt': at(5)};
      final undated = {'severity': 'high'};

      final list = [undated, dated]..sort(compareReports);
      expect(list.first, same(dated));
    });

    test('an unknown severity is treated as lowest', () {
      final weird = {'severity': 'catastrophic', 'createdAt': at(9)};
      final low = {'severity': 'low', 'createdAt': at(1)};

      final list = [weird, low]..sort(compareReports);
      // Both rank as "other"; the newer one wins on recency.
      expect(list.first, same(weird));
    });
  });
}
