import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/event_provider.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/widgets/cached_image.dart';
import '../../shared/widgets/organizer_row.dart';

class EventDetailsScreen extends StatefulWidget {
  final String? eventId;
  const EventDetailsScreen({super.key, this.eventId});
  @override State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  EventModel? _event;
  UserModel? _organizer;
  bool _loading = true;
  bool _hasError = false;
  bool _rsvpd = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _hasError = false; });
    if (widget.eventId == null) { setState(() => _loading = false); return; }
    try {
      final eventProvider = context.read<EventProvider>();
      final userProvider = context.read<UserProvider>();
      final events = eventProvider.events;
      final match = events.where((e) => e.id == widget.eventId).firstOrNull;
      if (match != null) {
        final rsvpd = await eventProvider.hasRsvped(match.id);
        final organizer = await userProvider.fetchUser(match.createdBy);
        if (mounted) setState(() { _event = match; _organizer = organizer; _rsvpd = rsvpd; _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _toggleRsvp() async {
    final wasRsvpd = _rsvpd;
    setState(() => _rsvpd = !_rsvpd);
    try {
      await context.read<EventProvider>().toggleRsvp(_event!.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _rsvpd = wasRsvpd);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update RSVP: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    if (_hasError) {
      return Scaffold(
      appBar: AppBar(leading: const BackButton(), backgroundColor: Colors.white),
      body: EmptyState(
        icon: Icons.wifi_off_outlined,
        title: 'Failed to load event',
        subtitle: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: _load,
      ));
    }
    if (_event == null) {
      return Scaffold(
      appBar: AppBar(leading: const BackButton(), backgroundColor: Colors.white),
      body: const EmptyState(
        icon: Icons.event_busy_outlined,
        title: 'Event not found',
        subtitle: 'This event may have been removed.',
      ));
    }

    final e = _event!;
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 240, pinned: true,
          backgroundColor: AppColors.dark,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
            onPressed: () => GoRouter.of(context).pop()),
          actions: [
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
              onPressed: () => context.push(
                '/conversation/evt_${e.id}?name=${Uri.encodeComponent(e.title)}&group=true')),
            IconButton(
              icon: const Icon(Icons.share_outlined, color: Colors.white),
              onPressed: () {
                final link = 'https://flyconnect.co/events/${e.id}';
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Event link copied to clipboard'),
                  duration: Duration(seconds: 2),
                ));
              },
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              e.imageUrl != null
                ? CachedFeedImage(url: e.imageUrl!, fit: BoxFit.cover,
                    errorWidget: Container(color: AppColors.dark))
                : Container(color: AppColors.dark,
                    child: const Center(child: Icon(Icons.event, color: AppColors.primary, size: 72))),
              Container(decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)]))),
            ]),
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (e.isFeatured) Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
              child: const Text('FEATURED', style: TextStyle(color: AppColors.dark, fontSize: 11, fontWeight: FontWeight.w800))),
            Text(e.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            if (_organizer != null) ...[
              const SizedBox(height: 8),
              OrganizerRow(organizer: _organizer!),
            ],
            const SizedBox(height: 16),
            _InfoRow(icon: Icons.calendar_today_outlined,
              text: '${DateFormat('EEEE, MMM d, y').format(e.date)} · ${e.time}'),
            const SizedBox(height: 8),
            _InfoRow(icon: Icons.location_on_outlined, text: e.location),
            const SizedBox(height: 8),
            _InfoRow(icon: Icons.people_outline, text: '${e.rsvpCount} people going'),
            const SizedBox(height: 20),
            const Text('About', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(e.description, style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.6)),
            if (e.requirements.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Requirements', style: AppTextStyles.h4),
              const SizedBox(height: 8),
              ...e.requirements.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(r, style: const TextStyle(fontSize: 14)),
                ]))),
            ],
            const SizedBox(height: 32),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _toggleRsvp,
              style: ElevatedButton.styleFrom(
                backgroundColor: _rsvpd ? Colors.white : AppColors.primary,
                foregroundColor: _rsvpd ? Colors.red : AppColors.dark,
                side: _rsvpd ? const BorderSide(color: Colors.red) : null,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: Text(_rsvpd ? 'Cancel RSVP' : 'RSVP Now',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
            const SizedBox(height: 32),
          ]),
        )),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String text;
  const _InfoRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 18, color: AppColors.primary),
    const SizedBox(width: 10),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.black87))),
  ]);
}
