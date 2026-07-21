import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/trips/passport_ownership.dart';

/// Coverage for H9 — opening someone else's passport.
///
/// `/passport/:userId` passed a userId that `trips_screen.dart` never read, so
/// it always showed the SIGNED-IN user's trips — titled "My Trips", with a live
/// Add button and a per-row Delete. Tapping Delete on what looked like another
/// person's passport deleted your OWN trip.
///
/// The ownership decision gates both the data source and the controls, so it's
/// worth pinning on its own.
void main() {
  group('isOwnPassport', () {
    test('a null route userId means your own passport', () {
      // Reached via the bottom tab, not /passport/:userId.
      expect(isOwnPassport(viewerUid: 'me', routeUserId: null), isTrue);
    });

    test('your own uid in the route is still your passport', () {
      expect(isOwnPassport(viewerUid: 'me', routeUserId: 'me'), isTrue);
    });

    test('someone else\'s uid is NOT your passport', () {
      expect(isOwnPassport(viewerUid: 'me', routeUserId: 'them'), isFalse);
    });

    test('a signed-out viewer never owns a specific-user passport', () {
      // No viewer uid + a target uid → read-only, never editable.
      expect(isOwnPassport(viewerUid: null, routeUserId: 'them'), isFalse);
    });

    test('a signed-out viewer with no target is treated as own (empty) view', () {
      // The bottom-tab case while auth is still resolving: not a foreign
      // passport, just an empty own view — never grants edit over anyone.
      expect(isOwnPassport(viewerUid: null, routeUserId: null), isTrue);
    });
  });
}
