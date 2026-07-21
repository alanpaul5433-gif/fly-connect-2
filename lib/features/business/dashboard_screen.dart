import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/providers.dart';
import 'business_scope.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().currentUser;
    final name = user?.name ?? 'Business';
    // H19: every headline number here is scoped to THIS business. Previously
    // they summed across every business's promotions and events.
    final myPromos = ownPromotions(
        context.watch<PromotionProvider>().promotions, user?.uid);
    final activePromoCount = myPromos.where((p) => p.isActive && p.isApproved).length;
    final totalPromoViews = myPromos.fold<int>(0, (sum, p) => sum + p.views);
    final upcomingEventCount = ownEvents(
        context.watch<EventProvider>().events, user?.uid)
        .where((e) => e.date.isAfter(DateTime.now())).length;
    final followerCount = user?.followerCount ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Dashboard', style: AppTextStyles.labelLarge),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: AppColors.textPrimary),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined, color: AppColors.textPrimary),
            onPressed: () => context.push('/analytics'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Greeting row
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF1A1D27),
              backgroundImage: user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
              child: user?.photoUrl == null
                  ? Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: Color(0xFFD4F53C), fontWeight: FontWeight.bold, fontSize: 18))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Good morning,', style: AppTextStyles.caption),
              Text(name, style: AppTextStyles.labelLarge),
            ])),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary, size: 20),
              onPressed: () => context.push('/settings'),
            ),
          ]),

          const SizedBox(height: 20),
          const Text('Overview', style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),

          // 2x2 stats grid — all values sourced from providers
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _StatCard(icon: Icons.people_outline, value: followerCount.toString(), label: 'Followers'),
              _StatCard(icon: Icons.local_offer_outlined, value: '$activePromoCount', label: 'Active Deals'),
              _StatCard(icon: Icons.event_outlined, value: '$upcomingEventCount', label: 'Upcoming Events'),
              _StatCard(icon: Icons.visibility_outlined, value: '$totalPromoViews', label: 'Promo Views'),
            ],
          ),

          const SizedBox(height: 24),
          const Text('Quick Actions', style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(child: _QuickAction(
              icon: Icons.local_offer,
              label: 'Create Deal',
              onTap: () => context.push('/promotions/create'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _QuickAction(
              icon: Icons.event,
              label: 'Create Event',
              onTap: () => context.push('/create-event'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _QuickAction(
              icon: Icons.group_add,
              label: 'Create Group',
              onTap: () => context.push('/create-group'),
            )),
          ]),

          const SizedBox(height: 24),
          const Text('Recent Activity', style: AppTextStyles.labelLarge),
          const SizedBox(height: 12),
          _RecentActivitySection(),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatCard({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: const Color(0xFFD4F53C), size: 22),
        const SizedBox(height: 8),
        Text(value, style: AppTextStyles.h2.copyWith(color: const Color(0xFFD4F53C))),
        Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white70)),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D27),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: const Color(0xFFD4F53C), size: 22),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Color(0xFFD4F53C), fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

/// Shows recent promotion + event activity derived from real provider data.
class _RecentActivitySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // H19: "recent activity" (top promotion, redemption leader, top event) is
    // this business's own, not whichever business happens to lead globally.
    final me = context.watch<UserProvider>().currentUser?.uid;
    final promotions = ownPromotions(
        context.watch<PromotionProvider>().promotions, me);
    final events = ownEvents(context.watch<EventProvider>().events, me);

    final items = <_ActivityItem>[];

    // Most-viewed active promotion
    final activePromos = promotions.where((p) => p.isActive).toList()
      ..sort((a, b) => b.views.compareTo(a.views));
    if (activePromos.isNotEmpty) {
      final top = activePromos.first;
      items.add(_ActivityItem(
        icon: Icons.local_offer_outlined,
        iconColor: Colors.orange,
        title: '"${top.title}" · ${top.views} views, ${top.saves} saves',
      ));
    }

    // Upcoming events with most RSVPs
    final upcoming = events.where((e) => e.date.isAfter(DateTime.now())).toList()
      ..sort((a, b) => b.rsvpCount.compareTo(a.rsvpCount));
    if (upcoming.isNotEmpty) {
      final top = upcoming.first;
      items.add(_ActivityItem(
        icon: Icons.event_available,
        iconColor: Colors.green,
        title: '"${top.title}" · ${top.rsvpCount} RSVPs',
      ));
    }

    // Promotion redemption leader
    final redeemed = promotions.where((p) => p.currentRedemptions > 0).toList()
      ..sort((a, b) => b.currentRedemptions.compareTo(a.currentRedemptions));
    if (redeemed.isNotEmpty) {
      final top = redeemed.first;
      items.add(_ActivityItem(
        icon: Icons.confirmation_number_outlined,
        iconColor: Colors.purple,
        title: '"${top.title}" · ${top.currentRedemptions} redemptions used',
      ));
    }

    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100)),
        child: const Center(
          child: Text('No activity yet. Create a deal or event to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        ),
      );
    }

    return Column(
      children: items.map((item) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: item.iconColor.withValues(alpha: 0.12),
            child: Icon(item.icon, color: item.iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(item.title,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary),
            maxLines: 2)),
        ]),
      )).toList(),
    );
  }
}

class _ActivityItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  const _ActivityItem({required this.icon, required this.iconColor, required this.title});
}
