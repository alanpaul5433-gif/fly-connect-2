import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Coverage for H18 — SafeCheck visibility must travel on the document.
///
/// Visibility was a client-side filter over a collection any signed-in user
/// could read in full. Enforcing it in firestore.rules means the choice has to
/// be denormalised onto each check-in, plus a `visibleTo` audience for the
/// "Friends Only" case (bounded staleness: check-ins expire after 24h).
void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  SafeCheckModel build({
    String visibility = 'all',
    List<String> visibleTo = const [],
  }) => SafeCheckModel(
        id: 'sc1', userId: 'author', userName: 'Author', status: 'safe',
        city: 'NYC', lat: 40.7, lng: -74.0,
        createdAt: DateTime(2026, 7, 21),
        visibility: visibility, visibleTo: visibleTo,
      );

  test('defaults to everyone-visible so an unset check-in is not hidden', () {
    expect(build().visibility, 'all');
    expect(build().visibleTo, isEmpty);
  });

  test('round-trips visibility and visibleTo through Firestore', () async {
    final check = build(visibility: 'friends', visibleTo: ['friend-a', 'friend-b']);
    await db.collection('safeChecks').doc('sc1').set(check.toFirestore());

    final parsed = SafeCheckModel.fromFirestore(
      await db.collection('safeChecks').doc('sc1').get());

    expect(parsed.visibility, 'friends');
    expect(parsed.visibleTo, ['friend-a', 'friend-b']);
  });

  test('a legacy document with no visibility parses as everyone-visible',
      () async {
    // The rule denies these, but the model must not crash on them — they are
    // still readable by their own author until they expire.
    await db.collection('safeChecks').doc('legacy').set({
      'userId': 'author', 'status': 'safe', 'city': 'NYC',
      'createdAt': DateTime(2026, 7, 21),
    });

    final parsed = SafeCheckModel.fromFirestore(
      await db.collection('safeChecks').doc('legacy').get());

    expect(parsed.visibility, 'all');
    expect(parsed.visibleTo, isEmpty);
  });

  test('toFirestore always writes visibility so the query can pin it', () {
    expect(build().toFirestore()['visibility'], 'all');
  });

  test('visibleTo is only meaningful for friends, and is written verbatim', () {
    final check = build(visibility: 'friends', visibleTo: ['a']);

    expect(check.toFirestore()['visibleTo'], ['a']);
  });
}
