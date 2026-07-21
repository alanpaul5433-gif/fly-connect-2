import 'dart:math';
import 'package:geolocator/geolocator.dart';

enum LocationAccessResult { granted, denied, deniedForever, serviceDisabled }

/// Wraps the `geolocator` plugin so callers never touch the platform channel
/// directly and never have to invent their own fallback coordinate. Every
/// failure mode (denied permission, disabled service, timeout) is returned
/// as a value — callers must render an honest "location unavailable" state
/// instead of falling back to a fake position (that's exactly what H-4 was).
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// Checks location services are on, then checks/requests permission.
  /// No custom rationale dialog — matches this app's existing convention of
  /// calling the OS/plugin permission API directly (see
  /// NotificationService.init for the FCM equivalent).
  Future<LocationAccessResult> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccessResult.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse =>
        LocationAccessResult.granted,
      LocationPermission.deniedForever => LocationAccessResult.deniedForever,
      LocationPermission.denied || LocationPermission.unableToDetermine =>
        LocationAccessResult.denied,
    };
  }

  /// Returns the device's current position, or null on any failure
  /// (permission denied, service disabled, timeout). Never throws, never
  /// returns a placeholder coordinate — callers must treat null as
  /// "location unavailable."
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Rounds a coordinate to [decimals] places (default ~1.1km precision at
  /// the equator) for the "Approximate Location Only" privacy setting. Pure
  /// and side-effect-free so it's safe to unit test and safe under mock mode.
  static (double, double) fuzzCoordinate(double lat, double lng, {int decimals = 2}) {
    final factor = pow(10, decimals);
    return ((lat * factor).round() / factor, (lng * factor).round() / factor);
  }

  /// Distance between two coordinates, in meters.
  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

  /// Deep-links to this app's OS settings page — the only way to recover
  /// from a `deniedForever` permission (re-requesting is a silent no-op).
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Deep-links to the device's Location Services toggle.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
