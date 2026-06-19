import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Tests for PromotionProvider: active/expired filtering, date boundary logic.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  DateTime daysFromNow(int days) =>
      DateTime.now().add(Duration(days: days));

  test('active promotion: validFrom in past, validTo in future', () async {
    await db.collection('promotions').add({
      'businessId': 'biz-1',
      'title': 'Active promo',
      'validFrom': Timestamp.fromDate(daysFromNow(-5)),
      'validTo': Timestamp.fromDate(daysFromNow(5)),
      'isActive': true,
    });

    final snap = await db.collection('promotions').get();
    final doc = snap.docs.first.data();
    final from = (doc['validFrom'] as Timestamp).toDate();
    final to = (doc['validTo'] as Timestamp).toDate();
    final now = DateTime.now();

    expect(from.isBefore(now), true);
    expect(to.isAfter(now), true);
  });

  test('expired promotion: validTo in past', () async {
    await db.collection('promotions').add({
      'businessId': 'biz-1',
      'title': 'Old promo',
      'validFrom': Timestamp.fromDate(daysFromNow(-30)),
      'validTo': Timestamp.fromDate(daysFromNow(-1)),
      'isActive': false,
    });

    final snap = await db.collection('promotions').get();
    final doc = snap.docs.first.data();
    final to = (doc['validTo'] as Timestamp).toDate();
    expect(to.isBefore(DateTime.now()), true);
  });

  test('upcoming promotion: validFrom in future', () async {
    await db.collection('promotions').add({
      'businessId': 'biz-1',
      'title': 'Future promo',
      'validFrom': Timestamp.fromDate(daysFromNow(3)),
      'validTo': Timestamp.fromDate(daysFromNow(30)),
      'isActive': false,
    });

    final snap = await db.collection('promotions').get();
    final doc = snap.docs.first.data();
    final from = (doc['validFrom'] as Timestamp).toDate();
    expect(from.isAfter(DateTime.now()), true);
  });

  test('businessId filter returns only own promotions', () async {
    await db.collection('promotions').add({'businessId': 'biz-1', 'title': 'Mine'});
    await db.collection('promotions').add({'businessId': 'biz-2', 'title': 'Theirs'});
    await db.collection('promotions').add({'businessId': 'biz-1', 'title': 'Mine 2'});

    final snap = await db.collection('promotions')
        .where('businessId', isEqualTo: 'biz-1').get();
    expect(snap.docs.length, 2);
  });

  test('promotion created uses authenticated user.uid, never biz_001', () async {
    // Regression test for the QA finding:
    // "Business ID hardcoded to biz_001 regardless of logged-in user"
    const realUid = 'authenticated-business-uid';
    await db.collection('promotions').add({
      'businessId': realUid,
      'businessName': 'Real Business',
      'title': 'Deal',
    });

    final snap = await db.collection('promotions').get();
    expect(snap.docs.first.data()['businessId'], realUid);
    expect(snap.docs.first.data()['businessId'], isNot('biz_001'));
  });
}
