import '../../shared/models/models.dart';

/// Scoping helpers for the business dashboard and analytics screens.
///
/// PromotionProvider and EventProvider stream their whole collections (the
/// public Crew Deals feed and events browser need every item). The business's
/// OWN analytics must aggregate only what it owns — H19 leaked every other
/// business's titles, views, saves and redemptions because the screens used the
/// raw lists. A null [businessId] returns nothing rather than everything, since
/// "show all" is exactly the leak.

List<PromotionModel> ownPromotions(
        List<PromotionModel> all, String? businessId) =>
    businessId == null
        ? const []
        : all.where((p) => p.businessId == businessId).toList();

List<EventModel> ownEvents(List<EventModel> all, String? businessId) =>
    businessId == null
        ? const []
        : all.where((e) => e.createdBy == businessId).toList();

/// H20: real metrics computed from the business's own promotions, replacing the
/// fabricated Growth/Reach/Engagement literals the analytics screen showed.

int totalViews(List<PromotionModel> promos) =>
    promos.fold(0, (sum, p) => sum + p.views);

int totalRedemptions(List<PromotionModel> promos) =>
    promos.fold(0, (sum, p) => sum + p.currentRedemptions);

int activeDealCount(List<PromotionModel> promos) =>
    promos.where((p) => p.isActive && p.isApproved).length;

/// H20: engagement rates derived from data we already collect — real metrics
/// to replace the fabricated Growth/Reach/Engagement literals. Guarded against
/// divide-by-zero so an unseen catalogue reads 0, not NaN.

double redemptionRate(List<PromotionModel> promos) {
  final views = totalViews(promos);
  return views == 0 ? 0 : totalRedemptions(promos) / views;
}

double saveRate(List<PromotionModel> promos) {
  final views = totalViews(promos);
  final saves = promos.fold(0, (sum, p) => sum + p.saves);
  return views == 0 ? 0 : saves / views;
}

/// Real follower growth (H20): the fractional change from a [baseline]
/// snapshot to [current]. Null when there's no usable baseline yet — the UI
/// shows "building history…", never a fabricated number. Mirrors the Cloud
/// Function's growthFraction so client and backend agree.
double? growthFraction({required int current, required int? baseline}) {
  if (baseline == null || baseline <= 0) return null;
  return (current - baseline) / baseline;
}

/// The scannable payload behind a promotion's redemption QR (H21). A stable
/// deep link tied to the promotion id, so a venue scan resolves to exactly one
/// deal — unlike the old decorative grid, which encoded nothing.
String redemptionCode(String promotionId) =>
    'https://flyconnect.co/redeem/$promotionId';
