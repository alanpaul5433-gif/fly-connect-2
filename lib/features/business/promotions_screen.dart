import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/widgets/cached_image.dart';

class PromotionsScreen extends StatelessWidget {
  const PromotionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text('Crew Deals', style: AppTextStyles.labelLarge),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: AppColors.textPrimary),
              onPressed: () => context.push('/promotions/create'),
            ),
          ],
          bottom: const TabBar(
            labelColor: AppColors.dark,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            tabs: [Tab(text: 'Active'), Tab(text: 'Expired')],
          ),
        ),
        body: Consumer<PromotionProvider>(
          builder: (context, provider, _) => TabBarView(
            children: [
              _PromotionList(promotions: provider.activePromotions),
              _PromotionList(promotions: provider.expiredPromotions),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromotionList extends StatelessWidget {
  final List<PromotionModel> promotions;
  const _PromotionList({required this.promotions});

  @override
  Widget build(BuildContext context) {
    if (promotions.isEmpty) {
      return const EmptyState(
        icon: Icons.local_offer_outlined,
        title: 'No deals yet',
        subtitle: 'Create your first deal to reach more customers.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: promotions.length,
      itemBuilder: (_, i) => _PromotionCard(promo: promotions[i]),
    );
  }
}

class _PromotionCard extends StatelessWidget {
  final PromotionModel promo;
  const _PromotionCard({required this.promo});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy');
    final isActive = promo.isActive;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (promo.imageUrl != null)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: CachedFeedImage(url: promo.imageUrl!, height: 140, width: double.infinity, fit: BoxFit.cover,
              errorWidget: Container(height: 140, color: AppColors.backgroundGrey)),
          ),
        Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(promo.title, style: AppTextStyles.labelMedium)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFD4F53C),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text('-${promo.discountPercent}%',
                style: const TextStyle(color: Color(0xFF1A1D27), fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(promo.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.calendar_today, size: 12, color: AppColors.primary),
            const SizedBox(width: 4),
            Text('${fmt.format(promo.validFrom)} – ${fmt.format(promo.validTo)}', style: AppTextStyles.caption),
            const Spacer(),
            Text(isActive ? 'Active' : 'Expired',
              style: TextStyle(
                color: isActive ? Colors.green : Colors.red,
                fontWeight: FontWeight.w600, fontSize: 11)),
          ]),
          const Divider(height: 20),
          Row(children: [
            const Icon(Icons.visibility_outlined, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('${promo.views}', style: AppTextStyles.caption),
            const SizedBox(width: 12),
            const Icon(Icons.bookmark_outline, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('${promo.saves}', style: AppTextStyles.caption),
            const SizedBox(width: 12),
            const Icon(Icons.check_circle_outline, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('${promo.currentRedemptions}/${promo.maxRedemptions}', style: AppTextStyles.caption),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: () => context.push('/promotions/${promo.id}'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  minimumSize: const Size(100, 36),
                  side: const BorderSide(color: AppColors.dark),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('View Details', style: TextStyle(color: AppColors.dark, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () {
                final link = 'https://flyconnect.co/promotions/${promo.id}';
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Deal link copied to clipboard'),
                  duration: Duration(seconds: 2)));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4F53C),
                foregroundColor: const Color(0xFF1A1D27),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              ),
              child: const Text('Share', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ]),
        ])),
      ]),
    );
  }
}
