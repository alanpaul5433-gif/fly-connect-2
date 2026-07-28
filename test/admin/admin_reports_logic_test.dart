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
