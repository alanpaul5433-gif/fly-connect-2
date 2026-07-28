import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/cached_image.dart';

/// Media thumbnail for the admin moderation queues, with tap-to-enlarge.
///
/// Three admin pages moderate user-submitted media and none of them rendered
/// it: promotions drew a hardcoded `Text('IMG')` box, while events
/// (`imageUrl`) and reported posts (`mediaUrls`) read no image field at all.
/// An admin was approving or rejecting content sight-unseen — and for a
/// reported post, the image is frequently the reason it was reported.
///
/// Public and shared so the behaviour is defined once and is reachable from a
/// test: these pages stream live Firestore with no injection seam, so anything
/// left inside them cannot be exercised, which is how a hardcoded placeholder
/// survived review in the first place.
///
/// 100px is too small to judge content on, so tapping opens a full-size
/// [InteractiveViewer] — terms, expiry dates and fine print are often baked
/// into the artwork.
class AdminThumbnail extends StatelessWidget {
  /// Null or empty renders the placeholder. Every caller has a real case for
  /// it: promotions and events make the image optional, and a Storage object
  /// can be deleted after the fact.
  final String? imageUrl;

  /// Screen-reader label context only — admins tab through these queues.
  final String label;

  final double size;

  const AdminThumbnail({
    super.key,
    required this.imageUrl,
    required this.label,
    this.size = 100,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;

    // Doubles as the loading and error visual, so a deleted Storage object or
    // a slow fetch degrades to the same neutral box instead of throwing.
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.backgroundGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text('IMG',
            style: TextStyle(
                color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ),
    );

    if (url == null || url.isEmpty) return placeholder;

    return Semantics(
      button: true,
      label: 'View full-size image for $label',
      child: InkWell(
        onTap: () => _showFullSize(context, url),
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedFeedImage(
            url: url,
            width: size,
            height: size,
            placeholder: placeholder,
            errorWidget: placeholder,
          ),
        ),
      ),
    );
  }

  void _showFullSize(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: CachedFeedImage(url: url, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

/// First displayable image URL on a post document.
///
/// Posts store media as **`mediaUrls`** (a list — posts can carry several),
/// which the content-moderation page never read, so reported images were
/// invisible to the admin deciding on them. `thumbnailUrl` is preferred when
/// present because video posts set it and `mediaUrls[0]` is then a video file
/// the image loader cannot decode.
///
/// Returns null for text-only posts and for anything malformed — this renders
/// in a list, so one bad document must not take the queue down.
String? firstPostMediaUrl(Map<String, dynamic> post) {
  final thumb = post['thumbnailUrl'];
  if (thumb is String && thumb.isNotEmpty) return thumb;

  final media = post['mediaUrls'];
  if (media is List) {
    for (final entry in media) {
      if (entry is String && entry.isNotEmpty) return entry;
    }
  }
  return null;
}
