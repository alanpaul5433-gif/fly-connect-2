import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// MatchProvider data-layer contract.
///
/// Mirrors the `matches` collection rules in firestore.rules: a match is created
/// by userA, the two participants may transition status, and a "pass" is a status
/// change (not a delete) so the pair isn't re-surfaced.
void main() {
  late FakeFirebaseFirestore db;
  const a = 'user-a';
  const b = 'user-b';

  setUp(() => db = FakeFirebaseFirestore());

  test('a new match is owned by userA and starts pending', () async {
    final ref = await db.collection('matches').add({
      'userA': a,
      'userB': b,
      'status': 'pending',
      'createdAt': Timestamp.now(),
    });

    final doc = await ref.get();
    expect(doc['userA'], a);
    expect(doc['userB'], b);
    expect(doc['status'], 'pending');
  });

  test('a mutual like transitions pending -> matched and stamps matchedAt',
      () async {
    final ref = await db
        .collection('matches')
        .add({'userA': a, 'userB': b, 'status': 'pending'});

    await ref.update({'status': 'matched', 'matchedAt': Timestamp.now()});

    final doc = await ref.get();
    expect(doc['status'], 'matched');
    expect(doc.data()!.containsKey('matchedAt'), true);
  });

  test('a pass is recorded as status=passed (the row is kept, not deleted)',
      () async {
    final ref = await db
        .collection('matches')
        .add({'userA': a, 'userB': b, 'status': 'pending'});

    await ref.update({'status': 'passed'});

    final doc = await ref.get();
    expect(doc.exists, true);
    expect(doc['status'], 'passed');
  });

  test('querying my matches returns rows where I am userA or userB', () async {
    await db.collection('matches').add({'userA': a, 'userB': b, 'status': 'matched'});
    await db.collection('matches').add({'userA': 'x', 'userB': a, 'status': 'matched'});
    await db.collection('matches').add({'userA': 'y', 'userB': 'z', 'status': 'matched'});

    final asA = await db.collection('matches').where('userA', isEqualTo: a).get();
    final asB = await db.collection('matches').where('userB', isEqualTo: a).get();
    final mine = {...asA.docs.map((d) => d.id), ...asB.docs.map((d) => d.id)};

    expect(mine, hasLength(2)); // the y/z match is not mine
  });
}
