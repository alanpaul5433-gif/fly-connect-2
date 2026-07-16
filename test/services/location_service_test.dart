import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/core/services/location_service.dart';

/// Regression coverage for QA finding H-4: Nearby/SafeCheck used to submit a
/// hardcoded NYC coordinate. These cover LocationService's pure static
/// helpers — the plugin-backed methods (ensurePermission/getCurrentPosition)
/// need a real device/emulator and are verified manually per the H-4 plan.
void main() {
  group('LocationService.fuzzCoordinate', () {
    test('rounds to 2 decimal places by default', () {
      final (lat, lng) = LocationService.fuzzCoordinate(40.71283, -74.00601);
      expect(lat, 40.71);
      expect(lng, -74.01);
    });

    test('rounds a midpoint value away from zero (Dart round() semantics)', () {
      final (lat, lng) = LocationService.fuzzCoordinate(40.715, -74.005);
      expect(lat, 40.72);
      expect(lng, -74.01);
    });

    test('handles negative coordinates (southern/western hemisphere)', () {
      final (lat, lng) = LocationService.fuzzCoordinate(-33.86882, 151.20929);
      expect(lat, -33.87);
      expect(lng, 151.21);
    });

    test('respects a custom decimals param', () {
      final (lat, lng) = LocationService.fuzzCoordinate(40.71283, -74.00601, decimals: 0);
      expect(lat, 41.0);
      expect(lng, -74.0);
    });

    test('a coordinate already at the target precision is unchanged', () {
      final (lat, lng) = LocationService.fuzzCoordinate(40.71, -74.01);
      expect(lat, 40.71);
      expect(lng, -74.01);
    });
  });

  group('LocationService.distanceMeters', () {
    test('is zero for identical coordinates', () {
      expect(LocationService.distanceMeters(40.7128, -74.0060, 40.7128, -74.0060), 0.0);
    });

    test('matches a known real-world distance (NYC nearby-user fixtures)', () {
      // (40.7128, -74.0060) -> (40.7158, -74.0020) is ~473m (Haversine).
      final meters = LocationService.distanceMeters(40.7128, -74.0060, 40.7158, -74.0020);
      expect(meters, closeTo(473, 15));
    });

    test('is symmetric regardless of argument order', () {
      final a = LocationService.distanceMeters(40.7128, -74.0060, 40.7158, -74.0020);
      final b = LocationService.distanceMeters(40.7158, -74.0020, 40.7128, -74.0060);
      expect(a, closeTo(b, 0.001));
    });
  });
}
