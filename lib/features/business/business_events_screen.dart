import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/event_provider.dart';
import '../../shared/widgets/cached_image.dart';

class BusinessEventsScreen extends StatelessWidget {
  const BusinessEventsScreen({super.key});

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
          title: const Text('Events', style: AppTextStyles.labelLarge),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: AppColors.textPrimary),
              onPressed: () => context.push('/create-event'),
            ),
          ],
          bottom: const TabBar(
            labelColor: AppColors.dark,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            tabs: [Tab(text: 'Upcoming'), Tab(text: 'Past')],
          ),
        ),
        body: Consumer<EventProvider>(
          builder: (context, provider, _) {
            final now = DateTime.now();
            final upcoming = provider.events.where((e) => e.date.isAfter(now)).toList();
            final past = provider.events.where((e) => e.date.isBefore(now)).toList();
            return TabBarView(children: [
              _EventList(events: upcoming, isPast: false),
              _EventList(events: past, isPast: true),
            ]);
          },
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.dark,
          onPressed: () => context.push('/create-event'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  final List<EventModel> events;
  final bool isPast;
  const _EventList({required this.events, required this.isPast});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.event_outlined, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(isPast ? 'No past events' : 'No upcoming events',
          style: const TextStyle(color: Colors.grey)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (_, i) => _EventCard(event: events[i]),
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventModel event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, y · h:mm a');
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (event.imageUrl != null)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Stack(children: [
              CachedFeedImage(url: event.imageUrl!, height: 120, width: double.infinity, fit: BoxFit.cover,
                errorWidget: Container(height: 120, color: AppColors.backgroundGrey,
                  child: const Center(child: Icon(Icons.event, size: 48, color: AppColors.primary)))),
              Positioned(top: 8, right: 8, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(100)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.people_outline, size: 12, color: AppColors.dark),
                  const SizedBox(width: 4),
                  Text('${event.rsvpCount}', style: const TextStyle(
                    color: AppColors.dark, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              )),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.title, style: AppTextStyles.labelMedium),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(fmt.format(event.date), style: AppTextStyles.caption),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 12, color: AppColors.primary),
              const SizedBox(width: 4),
              Expanded(child: Text(event.location, style: AppTextStyles.caption,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push('/business-event-management', extra: event),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dark,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Manage', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
