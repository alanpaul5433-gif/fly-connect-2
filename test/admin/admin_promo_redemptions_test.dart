import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/admin/admin_promotions_page.dart';

/// The moderation queue read `p['redemptions']` while `PromotionModel.toMap`
/// writes `currentRedemptions` (models.dart:62). Only the older seeded
/// documents ever carried `redemptions`, so every business-created deal
/// reported "0 redemptions" in the admin queue no matter its real usage.
///
/// That failure mode is worse than a crash: 0 is a plausible number for a new
/// deal, so an admin reading the queue has no signal that the value is wrong.
/// Same shape as the promotions-`createdAt` bug — a write/read field-name
/// divergence that degrades into a believable value.
///
/// Both document generations exist in production and neither is going away, so
/// the reader has to handle both.
void main() {
  group('promoRedemptions', () {
    test('reads currentRedemptions — what the app actually writes', () {
      expect(promoRedemptions({'currentRedemptions': 7}), 7);
    });

    test('falls back to the legacy redemptions field on seeded documents', () {
      expect(promoRedemptions({'redemptions': 3}), 3);
    });

    test('prefers currentRedemptions when a document carries both', () {
      // Not hypothetical: a seeded promo that later gets redeemed through the
      // app picks up currentRedemptions alongside its original field.
      expect(promoRedemptions({'redemptions': 3, 'currentRedemptions': 9}), 9);
    });

    test('returns 0 when neither field is present', () {
      expect(promoRedemptions({'title': 'No counters yet'}), 0);
    });

    test('survives a non-numeric value instead of throwing', () {
      // This renders inside a list of up to 50 cards; one malformed document
      // must not take down the whole moderation queue.
      expect(promoRedemptions({'currentRedemptions': 'lots'}), 0);
      expect(promoRedemptions({'currentRedemptions': null, 'redemptions': 4}), 4);
    });

    test('truncates a double, as Firestore may hand back a num', () {
      expect(promoRedemptions({'currentRedemptions': 12.0}), 12);
    });
  });
}
