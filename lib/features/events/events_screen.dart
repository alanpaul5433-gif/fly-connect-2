import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/widgets/inline_error_banner.dart';
import '../../shared/providers/event_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/models.dart';
import '../home/main_shell.dart' show AppDrawer;
import '../../shared/widgets/cached_image.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> with SingleTickerProviderStateMixin {
  bool _nearbyEnabled = false;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    // Event/Group creation is restricted to business (and admin) accounts.
    final role = context.watch<AuthProvider>().userRole;
    final canCreate = role == 'business' || role == 'admin';
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppTopBar(
        showMenuIcon: true,
        showBack: Navigator.canPop(context),
        actions: [
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.add, color: AppColors.textPrimary),
              onPressed: () => context.push('/create-event')),
          const TopBarActions(),
        ],
      ),
      body: Consumer<EventProvider>(
        builder: (context, provider, _) {
          final upcoming = provider.events.where((e) => e.isUpcoming).toList();
          final featured = upcoming.where((e) => e.isFeatured).toList();
          final upcomingList = upcoming.where((e) => !e.isFeatured).toList();
          final err = provider.eventsError;

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              // Trigger a fresh snapshot from Firestore
              context.read<EventProvider>().retryEvents();
              await Future.delayed(const Duration(milliseconds: 400));
            },
            child: ListView(children: [
              if (err != null)
                InlineErrorBanner(
                  message: err,
                  onRetry: provider.retryEvents,
                ),
              // Header
              Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(children: [
                  const Expanded(child: Text('Events', style: AppTextStyles.h2)),
                  GestureDetector(
                    onTap: () { setState(() => _nearbyEnabled = !_nearbyEnabled); if (_nearbyEnabled) context.push(AppRoutes.nearby); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _nearbyEnabled ? AppColors.dark : AppColors.backgroundGrey,
                        borderRadius: BorderRadius.circular(100)),
                      child: Row(children: [
                        Icon(Icons.location_on, size: 14, color: _nearbyEnabled ? AppColors.primary : AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('Nearby', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: _nearbyEnabled ? Colors.white : AppColors.textSecondary)),
                      ]))),
                ])),

              // Filter tabs
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TabBar(
                  controller: _tabs,
                  labelColor: AppColors.dark,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 3,
                  tabs: const [Tab(text: 'All'), Tab(text: 'Upcoming'), Tab(text: 'Featured')],
                  onTap: (_) {},
                )),
              const SizedBox(height: 16),

              // Featured banner (if any)
              if (featured.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Featured', style: AppTextStyles.h4)),
                const SizedBox(height: 10),
                SizedBox(height: 200, child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: featured.length,
                  itemBuilder: (_, i) => _FeaturedCard(event: featured[i]))),
                const SizedBox(height: 20),
              ],

              // Create group CTA — business/admin only
              if (canCreate)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.dark, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Create a group activity', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      SizedBox(height: 4),
                      Text('Bring crew members together', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ])),
                    ElevatedButton(
                      onPressed: () => context.push(AppRoutes.createGroup),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.dark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        minimumSize: Size.zero),
                      child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  ]))),
              const SizedBox(height: 20),

              // Upcoming events
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
                child: SectionHeader(title: 'Upcoming Events', actionLabel: 'See All')),
              const SizedBox(height: 12),

              if (upcomingList.isEmpty)
                EmptyState(
                  icon: Icons.event_outlined,
                  title: 'No events yet',
                  subtitle:
                      'Check back soon, or start one yourself for your crew.',
                  actionLabel: canCreate ? 'Create Event' : null,
                  onAction: canCreate ? () => context.push('/create-event') : null,
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: upcomingList.length,
                  itemBuilder: (_, i) => _EventListTile(event: upcomingList[i])),
              const SizedBox(height: 24),
            ]),
          );
        },
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  final EventModel event;
  const _FeaturedCard({required this.event});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push('/events/${event.id}'),
    child: Container(
      width: 280, margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: AppColors.backgroundGrey),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Stack(children: [
            event.imageUrl != null
              ? CachedFeedImage(url: event.imageUrl!, height: 130, width: double.infinity, fit: BoxFit.cover,
                  errorWidget: Container(height: 130, color: AppColors.backgroundGrey))
              : Container(height: 130, color: AppColors.dark,
                  child: const Center(child: Icon(Icons.event, color: AppColors.primary, size: 40))),
            Container(height: 130, decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)]))),
          ])),
        Padding(padding: const EdgeInsets.all(10), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(event.title, style: AppTextStyles.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 2),
            Expanded(child: Text(event.location, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ])),
      ])));
}

class _EventListTile extends StatelessWidget {
  final EventModel event;
  const _EventListTile({required this.event});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push('/events/${event.id}'),
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(10),
          child: event.imageUrl != null
            ? CachedFeedImage(url: event.imageUrl!, width: 70, height: 70, fit: BoxFit.cover,
                errorWidget: Container(width: 70, height: 70, color: AppColors.backgroundGrey,
                  child: const Icon(Icons.event, color: AppColors.textSecondary)))
            : Container(width: 70, height: 70, color: AppColors.dark,
                child: const Center(child: Icon(Icons.event, color: AppColors.primary)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(event.title, style: AppTextStyles.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            // Card is white — primary on white is 1.7:1 (fail). Use dark.
            const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.dark),
            const SizedBox(width: 3),
            Text(DateFormat('MMM d, y').format(event.date),
              style: AppTextStyles.caption.copyWith(color: AppColors.dark, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 3),
            Expanded(child: Text(event.location, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.people_outline, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 3),
            Text('${event.rsvpCount} going', style: AppTextStyles.caption),
          ]),
        ])),
        const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      ]),
    ));
}
