import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/user_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'business_scope.dart';

class PromotionDetailScreen extends StatelessWidget {
  final PromotionModel promotion;
  const PromotionDetailScreen({super.key, required this.promotion});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy');
    final p = promotion;
    final redemptionPct = p.maxRedemptions > 0 ? p.currentRedemptions / p.maxRedemptions : 0.0;
    final savesPct = p.views > 0 ? p.saves / p.views : 0.0;

    // Performance metrics (views/saves/redemptions) belong to the business that
    // runs the promotion — or an admin moderating it. Crew browsing a deal must
    // never see another company's analytics. Fail closed when the viewer is unknown.
    final me = context.watch<UserProvider>().currentUser;
    final isOwnerOrAdmin =
        me != null && (me.uid == p.businessId || me.role == 'admin');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: const Color(0xFF1A1D27),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
              onPressed: () => GoRouter.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: p.imageUrl != null
                  ? Image.network(p.imageUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1A1D27)))
                  : Container(color: const Color(0xFF1A1D27)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Title + discount badge
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(p.title, style: AppTextStyles.h3)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4F53C),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text('-${p.discountPercent}%',
                      style: const TextStyle(color: Color(0xFF1A1D27), fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(p.businessName, style: AppTextStyles.caption),
                const SizedBox(height: 12),

                // Validity
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.backgroundGrey),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('${fmt.format(p.validFrom)} – ${fmt.format(p.validTo)}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary)),
                    const Spacer(),
                    Text(p.isActive ? 'Active' : 'Expired',
                      style: TextStyle(
                        color: p.isActive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w700, fontSize: 11)),
                  ]),
                ),
                const SizedBox(height: 16),

                // Description
                Text(p.description, style: AppTextStyles.bodyMedium),

                // Business-only: a crew member browsing the deal must not see the
                // promoting business's performance metrics.
                if (isOwnerOrAdmin) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    _StatChip(icon: Icons.visibility_outlined, label: '${p.views} views'),
                    const SizedBox(width: 10),
                    _StatChip(icon: Icons.bookmark_outline, label: '${p.saves} saves'),
                    const SizedBox(width: 10),
                    _StatChip(icon: Icons.check_circle_outline, label: '${p.currentRedemptions}/${p.maxRedemptions}'),
                  ]),
                ],

                const Divider(height: 32),

                // QR Code section
                const Text('Redemption QR Code', style: AppTextStyles.labelLarge),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D27),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Show this QR code at the venue',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                        textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      // H21: was a 6×6 GridView coloured by `i % 3 == 0` — a
                      // decorative grid that looked like a QR code but encoded
                      // nothing, so it could never actually be scanned. Now a
                      // real QR of the promotion's redemption code.
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(8),
                        child: QrImageView(
                          data: redemptionCode(p.id),
                          version: QrVersions.auto,
                          size: 160,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(p.id, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
                    ]),
                  ),
                ),

                // Business-only analytics — hidden from crew browsing the deal.
                if (isOwnerOrAdmin) ...[
                  const Divider(height: 32),
                  const Text('Analytics', style: AppTextStyles.labelLarge),
                  const SizedBox(height: 12),
                  _AnalyticsBar(label: 'Views', value: p.views, progress: 1.0),
                  const SizedBox(height: 10),
                  _AnalyticsBar(label: 'Saves', value: p.saves, progress: savesPct.clamp(0.0, 1.0)),
                  const SizedBox(height: 10),
                  _AnalyticsBar(label: 'Redemptions', value: p.currentRedemptions, progress: redemptionPct.clamp(0.0, 1.0)),
                ],
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.backgroundGrey),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.caption),
      ]),
    );
  }
}

class _AnalyticsBar extends StatelessWidget {
  final String label;
  final int value;
  final double progress;
  const _AnalyticsBar({required this.label, required this.value, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary)),
        const Spacer(),
        Text('$value', style: AppTextStyles.labelMedium),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: AppColors.backgroundGrey,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          minHeight: 6,
        ),
      ),
    ]);
  }
}
