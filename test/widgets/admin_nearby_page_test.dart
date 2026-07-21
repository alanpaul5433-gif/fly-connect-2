import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/admin/admin_nearby_page.dart';

import '../helpers/firebase_mocks.dart';

/// Same limitation as admin_safecheck_page_test.dart: an unmocked
/// .snapshots() stream never emits here, so _loading never flips false and
/// the GoogleMap/marker path can't be exercised without a live backend.
/// Smoke test only — confirms the page (and its warning banner) render
/// without crashing while loading.
void main() {
  setUpAll(setupFirebaseCoreMocks);

  testWidgets('renders the loading state and warning banner without crashing',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AdminNearbyPage())));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Locations are simulated'), findsOneWidget);
  });
}
