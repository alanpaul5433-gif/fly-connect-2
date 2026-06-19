import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/widgets/inline_error_banner.dart';
import '../../shared/widgets/cached_image.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  // Distinguishes "chat list is still loading" from "list loaded but empty",
  // mirroring the pattern used in home_screen. Without this, the screen
  // flashes the empty state on every cold start before the first snapshot
  // returns — which feels broken.
  bool _initialLoadComplete = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Fail-safe: after 4s assume the chat list has loaded (or failed
    // silently) so we don't show skeletons forever.
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _initialLoadComplete = true);
    });
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  void _markLoaded() {
    if (!_initialLoadComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _initialLoadComplete = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        title: const Text('Messages', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
        actions: [
          IconButton(icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () => context.push(AppRoutes.search)),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.black),
            tooltip: 'New message',
            onPressed: () => context.push(AppRoutes.nearby),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.dark,
          unselectedLabelColor: Colors.grey,
          // Tab indicator on a white AppBar — primary fails 3:1, dark passes.
          indicatorColor: AppColors.dark,
          indicatorWeight: 3,
          tabs: const [Tab(text: 'Direct'), Tab(text: 'Groups')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DmList(
            initialLoadComplete: _initialLoadComplete,
            onLoaded: _markLoaded,
          ),
          _GroupList(
            initialLoadComplete: _initialLoadComplete,
            onLoaded: _markLoaded,
          ),
        ],
      ),
    );
  }
}

class _DmList extends StatelessWidget {
  final bool initialLoadComplete;
  final VoidCallback onLoaded;
  const _DmList({required this.initialLoadComplete, required this.onLoaded});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final uid = context.read<AuthProvider>().currentUser?.uid ?? '';
        final dms = provider.chats.where((c) => c.type == 'dm').toList();
        final err = provider.chatsError;

        if (dms.isNotEmpty) onLoaded();

        if (err != null && dms.isEmpty) {
          return Column(children: [
            InlineErrorBanner(
              message: err,
              onRetry: provider.retryChats,
            ),
            const Expanded(child: SizedBox.shrink()),
          ]);
        }

        if (dms.isEmpty) {
          if (!initialLoadComplete) {
            return const _ChatListSkeleton();
          }
          return EmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'No conversations yet',
            subtitle: 'Connect with crew nearby or via Match to start chatting.',
            actionLabel: 'Find People',
            onAction: () => context.push('/nearby'),
          );
        }

        return ListView.separated(
          itemCount: dms.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.backgroundGrey, indent: 76),
          itemBuilder: (context, i) => _ChatTile(chat: dms[i], currentUid: uid),
        );
      },
    );
  }
}

class _GroupList extends StatelessWidget {
  final bool initialLoadComplete;
  final VoidCallback onLoaded;
  const _GroupList({required this.initialLoadComplete, required this.onLoaded});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final uid = context.read<AuthProvider>().currentUser?.uid ?? '';
        final groups = provider.chats.where((c) => c.type == 'group').toList();
        final err = provider.chatsError;

        if (groups.isNotEmpty) onLoaded();

        if (err != null && groups.isEmpty) {
          return Column(children: [
            InlineErrorBanner(
              message: err,
              onRetry: provider.retryChats,
            ),
            const Expanded(child: SizedBox.shrink()),
          ]);
        }

        if (groups.isEmpty) {
          if (!initialLoadComplete) {
            return const _ChatListSkeleton();
          }
          return EmptyState(
            icon: Icons.group_outlined,
            title: 'No group chats yet',
            subtitle: 'Join a crew group to start chatting together.',
            actionLabel: 'Discover Groups',
            onAction: () => context.push('/groups-list'),
          );
        }

        return ListView.separated(
          itemCount: groups.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.backgroundGrey, indent: 76),
          itemBuilder: (context, i) => _ChatTile(chat: groups[i], currentUid: uid),
        );
      },
    );
  }
}

class _ChatListSkeleton extends StatelessWidget {
  const _ChatListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 6,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.backgroundGrey, indent: 76),
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Skeleton.circle(size: 48),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 140, height: 14),
                SizedBox(height: 8),
                Skeleton(width: 200, height: 10),
              ],
            ),
          ),
          SizedBox(width: 12),
          Skeleton(width: 60, height: 10),
        ]),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatModel chat;
  final String currentUid;
  const _ChatTile({required this.chat, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    final unread = chat.unreadCount[currentUid] ?? 0;
    final isGroup = chat.type == 'group';
    final name = isGroup ? (chat.groupName ?? 'Group') : _otherName(chat, currentUid);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(children: [
        CachedAvatar(
          url: isGroup ? chat.groupPhotoUrl : null,
          radius: 26,
          backgroundColor: isGroup ? AppColors.dark : AppColors.backgroundGrey,
          fallback: (isGroup && chat.groupPhotoUrl == null)
            ? const Icon(Icons.group, color: AppColors.primary)
            : null),
        Positioned(bottom: 0, right: 0,
          child: Container(width: 12, height: 12,
            decoration: BoxDecoration(
              color: AppColors.online, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2)))),
      ]),
      title: Text(name, style: AppTextStyles.labelMedium),
      subtitle: Text(chat.lastMessage ?? 'No messages yet',
        style: AppTextStyles.bodySmall.copyWith(
          color: unread > 0 ? AppColors.dark : AppColors.textSecondary,
          fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal),
        maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (chat.lastMessageAt != null)
          Text(timeago.format(chat.lastMessageAt!), style: AppTextStyles.caption),
        const SizedBox(height: 4),
        if (unread > 0)
          // WCAG 1.4.11: an unread badge is a UI component conveying state,
          // so it needs 3:1 against the white tile background. Primary on
          // white is 1.7:1 (fail). AppColors.badge is the standard red
          // (5.5:1) used by iOS / Android system unread indicators.
          Container(width: 20, height: 20,
            decoration: const BoxDecoration(color: AppColors.badge, shape: BoxShape.circle),
            child: Center(child: Text(unread > 9 ? '9+' : '$unread',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)))),
      ]),
      onTap: () => context.push('/conversation/${chat.id}?name=${Uri.encodeComponent(name)}&group=$isGroup'),
    );
  }

  String _otherName(ChatModel chat, String uid) {
    // Prefer a name embedded on the chat doc (set when the DM was created);
    // fall back to the group name or a generic "User". We no longer look
    // up against mockUsers — the chat doc should carry the participant name.
    final names = (chat as dynamic).participantNames;
    if (names is Map) {
      final otherUid = chat.participants.firstWhere((p) => p != uid, orElse: () => '');
      final name = names[otherUid];
      if (name is String && name.isNotEmpty) return name;
    }
    return chat.groupName ?? 'User';
  }
}
