import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flyconnect/shared/providers/post_provider.dart';
import 'package:flyconnect/features/home/edit_post_screen.dart';

import '../helpers/fixtures.dart';

class _MockPostProvider extends Mock implements PostProvider {}

Future<void> _pump(WidgetTester tester, PostProvider postProvider,
    {required List<String> mediaUrls, String caption = 'original caption', String? location}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PostProvider>.value(value: postProvider),
      ],
      child: MaterialApp(
        home: EditPostScreen(
          post: buildPost(caption: caption, mediaUrls: mediaUrls, location: location),
        ),
      ),
    ),
  );
}

void main() {
  late _MockPostProvider postProvider;

  setUp(() {
    postProvider = _MockPostProvider();
  });

  group('M-7: post edit', () {
    testWidgets('fields pre-fill from the passed post', (tester) async {
      await _pump(tester, postProvider,
          mediaUrls: const [], caption: 'my original caption', location: 'DXB');
      await tester.pumpAndSettle();

      expect(find.text('my original caption'), findsOneWidget);
      expect(find.text('DXB'), findsOneWidget);
    });

    testWidgets('Save calls updatePost with the edited values', (tester) async {
      when(() => postProvider.updatePost(any(),
              caption: any(named: 'caption'), location: any(named: 'location')))
          .thenAnswer((_) async {});

      await _pump(tester, postProvider, mediaUrls: const [], caption: 'old', location: null);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'new caption');
      await tester.tap(find.text('Save'));
      await tester.pump();

      verify(() => postProvider.updatePost('post-1',
          caption: 'new caption', location: null)).called(1);
    });

    testWidgets('on a text-only post, clearing the caption blocks save',
        (tester) async {
      await _pump(tester, postProvider, mediaUrls: const [], caption: 'old', location: null);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('A text post needs a caption.'), findsOneWidget);
      verifyNever(() => postProvider.updatePost(any(),
          caption: any(named: 'caption'), location: any(named: 'location')));
    });

    testWidgets('on a media post, an empty caption is allowed to save',
        (tester) async {
      when(() => postProvider.updatePost(any(),
              caption: any(named: 'caption'), location: any(named: 'location')))
          .thenAnswer((_) async {});

      await _pump(tester, postProvider,
          mediaUrls: const ['https://example.com/photo.jpg'], caption: 'old', location: null);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('A text post needs a caption.'), findsNothing);
      verify(() => postProvider.updatePost('post-1',
          caption: '', location: null)).called(1);
    });
  });
}
