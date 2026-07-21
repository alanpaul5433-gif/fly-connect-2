import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/admin/admin_safecheck_page.dart';

import '../helpers/firebase_mocks.dart';

/// AdminSafeCheckPage listens to a live Firestore .snapshots() stream with
/// no injection seam, and an unmocked stream never emits in this test
/// environment — so _loading never flips false and the data-driven feed/
/// queue UI can't be exercised without a live backend (out of scope, same
/// limitation as nearby_users_screen_test.dart). This is a smoke test:
/// confirms the page builds and renders its loading state without crashing.
void main() {
  setUpAll(setupFirebaseCoreMocks);

  testWidgets('renders the loading state without crashing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminSafeCheckPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
