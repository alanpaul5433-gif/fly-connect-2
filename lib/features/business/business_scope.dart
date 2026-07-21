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
