import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/providers.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/widgets/inline_error_banner.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // Distinguishes "notifications still loading" from "loaded but empty",
  // so the empty state doesn't flash on cold start before the first
  // snapshot returns.
  bool _initialLoadComplete = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _initialLoadComplete = true);
    });
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'like': return Icons.favorite;
      case 'comment': return Icons.chat_bubble;
      case 'follow': return Icons.person_add;
      case 'match': return Icons.favorite_border;
      case 'message': return Icons.message;
      case 'event': return Icons.event;
      case 'group': return Icons.groups;
      case 'promotion': return Icons.local_offer;
      default: return Icons.notifications;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'like': return Colors.red;
      case 'match': return Colors.pink;
      case 'comment': return Colors.blue;
      case 'follow': return Colors.green;
      default: return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.dark), onPressed: () => context.pop()),
        title: Text('Notifications', style: AppTextStyles.h3.copyWith(color: AppColors.dark)),
        actions: [TextButton(
          onPressed: () => context.read<NotificationProvider>().markAllAsRead(),
          // Contrast: 'Mark all read' sits in a white AppBar — primary fails AA (1.7:1).
          child: const Text('Mark all read', style: TextStyle(color: AppColors.dark, fontSize: 13, fontWeight: FontWeight.w600)),
        )],
      ),
      body: Consumer<NotificationProvider>(
        builder: (ctx, provider, _) {
          final notifications = provider.notifications;
          final err = provider.notificationsError;
          if (notifications.isNotEmpty && !_initialLoadComplete) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _initialLoadComplete = true);
            });
          }
          if (err != null && notifications.isEmpty) {
            return Column(children: [
              InlineErrorBanner(
                message: err,
                onRetry: provider.retryNotifications,
              ),
              const Expanded(child: SizedBox.shrink()),
            ]);
          }
          if (notifications.isEmpty) {
            if (!_initialLoadComplete) {
              return const _NotificationsSkeleton();
            }
            return const EmptyState(
              icon: Icons.notifications_off_outlined,
              title: 'All caught up!',
              subtitle: "When someone likes, comments, or messages you, you'll see it here.",
            );
          }
          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (_, i) {
              final n = notifications[i];
              return Dismissible(
                key: Key(n.id),
                direction: DismissDirection.endToStart,
                background: Container(color: Colors.red, alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline, color: Colors.white)),
                onDismissed: (_) => provider.delete(n.id),
                child: InkWell(
                  onTap: () {
                    provider.markAsRead(n.id);
                    if (n.deepLink != null) context.push(n.deepLink!);
                  },
                  child: Container(
                    color: n.isRead ? null : AppColors.primary.withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 44, height: 44,
                        decoration: BoxDecoration(color: _colorForType(n.type).withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: Icon(_iconForType(n.type), color: _colorForType(n.type), size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(n.title, style: AppTextStyles.labelMedium.copyWith(color: AppColors.dark,
                          fontWeight: n.isRead ? FontWeight.normal : FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(n.body, style: TextStyle(color: AppColors.dark.withValues(alpha: 0.6), fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(timeago.format(n.createdAt),
                          style: TextStyle(color: AppColors.dark.withValues(alpha: 0.4), fontSize: 11)),
                      ])),
                      // Unread dot carries state — needs 3:1 vs the white
                      // tile. Primary fails (1.7:1); badge red is 5.5:1 and
                      // matches platform unread conventions.
                      if (!n.isRead) Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4),
                        decoration: const BoxDecoration(color: AppColors.badge, shape: BoxShape.circle)),
                    ]),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Skeleton.circle(size: 40),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 160, height: 12),
                SizedBox(height: 8),
                Skeleton(width: 80, height: 10),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
