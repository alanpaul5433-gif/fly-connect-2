import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/location_service.dart';

/// Location-sharing privacy, in one place.
///
/// H17: the upload was gated on `AuthProvider.currentUser.settings`, which
/// never refreshes after Settings writes (and UserProvider's copy is clobbered
/// back to that stale value on the next auth notify). So `shareLocation: false`
/// had no effect until an app restart, and coordinates kept uploading.

/// Whether the viewer's position may be persisted so others see a real
/// distance. Defaults ON when the setting is absent (a pre-migration account),
/// matching the Settings screen's `_shareLocation = true` default.
bool shouldShareLocation(Map<String, dynamic> settings) =>
    settings['shareLocation'] != false;

/// The coordinate to actually persist: fuzzed to ~1.1km when 'Approximate
/// Location Only' is on (also defaults on).
(double, double) resolveCoordinateToPersist(
        double lat, double lng, Map<String, dynamic> settings) =>
    settings['approxLocationOnly'] != false
        ? LocationService.fuzzCoordinate(lat, lng)
        : (lat, lng);

/// Persists [lat]/[lng] for [uid] IFF sharing is currently allowed — reading
/// the setting AUTHORITATIVELY from Firestore, not from any in-memory copy
/// (H17). Returns whether a write happened.
///
/// Fails closed: if the settings read throws (offline / permission), no
/// location is uploaded. For a privacy control, refusing to share on an
/// unknown state is the safe error — the opposite of the old `catch { }` that
/// let the upload proceed.
Future<bool> persistLocationIfAllowed(
  FirebaseFirestore db, {
  required String uid,
  required double lat,
  required double lng,
}) async {
  final Map<String, dynamic> settings;
  try {
    final doc = await db.collection('users').doc(uid).get();
    settings = (doc.data()?['settings'] as Map<String, dynamic>?) ?? const {};
  } catch (_) {
    return false; // unknown consent → do not upload
  }

  if (!shouldShareLocation(settings)) return false;

  final (fLat, fLng) = resolveCoordinateToPersist(lat, lng, settings);
  await db.collection('users').doc(uid).update({'lat': fLat, 'lng': fLng});
  return true;
}
