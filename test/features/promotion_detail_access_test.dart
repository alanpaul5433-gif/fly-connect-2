import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/models/models.dart';
import 'package:flyconnect/shared/providers/user_provider.dart';
import 'package:flyconnect/features/business/promotion_detail_screen.dart';

/// Access-control regression for the Crew-Deals analytics leak.
///
/// `PromotionDetailScreen` is shared by the crew-facing deal card and the
/// business promotions list (both route to /promotions/:id). The views/saves/
/// redemptions metrics belong to the promoting business — a crew member must
/// never see another company's analytics. These tests pin that gating.
class _MockUserProvider extends Mock implements UserProvider {}

PromotionModel _promo() => PromotionModel(
      id: 'promo-1',
      businessId: 'biz-1',
      businessName: 'SkyBar',
      title: '20% off drinks',
      description: 'Layover special',
      discountPercent: 20,
      validFrom: DateTime(2026, 1, 1),
      validTo: DateTime(2026, 12, 31),
      maxRedemptions: 100,
      currentRedemptions: 42,
      views: 500,
      saves: 80,
    );

UserModel _user(String uid, {String role = 'user'}) => UserModel(
      uid: uid, name: 'N', email: 'n@x.com', role: role,
      createdAt: DateTime(2024),
    );

Future<void> _pump(WidgetTester tester, UserModel? viewer) async {
  final up = _MockUserProvider();
  when(() => up.currentUser).thenReturn(viewer);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: up,
      child: MaterialApp(home: PromotionDetailScreen(promotion: _promo())),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('crew (non-owner user) does NOT see analytics/saves/redemptions',
      (tester) async {
    await _pump(tester, _user('crew-9'));
    expect(find.text('Analytics'), findsNothing);
    expect(find.textContaining('saves'), findsNothing); // "80 saves" stat chip
    // The user-facing parts still render.
    expect(find.text('20% off drinks'), findsOneWidget);
    expect(find.text('Redemption QR Code'), findsOneWidget);
  });

  testWidgets('owning business sees analytics', (tester) async {
    await _pump(tester, _user('biz-1', role: 'business'));
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.textContaining('saves'), findsOneWidget);
  });

  testWidgets('admin sees analytics (moderation)', (tester) async {
    await _pump(tester, _user('mod-1', role: 'admin'));
    expect(find.text('Analytics'), findsOneWidget);
  });

  testWidgets('signed-out / unknown viewer fails closed (no analytics)',
      (tester) async {
    await _pump(tester, null);
    expect(find.text('Analytics'), findsNothing);
  });
}
