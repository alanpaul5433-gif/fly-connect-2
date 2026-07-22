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

/// The scannable payload behind a promotion's redemption QR (H21). A stable
/// deep link tied to the promotion id, so a venue scan resolves to exactly one
/// deal — unlike the old decorative grid, which encoded nothing.
String redemptionCode(String promotionId) =>
    'https://flyconnect.co/redeem/$promotionId';
