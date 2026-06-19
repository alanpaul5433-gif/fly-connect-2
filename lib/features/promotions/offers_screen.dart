import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/cached_image.dart';

/// Crew-facing offers browser. Shows business promotions to all users
/// without the create/manage UI that PromotionsScreen exposes to businesses.
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text('Crew Deals', style: AppTextStyles.labelLarge),
        centerTitle: true,
      ),
      body: Consumer<PromotionProvider>(
        builder: (context, provider, _) {
          final all = provider.activePromotions;
          final filtered = _search.isEmpty
              ? all
              : all.where((p) =>
                  p.title.toLowerCase().contains(_search.toLowerCase()) ||
                  p.businessName.toLowerCase().contains(_search.toLowerCase()) ||
                  p.description.toLowerCase().contains(_search.toLowerCase()))
                  .toList();

          return Column(children: [
            // Header banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: AppColors.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.local_offer_rounded, color: AppColors.dark, size: 22),
                    const SizedBox(width: 8),
                    Text('${all.length} active deal${all.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: AppColors.dark,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  const Text('Exclusive savings for FlyConnect crew',
                      style: TextStyle(color: AppColors.dark, fontSize: 12)),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search deals, businesses...',
                  hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.backgroundGrey,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // List
            Expanded(
              child: filtered.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _OfferCard(promo: filtered[i]),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_offer_outlined, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          const Text('No deals available right now',
              style: AppTextStyles.h4),
          const SizedBox(height: 6),
          Text('Check back soon for new offers',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final PromotionModel promo;
  const _OfferCard({required this.promo});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d');
    return GestureDetector(
      onTap: () => context.push('/promotions/${promo.id}'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image with discount badge
          Stack(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: promo.imageUrl != null
                  ? CachedFeedImage(
                      url: promo.imageUrl!,
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: _placeholderImage(),
                    )
                  : _placeholderImage(),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('-${promo.discountPercent}%',
                    style: const TextStyle(
                        color: AppColors.dark,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ),
            ),
          ]),
          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(promo.title, style: AppTextStyles.labelLarge),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.store_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(promo.businessName,
                      style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 8),
              Text(promo.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.online.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.access_time, size: 11, color: AppColors.online),
                    const SizedBox(width: 3),
                    Text('Until ${fmt.format(promo.validTo)}',
                        style: const TextStyle(
                            color: AppColors.online,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
                const Spacer(),
                const Text('View details →',
                    style: TextStyle(
                        color: AppColors.dark,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _placeholderImage() {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1D27), Color(0xFF2D3142)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.local_offer, size: 48, color: AppColors.primary),
      ),
    );
  }
}
