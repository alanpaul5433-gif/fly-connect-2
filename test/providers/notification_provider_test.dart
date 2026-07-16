import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flyconnect/shared/providers/real_providers.dart' show describeNotificationsError;

/// M-8: Notifications previously showed the same "Could not load" copy for
/// every failure. describeNotificationsError distinguishes offline (a
/// FirebaseException with code 'unavailable') from any other server error.
void main() {
  group('describeNotificationsError (M-8)', () {
    test('offline (unavailable) gets a connection-specific message', () {
      final err = FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      expect(describeNotificationsError(err), contains('offline'));
    });

    test('a missing-index / server error gets a generic retry message, not "offline"', () {
      final err = FirebaseException(plugin: 'cloud_firestore', code: 'failed-precondition');
      final message = describeNotificationsError(err);
      expect(message, isNot(contains('offline')));
      expect(message, contains('try again'));
    });

    test('a non-FirebaseException error still falls back to the generic message', () {
      final message = describeNotificationsError(Exception('boom'));
      expect(message, isNot(contains('offline')));
    });
  });
}
