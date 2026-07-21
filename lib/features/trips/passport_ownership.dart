/// Whether the passport being viewed is the viewer's own — which gates both
/// the data source (own live stream vs. the target user's trips) and the
/// owner-only controls (Add, Delete).
///
/// H9: `/passport/:userId` was opened for other users but the screen ignored
/// the id and always showed the viewer's own trips with live edit controls, so
/// "delete" on a foreign-looking passport deleted the viewer's own trip.
///
/// A null [routeUserId] is the bottom-tab entry (your own passport). A specific
/// [routeUserId] is your own only when it matches [viewerUid]; anyone else is a
/// read-only view. A signed-out viewer never owns a specific-user passport.
bool isOwnPassport({required String? viewerUid, required String? routeUserId}) {
  if (routeUserId == null) return true;
  return viewerUid != null && viewerUid == routeUserId;
}
