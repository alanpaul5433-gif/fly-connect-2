import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/providers.dart';
import 'business_scope.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  Widget build(BuildContext context) {
    final me = context.watch<UserProvider>().currentUser;
    final realFollowers = me?.followerCount ?? 0;
    // H19: scope to THIS business. The provider streams every business's
    // promotions (the public Crew Deals feed needs them); aggregating that raw
    // list showed Business A the titles/views/saves/redemptions of Business B.
    final promotions = ownPromotions(
        context.watch<PromotionProvider>().promotions, me?.uid);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => GoRouter.of(context).pop(),
        ),
        title: const Text('Analytics', style: AppTextStyles.labelLarge),
        // The 7/30/90-day range selector drove only the demo bar chart, which
        // is gone (H20) — real growth is a single since-baseline figure.
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Top metric cards — H20: every value is now real and scoped to this
          // business (Growth/Reach/Engagement were hardcoded literals like
          // '+12%'/'8,420' presented as measured data). Metrics that need
          // historical snapshots or impression tracking we don't collect were
          // dropped rather than fabricated.
          Row(children: [
            Expanded(child: _MetricCard(value: realFollowers.toString(), label: 'Followers')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(value: '${activeDealCount(promotions)}', label: 'Deals')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(value: '${totalViews(promotions)}', label: 'Views')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(value: '${totalRedemptions(promotions)}', label: 'Redeemed')),
          ]),

          const SizedBox(height: 10),
          // H20: real engagement rates derived from data we already collect —
          // no fabrication, no time-series infra needed.
          Row(children: [
            Expanded(child: _RateChip(
              label: 'Redemption rate',
              value: '${(redemptionRate(promotions) * 100).toStringAsFixed(1)}%')),
            const SizedBox(width: 10),
            Expanded(child: _RateChip(
              label: 'Save rate',
              value: '${(saveRate(promotions) * 100).toStringAsFixed(1)}%')),
          ]),

          const SizedBox(height: 24),

          const Text('Follower Growth', style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),
          // H20: real growth from the daily follower snapshots the scheduled
          // Cloud Function writes — replaces the "Demo chart" of fabricated
          // bars. Reads empty until history accrues, never a made-up number.
          _FollowerGrowth(uid: me?.uid, currentFollowers: realFollowers),

          const SizedBox(height: 24),

          const Text('Crew Deal Performance', style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: promotions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final p = promotions[i];
              final progress = p.maxRedemptions > 0
                  ? (p.currentRedemptions / p.maxRedemptions).clamp(0.0, 1.0)
                  : 0.0;
              return GestureDetector(
                onTap: () => context.push('/promotions/${p.id}'),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.percent, color: AppColors.dark, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.title, style: AppTextStyles.labelMedium,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(p.isActive ? 'Active' : 'Expired',
                          style: TextStyle(
                            color: p.isActive ? Colors.green : Colors.red,
                            fontSize: 11, fontWeight: FontWeight.w600)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${p.views} views',
                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
                        Text('${p.saves} saves', style: AppTextStyles.caption),
                      ]),
                    ]),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 6,
                    ),
                    const SizedBox(height: 4),
                    Text('${p.currentRedemptions}/${p.maxRedemptions} redemptions',
                      style: AppTextStyles.caption),
                  ]),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          const Text('Event Attendance', style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),

          Consumer<EventProvider>(builder: (_, eventProvider, __) {
            final uid = context.read<AuthProvider>().currentUser?.uid;
            // Scope to this business's own events — the unfiltered global
            // list previously meant "Event Attendance" showed events other
            // businesses created, and tapping one would open it for
            // management regardless of who created it.
            final events = eventProvider.events.where((e) => e.createdBy == uid).take(3).toList();
            if (events.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Center(
                  child: Text('No events yet',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final e = events[i];
              final progress = (e.rsvpCount / 50).clamp(0.0, 1.0);
              return GestureDetector(
                onTap: () => context.push('/business-event-management', extra: e),
                child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(e.title, style: AppTextStyles.labelMedium,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${e.rsvpCount}',
                        style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
                      const Text(' RSVPs', style: AppTextStyles.caption),
                    ]),
                  ]),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 6,
                  ),
                ]),
              ),
              );
            },
            );
          }),

          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String value, label;
  const _MetricCard({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
    decoration: BoxDecoration(
      color: AppColors.dark, borderRadius: BorderRadius.circular(14)),
    child: Column(children: [
      Text(value, style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
      const SizedBox(height: 2),
      Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white70),
        textAlign: TextAlign.center),
    ]),
  );
}

/// Real follower growth (H20) from `users/{uid}/dailyStats` — the earliest
/// snapshot is the baseline, compared to the current followerCount. Shows
/// "building history…" until the scheduled snapshotter has run at least once.
class _FollowerGrowth extends StatelessWidget {
  final String? uid;
  final int currentFollowers;
  const _FollowerGrowth({required this.uid, required this.currentFollowers});

  @override
  Widget build(BuildContext context) {
    final id = uid;
    Widget shell(Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.dark, borderRadius: BorderRadius.circular(16)),
      child: child,
    );
    final building = shell(Text('Building history — check back in a few days.',
        style: AppTextStyles.bodySmall.copyWith(color: Colors.white70)));
    if (id == null) return building;

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users').doc(id).collection('dailyStats')
          .orderBy(FieldPath.documentId).limit(1).get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return shell(const Center(
            child: SizedBox(height: 20, width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))));
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return building;

        final baseline = (docs.first.data()['followerCount'] as num?)?.toInt();
        final since = docs.first.id; // yyyy-mm-dd
        final g = growthFraction(current: currentFollowers, baseline: baseline);
        if (g == null) return building;

        final up = g >= 0;
        final pct = '${up ? '+' : ''}${(g * 100).toStringAsFixed(1)}%';
        return shell(Row(children: [
          Icon(up ? Icons.trending_up : Icons.trending_down,
            color: up ? AppColors.primary : Colors.redAccent),
          const SizedBox(width: 10),
          Text(pct, style: AppTextStyles.h3.copyWith(
            color: up ? AppColors.primary : Colors.redAccent)),
          const SizedBox(width: 10),
          Expanded(child: Text('since $since',
            style: AppTextStyles.caption.copyWith(color: Colors.white54))),
        ]));
      },
    );
  }
}

/// Compact engagement-rate pill (H20). Lighter than a _MetricCard since a rate
/// is a derived percentage, not a headline total.
class _RateChip extends StatelessWidget {
  final String value, label;
  const _RateChip({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    decoration: BoxDecoration(
      color: AppColors.backgroundGrey, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Expanded(child: Text(label, style: AppTextStyles.caption)),
      Text(value, style: AppTextStyles.labelMedium.copyWith(color: AppColors.dark)),
    ]),
  );
}
