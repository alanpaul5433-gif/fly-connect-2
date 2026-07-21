import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flyconnect/main.dart' as app;

/// Create-post flow: assumes user is already signed in via emulator or
/// previous test set up auth state.
///
/// Run:
///   flutter test integration_test/post_create_flow_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Post creation flow', () {
    testWidgets('Tap FAB \u2192 write caption \u2192 Share \u2192 post appears in feed',
        (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to create post. Usually a FAB or drawer action.
      // The route is /create-post \u2014 we rely on deep-link navigation in tests.
      // Skip until a reliable path is established during device test runs.
    }, skip: true);

    testWidgets('Empty post (no caption, no media) cannot be submitted',
        (tester) async {
      // When _post() is called with empty caption AND no image, it early-returns.
      // This is covered by unit tests; integration stub kept for future.
    }, skip: true);
  });
}
