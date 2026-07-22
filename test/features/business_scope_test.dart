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

  group('engagement rates (H20 — real, derived from existing data)', () {
    test('redemptionRate is redemptions over views', () {
      final promos = [
        promo('p1', me, views: 100, redemptions: 5),
        promo('p2', me, views: 100, redemptions: 15),
      ];
      // 20 redemptions / 200 views = 10%.
      expect(redemptionRate(promos), closeTo(0.10, 1e-9));
    });

    test('saveRate is saves over views', () {
      // promo() seeds saves: 0, so build one with saves via the model directly.
      final p = PromotionModel(
        id: 's1', businessId: me, businessName: me, title: 's1', description: '',
        discountPercent: 10, validFrom: DateTime(2026, 1, 1), validTo: DateTime(2026, 12, 31),
        maxRedemptions: 100, currentRedemptions: 0, views: 50, saves: 10,
        isActive: true, isApproved: true);
      expect(saveRate([p]), closeTo(0.20, 1e-9));
    });

    test('rates are zero (not NaN) when there are no views', () {
      final p = promo('p1', me, views: 0, redemptions: 0);
      expect(redemptionRate([p]), 0);
      expect(saveRate([p]), 0);
    });

    test('rates of an empty list are zero', () {
      expect(redemptionRate(const []), 0);
      expect(saveRate(const []), 0);
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
