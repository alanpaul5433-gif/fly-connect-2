import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/shared/widgets/cached_image.dart';

/// Tests for the cached image widgets. We exercise the synchronous fallback
/// paths (null / empty url) — the common "user has no photo" case — which
/// render without any network/timer activity, so they stay non-flaky.
void main() {
  group('CachedAvatar', () {
    testWidgets('renders the fallback when url is null', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CachedAvatar(url: null, radius: 20, fallback: Text('AB')),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('AB'), findsOneWidget);
      // Fallback path renders a CircleAvatar (not a network image).
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('renders the fallback when url is empty', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CachedAvatar(
                url: '', radius: 16, fallback: Icon(Icons.person)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('honors backgroundColor and radius on the fallback',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CachedAvatar(
              url: null,
              radius: 24,
              backgroundColor: Colors.teal,
              fallback: Text('Z'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundColor, Colors.teal);
      expect(avatar.radius, 24);
    });
  });
}
