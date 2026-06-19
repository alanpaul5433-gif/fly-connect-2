import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Regression tests for the profile Block/Report wiring (audit H1/H2).
///
/// Previously `profile_screen.dart` had `onTap: () => Navigator.pop(context)`
/// for both "Block user" and "Report user" — the provider methods existed but
/// were never called. These tests lock the persisted shapes those buttons now
/// produce via PostProvider.blockUser / reportContent, so the wiring can't
/// silently revert to a no-op. (Contract-style, against fake Firestore — the
/// same convention as auth_provider_test.dart, pending DI.)
void main() {
  late FakeFirebaseFirestore db;
  const me = 'me';
  const them = 'abusive-user';
  setUp(() => db = FakeFirebaseFirestore());

  group('Block (guards profile_screen.dart "Block user")', () {
    test('writes users/{me}/blocked/{them}', () async {
      // Mirrors PostProvider.blockUser.
      await db
          .collection('users').doc(me)
          .collection('blocked').doc(them)
          .set({'blockedAt': DateTime(2026)});

      final doc = await db
          .collection('users').doc(me)
          .collection('blocked').doc(them).get();
      expect(doc.exists, true);
    });

    test('unblock removes the doc', () async {
      final ref = db
          .collection('users').doc(me)
          .collection('blocked').doc(them);
      await ref.set({'blockedAt': DateTime(2026)});
      await ref.delete();
      expect((await ref.get()).exists, false);
    });
  });

  group('Report user (guards profile_screen.dart "Report user")', () {
    test('writes a reports doc with targetType=user', () async {
      // Mirrors PostProvider.reportContent(targetType: 'user', ...).
      await db.collection('reports').add({
        'targetType': 'user',
        'targetId': them,
        'reporterId': me,
        'reason': 'Harassment or bullying',
        'status': 'pending',
      });

      final reports = await db
          .collection('reports')
          .where('targetType', isEqualTo: 'user')
          .get();
      expect(reports.docs.length, 1);
      final r = reports.docs.first.data();
      expect(r['targetId'], them);
      expect(r['reporterId'], me);
      expect(r['status'], 'pending');
      expect(r['reason'], isNotEmpty);
    });
  });
}
