import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/admin/admin_thumbnail.dart';
import 'package:flyconnect/shared/widgets/cached_image.dart';

/// The admin moderation queue rendered a hardcoded `Text('IMG')` box in place
/// of the deal image, and `_buildPromoCard` never read `p['imageUrl']` at all —
/// so a business could attach an image and an admin approving the deal would
/// never see it. Business-created promotions in production do carry a valid
/// imageUrl (Firebase Storage download URLs under user_uploads/{uid}/promos/),
/// so nothing upstream was broken; the display code simply did not exist.
///
/// These tests pin the three states, because "shows a grey box" is exactly what
/// the bug looked like and a regression would be invisible again.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('AdminThumbnail', () {
    testWidgets('renders the image when the promo has one', (tester) async {
      await tester.pumpWidget(host(const AdminThumbnail(
        imageUrl: 'https://example.com/deal.jpg',
        label: '50% Off Crew Meals',
      )));

      expect(find.byType(CachedFeedImage), findsOneWidget,
          reason: 'A promo with an imageUrl must render the image, not just a '
              'static box. This is the original bug.');
      expect(find.byType(InkWell), findsOneWidget,
          reason: 'and it must be tappable.');

      // Deliberately NOT asserting that "IMG" is absent. The placeholder is
      // reused as CachedFeedImage's loading visual, and widget tests force
      // every HTTP request to 400, so the image never resolves and the
      // placeholder stays on screen for the whole test. Presence of
      // CachedFeedImage is what distinguishes fixed from broken here.
    });

    testWidgets('falls back to the placeholder when there is no image',
        (tester) async {
      await tester.pumpWidget(host(const AdminThumbnail(
        imageUrl: null,
        label: 'Untitled',
      )));

      // imageUrl is genuinely optional at creation
      // (create_promotion_screen.dart:88), so this is a real case, not a
      // defensive branch — a naive Image.network here would throw.
      expect(find.text('IMG'), findsOneWidget);
      expect(find.byType(CachedFeedImage), findsNothing);
    });

    testWidgets('treats an empty imageUrl as no image', (tester) async {
      await tester.pumpWidget(host(const AdminThumbnail(
        imageUrl: '',
        label: 'Untitled',
      )));

      expect(find.text('IMG'), findsOneWidget);
    });

    testWidgets('tapping opens a full-size view an admin can judge',
        (tester) async {
      await tester.pumpWidget(host(const AdminThumbnail(
        imageUrl: 'https://example.com/deal.jpg',
        label: '50% Off Crew Meals',
      )));

      await tester.tap(find.byType(CachedFeedImage));
      // Not pumpAndSettle: CachedNetworkImage keeps a pending image request in
      // the test environment, so settling never completes.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Dialog), findsOneWidget,
          reason: '100x100 is too small to approve or reject a deal image on; '
              'the admin needs a full-size look before deciding.');
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('placeholder is not tappable — there is nothing to enlarge',
        (tester) async {
      await tester.pumpWidget(host(const AdminThumbnail(
        imageUrl: null,
        label: 'Untitled',
      )));

      expect(find.byType(InkWell), findsNothing);
    });
  });
}
