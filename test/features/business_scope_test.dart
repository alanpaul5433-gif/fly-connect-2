import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/business/business_scope.dart';
import 'package:flyconnect/shared/models/models.dart';

/// Coverage for H19 — a business's analytics/dashboard leaked OTHER
/// businesses' data.
///
/// PromotionProvider streams the whole `promotions` collection (correct — the
/// public Crew Deals feed needs every active deal). But the analytics and
/// dashboard screens aggregated that raw list instead of the owner's own, so
/// Business A saw Business B's titles, views, saves and redemptions as if they
/// were their own. `myPromotions(uid)` existed and was simply not used.
void main() {
  PromotionModel promo(String id, String businessId,
          {int views = 0, int redemptions = 0, bool active = true}) =>
      PromotionModel(
        id: id,
        businessId: businessId,
        businessName: businessId,
        title: id,
        description: '',
        discountPercent: 10,
        validFrom: DateTime(2026, 1, 1),
        validTo: DateTime(2026, 12, 31),
        maxRedemptions: 100,
        currentRedemptions: redemptions,
        views: views,
        saves: 0,
        isActive: active,
        isApproved: true,
      );

  EventModel event(String id, String createdBy) => EventModel(
        id: id,
        title: id,
        description: '',
        location: 'JFK',
        date: DateTime(2026, 8, 1),
        time: '18:00',
        createdBy: createdBy,
        createdAt: DateTime(2026, 1, 1),
      );

  const me = 'biz_me';
  const them = 'biz_them';

  final all = [
    promo('mine1', me, views: 10, redemptions: 2),
    promo('theirs1', them, views: 999, redemptions: 500),
    promo('mine2', me, views: 5),
  ];

  List<String> ids(List<PromotionModel> p) => p.map((x) => x.id).toList();

  group('ownPromotions', () {
    test('returns only my promotions', () {
      expect(ids(ownPromotions(all, me)), ['mine1', 'mine2']);
    });

    test('never includes another business\'s promotion', () {
      expect(ids(ownPromotions(all, me)), isNot(contains('theirs1')));
    });

    test('is empty for a business with none', () {
      expect(ownPromotions(all, 'nobody'), isEmpty);
    });

    test('is empty for a null uid rather than leaking everything', () {
      // A business screen with no resolved uid must show nothing, not the whole
      // collection — the failure mode that made this a leak.
      expect(ownPromotions(all, null), isEmpty);
    });
  });

  group('ownEvents', () {
    test('returns only events I created', () {
      final events = [event('e1', me), event('e2', them), event('e3', me)];
      expect(ownEvents(events, me).map((e) => e.id), ['e1', 'e3']);
    });

    test('is empty for a null uid', () {
      expect(ownEvents([event('e1', me)], null), isEmpty);
    });
  });

  group('promotion aggregates (H20 — real metrics, not fabricated)', () {
    final promos = [
      promo('p1', me, views: 10, redemptions: 2, active: true),
      promo('p2', me, views: 5, redemptions: 0, active: true),
      promo('p3', me, views: 100, redemptions: 7, active: false),
    ];

    test('totalViews sums views across all promotions', () {
      expect(totalViews(promos), 115);
    });

    test('totalRedemptions sums redemptions across all promotions', () {
      expect(totalRedemptions(promos), 9);
    });

    test('activeDealCount counts only active, approved promotions', () {
      expect(activeDealCount(promos), 2);
    });

    test('aggregates of an empty list are zero, not fabricated', () {
      expect(totalViews(const []), 0);
      expect(totalRedemptions(const []), 0);
      expect(activeDealCount(const []), 0);
    });
  });

  group('redemptionCode (H21 — a real, scannable QR payload)', () {
    test('encodes the promotion id in a stable deep link', () {
      expect(redemptionCode('promo_42'),
          'https://flyconnect.co/redeem/promo_42');
    });

    test('different promotions produce different codes', () {
      expect(redemptionCode('a'), isNot(redemptionCode('b')));
    });
  });
}
