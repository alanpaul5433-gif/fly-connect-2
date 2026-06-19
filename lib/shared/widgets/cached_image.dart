import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Shared image widgets backed by [cached_network_image].
///
/// Two wins over raw `Image.network` / `NetworkImage`:
///   1. **Disk + memory cache** — bytes are fetched once, reused across
///      rebuilds and app sessions (no re-download when a Consumer rebuilds).
///   2. **Decode-time downscaling** via `memCacheWidth/Height` — the bitmap is
///      decoded at the size it's actually displayed, not at full source
///      resolution. A 1000px avatar in a 40px circle stops costing ~4 MB.
///
/// `memCacheWidth` is sized to `logicalPx * devicePixelRatio` so the decode is
/// crisp on high-DPI screens without over-allocating.

/// Circular avatar with caching + the app's letter-fallback behavior.
///
/// Drop-in for `CircleAvatar(backgroundImage: NetworkImage(url), child: Text(..))`.
/// Shows [fallback] (typically the initial) while loading, when [url] is
/// null/empty, and on load error.
class CachedAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final Color? backgroundColor;
  final Widget? fallback;

  const CachedAvatar({
    super.key,
    required this.url,
    required this.radius,
    this.backgroundColor,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackCircle = CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: fallback,
    );
    if (url == null || url!.isEmpty) return fallbackCircle;

    final px = (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        memCacheWidth: px,
        memCacheHeight: px,
        placeholder: (_, __) => fallbackCircle,
        errorWidget: (_, __, ___) => fallbackCircle,
      ),
    );
  }
}

/// Rectangular cached image for feed/post/promo/event imagery.
///
/// Drop-in for `Image.network(url, height:.., width:.., fit:..)`. Pass the
/// existing loading/error visuals via [placeholder] / [errorWidget].
class CachedFeedImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedFeedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Size the in-memory decode to the display width. When width is unbounded
    // (e.g. double.infinity inside a full-bleed card), fall back to the screen
    // width so we never decode wider than the device can show.
    final targetW = (width != null && width!.isFinite)
        ? (width! * dpr).round()
        : (MediaQuery.sizeOf(context).width * dpr).round();

    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: targetW,
      placeholder: placeholder != null ? (_, __) => placeholder! : null,
      errorWidget: errorWidget != null ? (_, __, ___) => errorWidget! : null,
    );
  }
}
