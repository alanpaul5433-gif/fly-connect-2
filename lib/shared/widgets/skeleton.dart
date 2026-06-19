import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// A subtle "loading placeholder" block.
///
/// Use these in place of a `CircularProgressIndicator` on screens where
/// the user is about to see structured content (feed cards, list rows,
/// admin tables). Skeletons feel faster than spinners because the user
/// can already see the shape of what's coming.
///
/// Animation is intentionally cheap: a single `AnimatedBuilder` driving
/// a colour tween. We do NOT use shimmer (extra dependency, more paint).
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
  });

  const Skeleton.circle({super.key, double size = 40})
      : width = size,
        height = size,
        radius = size / 2;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // Subtle pulse: 0xFFE7E8EB ↔ 0xFFF3F4F6
        final t = _ctrl.value;
        final colour = Color.lerp(
          const Color(0xFFE7E8EB),
          const Color(0xFFF3F4F6),
          t,
        )!;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Skeleton placeholder for a feed post card.
/// Approximate dimensions match `_PostCard` in home_screen.dart so the
/// transition from skeleton → real card is visually stable.
class FeedPostSkeleton extends StatelessWidget {
  const FeedPostSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Skeleton.circle(size: 40),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 130, height: 14),
                  SizedBox(height: 6),
                  Skeleton(width: 80, height: 10),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: const Skeleton(
                width: double.infinity, height: 220, radius: 12),
          ),
          const SizedBox(height: 12),
          const Skeleton(width: double.infinity, height: 12),
          const SizedBox(height: 6),
          const Skeleton(width: 220, height: 12),
          const SizedBox(height: 14),
          const Row(children: [
            Skeleton(width: 50, height: 12),
            SizedBox(width: 16),
            Skeleton(width: 50, height: 12),
            SizedBox(width: 16),
            Skeleton(width: 50, height: 12),
          ]),
        ],
      ),
    );
  }
}

/// A reusable "branded" empty-state placeholder that pairs an icon, a
/// short headline, an explanation, and an optional CTA.
///
/// Use this instead of the various ad-hoc "No X" Text widgets scattered
/// across the app so empty screens feel intentional, not broken.
class BrandedEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;

  const BrandedEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppColors.dark),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: onCta,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.dark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    ctaLabel!,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
