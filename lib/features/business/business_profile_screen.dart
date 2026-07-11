import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/providers.dart';
import '../../shared/providers/event_provider.dart';

class BusinessProfileScreen extends StatefulWidget {
  final bool isOwner;
  const BusinessProfileScreen({super.key, this.isOwner = false});
  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    final biz = context.watch<AuthProvider>().currentUser;
    if (biz == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final promoCount = context.watch<PromotionProvider>().promotions.length;
    final activePromos = context.watch<PromotionProvider>().activePromotions;
    final events = context.watch<EventProvider>().events.take(2).toList();
    final fmt = DateFormat('MMM d, y');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          backgroundColor: AppColors.dark,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
            onPressed: () => GoRouter.of(context).pop(),
          ),
          actions: [
            if (widget.isOwner)
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                onPressed: () => context.push('/edit-profile'),
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              Image.network(
                'https://picsum.photos/seed/cover/800/300',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: AppColors.dark),
              ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
              ),
              Positioned(
                bottom: 20, left: 0, right: 0,
                child: Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.dark,
                    backgroundImage: biz.photoUrl != null ? NetworkImage(biz.photoUrl!) : null,
                    child: biz.photoUrl == null
                      ? Text(biz.name.isNotEmpty ? biz.name[0] : '?',
                          style: const TextStyle(color: AppColors.primary, fontSize: 28, fontWeight: FontWeight.bold))
                      : null,
                  ),
                ),
              ),
            ]),
          ),
        ),

        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(biz.name, style: AppTextStyles.h2)),
              if (biz.isVerified) const Icon(Icons.verified, color: AppColors.primary, size: 22),
            ]),
            const SizedBox(height: 4),

            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(100)),
                child: Text(biz.position ?? 'Business',
                  style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 2),
              Text('${biz.city ?? ''}, ${biz.state ?? ''}', style: AppTextStyles.caption),
            ]),
            const SizedBox(height: 8),

            if (biz.bio != null && biz.bio!.isNotEmpty)
              Text(biz.bio!, style: AppTextStyles.bodyMedium),

            const SizedBox(height: 16),

            // Stats row
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Row(children: [
                const Expanded(child: _StatItem(value: '2,840', label: 'Followers')),
                _VertDivider(),
                Expanded(child: _StatItem(value: '$promoCount', label: 'Crew Deals')),
                _VertDivider(),
                const Expanded(child: _StatItem(value: '3', label: 'Events')),
                _VertDivider(),
                const Expanded(child: _StatItem(value: '1', label: 'Groups')),
              ]),
            ),

            if (!widget.isOwner) ...[
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: ElevatedButton(
                  onPressed: () {
                    setState(() => _following = !_following);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(_following ? 'Following Sky Lounge NYC' : 'Unfollowed Sky Lounge NYC'),
                      duration: const Duration(seconds: 2)));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _following ? Colors.white : AppColors.dark,
                    foregroundColor: _following ? AppColors.dark : AppColors.primary,
                    side: _following ? const BorderSide(color: AppColors.dark) : null,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text(_following ? 'Following' : 'Follow',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                )),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton(
                  onPressed: () => context.push('/conversation/${biz.uid}?name=${Uri.encodeComponent(biz.name)}'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.dark),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Message', style: TextStyle(color: AppColors.dark, fontWeight: FontWeight.bold)),
                )),
              ]),
            ],

            const SizedBox(height: 20),

            const Text('Active Deals', style: AppTextStyles.labelLarge),
            const SizedBox(height: 12),

            if (activePromos.isEmpty)
              const Text('No active deals', style: AppTextStyles.caption)
            else
              SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: activePromos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final p = activePromos[i];
                    return GestureDetector(
                      onTap: () => context.push('/promotions/${p.id}'),
                      child: SizedBox(
                        width: 200,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(fit: StackFit.expand, children: [
                            p.imageUrl != null
                              ? Image.network(p.imageUrl!, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(color: AppColors.dark))
                              : Container(color: AppColors.dark),
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black87]),
                              ),
                            ),
                            Positioned(
                              top: 8, right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary, borderRadius: BorderRadius.circular(100)),
                                child: Text('-${p.discountPercent}%',
                                  style: const TextStyle(color: AppColors.dark, fontWeight: FontWeight.w800, fontSize: 11)),
                              ),
                            ),
                            Positioned(
                              bottom: 10, left: 10, right: 10,
                              child: Text(p.title,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 20),

            const Text('Upcoming Events', style: AppTextStyles.labelLarge),
            const SizedBox(height: 12),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final ev = events[i];
                return GestureDetector(
                  onTap: () => context.push('/events/${ev.id}'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ev.imageUrl != null
                          ? Image.network(ev.imageUrl!, width: 70, height: 70, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(width: 70, height: 70,
                                color: AppColors.backgroundGrey,
                                child: const Icon(Icons.event, color: AppColors.primary)))
                          : Container(width: 70, height: 70, color: AppColors.backgroundGrey,
                              child: const Icon(Icons.event, color: AppColors.primary)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ev.title, style: AppTextStyles.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(fmt.format(ev.date), style: AppTextStyles.caption),
                        const SizedBox(height: 2),
                        Text(ev.location, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                      const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    ]),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),
          ]),
        )),
      ]),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value, label;
  const _StatItem({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: AppTextStyles.h4),
    Text(label, style: AppTextStyles.caption),
  ]);
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
    Container(width: 1, height: 28, color: Colors.grey.shade200);
}
