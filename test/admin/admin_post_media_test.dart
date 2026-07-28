import 'package:flutter_test/flutter_test.dart';
import 'package:flyconnect/features/admin/admin_thumbnail.dart';

/// The content-moderation queue read `authorName`, `caption` and `reportCount`
/// off reported posts but never touched `mediaUrls`, where the image actually
/// lives (verified against production posts). An admin therefore decided
/// whether to delete a reported post, and whether to ban its author, without
/// ever seeing the image — which is frequently the reason it was reported.
///
/// `mediaUrls` is a list because a post can carry several images, and video
/// posts additionally set `thumbnailUrl`. Preferring the thumbnail matters:
/// for a video post `mediaUrls[0]` is a video file, which the image loader
/// cannot decode, so reaching for it first would show a broken box on exactly
/// the content most likely to need review.
void main() {
  group('firstPostMediaUrl', () {
    test('returns the first media URL on an image post', () {
      expect(
        firstPostMediaUrl({
          'mediaUrls': ['https://example.com/a.jpg', 'https://example.com/b.jpg']
        }),
        'https://example.com/a.jpg',
      );
    });

    test('prefers thumbnailUrl, because mediaUrls[0] may be a video', () {
      expect(
        firstPostMediaUrl({
          'mediaType': 'video',
          'thumbnailUrl': 'https://example.com/thumb.jpg',
          'mediaUrls': ['https://example.com/clip.mp4'],
        }),
        'https://example.com/thumb.jpg',
      );
    });

    test('returns null for a text-only post', () {
      // Real shape: production posts store an empty caption with no media.
      expect(firstPostMediaUrl({'caption': 'just text', 'mediaUrls': []}),
          isNull);
    });

    test('returns null when the field is absent entirely', () {
      expect(firstPostMediaUrl({'caption': 'hi'}), isNull);
    });

    test('ignores a null thumbnailUrl, which production posts do set', () {
      expect(
        firstPostMediaUrl({
          'thumbnailUrl': null,
          'mediaUrls': ['https://example.com/a.jpg'],
        }),
        'https://example.com/a.jpg',
      );
    });

    test('skips empty and non-string entries rather than returning them', () {
      expect(
        firstPostMediaUrl({
          'mediaUrls': ['', 42, null, 'https://example.com/real.jpg']
        }),
        'https://example.com/real.jpg',
      );
    });

    test('survives mediaUrls being the wrong type', () {
      // One malformed document must not take down a queue of 30 cards.
      expect(firstPostMediaUrl({'mediaUrls': 'not-a-list'}), isNull);
    });
  });
}
