import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/providers/real_providers.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Provider-level coverage of SafeCheck's multi-branch merge (H18) — the exact
/// piece the H18 fix could NOT test, because SafeCheckProvider hard-coded
/// FirebaseFirestore.instance. With db injected it runs the real subscriptions
/// (one per entitled visibility branch) and the dedupe/merge against a fake db.
///
/// The viewer identity comes through an AuthProvider, so a tiny subclass with a
/// controllable currentUser stands in for it.
class _FakeAuth extends AuthProvider {
  final UserModel _user;
  // Forward fakes to super so the field initializers don't touch
  // FirebaseFirestore.instance / FirebaseAuth.instance (no Firebase in tests).
  _FakeAuth(this._user, FirebaseFirestore db)
      : super(isMock: true, db: db, auth: MockFirebaseAuth());
  @override
  UserModel? get currentUser => _user;
}

void main() {
  late FakeFirebaseFirestore db;
  const me = 'me';

  UserModel user(String uid, {bool verified = false}) => UserModel(
        uid: uid, name: uid, email: '$uid@x.test',
        createdAt: DateTime(2026, 1, 1), isVerified: verified);

  SafeCheckProvider providerFor(UserModel viewer) =>
      SafeCheckProvider(db: db)..updateAuth(_FakeAuth(viewer, db));

  Future<void> seedCheck(String id, {
    required String userId,
    required String visibility,
    List<String> visibleTo = const [],
    DateTime? createdAt,
  }) =>
      db.collection('safeChecks').doc(id).set({
        'userId': userId, 'userName': userId, 'status': 'safe', 'city': 'NYC',
        'visibility': visibility, 'visibleTo': visibleTo,
        'createdAt': createdAt ?? DateTime(2026, 7, 1),
      });

  setUp(() => db = FakeFirebaseFirestore());

  Future<List<String>> visibleIds(SafeCheckProvider p) async {
    for (var i = 0; i < 25 && p.checkIns.isEmpty; i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    await Future.delayed(const Duration(milliseconds: 20)); // let all branches land
    return p.checkIns.map((c) => c.id).toList();
  }

  test("'all' check-ins are visible to everyone", () async {
    await seedCheck('a1', userId: 'stranger', visibility: 'all');
    expect(await visibleIds(providerFor(user(me))), contains('a1'));
  });

  test("a 'friends' check-in is hidden unless the viewer is in visibleTo", () async {
    await seedCheck('f1', userId: 'stranger', visibility: 'friends', visibleTo: const ['someone_else']);
    expect(await visibleIds(providerFor(user(me))), isNot(contains('f1')));
  });

  test("a 'friends' check-in listing the viewer IS visible", () async {
    await seedCheck('f2', userId: 'stranger', visibility: 'friends', visibleTo: const [me]);
    expect(await visibleIds(providerFor(user(me))), contains('f2'));
  });

  test("a 'verified' check-in is hidden from an unverified viewer", () async {
    await seedCheck('v1', userId: 'stranger', visibility: 'verified');
    expect(await visibleIds(providerFor(user(me, verified: false))), isNot(contains('v1')));
  });

  test("a 'verified' check-in is visible to a verified viewer", () async {
    await seedCheck('v2', userId: 'stranger', visibility: 'verified');
    expect(await visibleIds(providerFor(user(me, verified: true))), contains('v2'));
  });

  test('my own check-in is visible regardless of its visibility', () async {
    await seedCheck('m1', userId: me, visibility: 'friends', visibleTo: const []);
    expect(await visibleIds(providerFor(user(me))), contains('m1'));
  });

  test('a check-in matching two branches appears exactly once (dedupe)', () async {
    // Authored by me AND friends-visible to me → matches both 'mine' and
    // 'friends'. _recombine must dedupe by id.
    await seedCheck('d1', userId: me, visibility: 'friends', visibleTo: const [me]);
    final ids = await visibleIds(providerFor(user(me)));
    expect(ids.where((id) => id == 'd1'), hasLength(1));
  });

  test('merged results are sorted newest-first', () async {
    await seedCheck('old', userId: 'x', visibility: 'all', createdAt: DateTime(2026, 7, 1));
    await seedCheck('new', userId: 'y', visibility: 'all', createdAt: DateTime(2026, 7, 20));
    final ids = await visibleIds(providerFor(user(me)));
    expect(ids.indexOf('new'), lessThan(ids.indexOf('old')));
  });
}
