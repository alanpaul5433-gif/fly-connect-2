import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_colors.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/group_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/post_provider.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/widgets/cached_image.dart';

class GroupDetailsScreen extends StatefulWidget {
  final String groupId;
  const GroupDetailsScreen({super.key, required this.groupId});
  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  GroupModel? _group;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    final g = await context.read<GroupProvider>().getGroup(widget.groupId);
    if (mounted) setState(() { _group = g; _loading = false; });
  }

  void _openGroupChat() {
    final g = _group!;
    final chatId = g.chatId ?? g.id;
    context.push('/conversation/$chatId?name=${Uri.encodeComponent(g.name)}&group=true');
  }

  void _showReportSheet() {
    const reasons = [
      'Spam or misleading',
      'Harassment or bullying',
      'Hate speech',
      'Sexual or explicit content',
      'Illegal activity',
      'Other',
    ];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Why are you reporting this group?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          ...reasons.map((r) => ListTile(
                title: Text(r),
                onTap: () async {
                  Navigator.pop(context);
                  await context.read<PostProvider>().reportContent(
                        targetType: 'group',
                        targetId: widget.groupId,
                        reason: r,
                      );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Report submitted. Our team will review it.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                    ));
                  }
                },
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showGroupMenu() {
    final g = _group!;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share group'),
            onTap: () {
              Navigator.pop(context);
              final link = 'https://flyconnect.co/groups/${g.id}';
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Group link copied to clipboard'),
                duration: Duration(seconds: 2),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Copy link'),
            onTap: () {
              Navigator.pop(context);
              final link = 'https://flyconnect.co/groups/${g.id}';
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Group link copied to clipboard'),
                duration: Duration(seconds: 2),
              ));
            },
          ),
          // Mute group hidden for v1.0 — not yet implemented.
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: Colors.red),
            title:
                const Text('Report group', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _showReportSheet();
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    if (_group == null) {
      return Scaffold(
      appBar: AppBar(leading: const BackButton(), backgroundColor: Colors.white),
      body: const Center(child: Text('Group not found')));
    }

    final g = _group!;
    final isMember = context.watch<GroupProvider>().isMember(g.id);
    final groupPosts = context.watch<PostProvider>().feed.where((p) => p.groupId == widget.groupId).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 200, pinned: true,
            backgroundColor: AppColors.dark,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
              tooltip: 'Back',
              onPressed: () => GoRouter.of(context).pop()),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                tooltip: 'Group options',
                onPressed: _showGroupMenu,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                g.imageUrl != null
                  ? CachedFeedImage(url: g.imageUrl!, fit: BoxFit.cover,
                      errorWidget: Container(color: AppColors.dark))
                  : Container(color: AppColors.dark,
                      child: const Center(child: Icon(Icons.group, color: AppColors.primary, size: 72))),
                Container(decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)]))),
                Positioned(bottom: 20, left: 20, right: 20, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (g.isPinned) Container(margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                    child: const Text('FEATURED', style: TextStyle(color: AppColors.dark, fontSize: 10, fontWeight: FontWeight.w800))),
                  Text(g.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  Text('${g.memberCount} members', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ])),
              ]),
            ),
          ),
        ],
        body: Column(children: [
          // Join / Leave + Chat buttons
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Row(children: [
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isMember ? Colors.white : AppColors.primary,
                foregroundColor: isMember ? AppColors.textPrimary : AppColors.dark,
                side: isMember ? const BorderSide(color: AppColors.inputBorder) : null,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () async {
                final gp = context.read<GroupProvider>();
                final messenger = ScaffoldMessenger.of(context);
                if (isMember) {
                  final confirmed = await showConfirmDialog(
                    context,
                    title: 'Leave "${g.name}"?',
                    message:
                        "You'll stop receiving updates from this group. You can rejoin anytime.",
                    confirmLabel: 'Leave',
                    isDestructive: true,
                  );
                  if (!confirmed) return;
                  try {
                    await gp.leaveGroup(g.id);
                  } catch (_) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Could not leave group. Please try again.'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                } else {
                  try {
                    await gp.joinGroup(g.id);
                  } catch (_) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Could not join group. Please try again.'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                }
              },
              child: Text(isMember ? 'Leave Group' : 'Join Group',
                style: const TextStyle(fontWeight: FontWeight.bold)))),
            if (isMember) ...[
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Group Chat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dark,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: _openGroupChat,
              )),
            ],
          ])),
          // About + tags
          Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.description, style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5)),
            if (g.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: g.tags.map((t) =>
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.backgroundGrey, borderRadius: BorderRadius.circular(100)),
                  child: Text('#$t', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)))).toList()),
            ],
          ])),
          // Tab bar
          TabBar(controller: _tabs,
            labelColor: AppColors.dark, unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary, indicatorWeight: 3,
            tabs: [
              Tab(text: 'Posts (${groupPosts.length})'),
              const Tab(text: 'Members'),
            ]),
          Expanded(child: TabBarView(controller: _tabs, children: [
            _PostsTab(posts: groupPosts),
            _MembersTab(groupId: g.id, members: g.members, admins: g.admins),
          ])),
        ]),
      ),
    );
  }
}

class _PostsTab extends StatelessWidget {
  final List<PostModel> posts;
  const _PostsTab({required this.posts});
  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const EmptyState(
      icon: Icons.article_outlined,
      title: 'No posts yet',
      subtitle: 'Be the first to post in this group.',
    );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: posts.length,
      itemBuilder: (_, i) => _PostCard(post: posts[i]),
    );
  }
}

class _PostCard extends StatelessWidget {
  final PostModel post;
  const _PostCard({required this.post});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.dark,
            backgroundImage: post.authorPhotoUrl != null ? NetworkImage(post.authorPhotoUrl!) : null,
            child: post.authorPhotoUrl == null
              ? Text(post.authorName.isNotEmpty ? post.authorName[0] : '?',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))
              : null,
          ),
          title: Text(post.authorName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(timeago.format(post.createdAt), style: const TextStyle(fontSize: 11)),
          trailing: post.location != null
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 2),
                Text(post.location!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ])
            : null,
        ),
        if (post.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(post.caption, style: const TextStyle(fontSize: 14, height: 1.4)),
          ),
        if (post.mediaUrls.isNotEmpty)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            child: CachedFeedImage(url: post.mediaUrls.first, width: double.infinity, height: 180, fit: BoxFit.cover,
              errorWidget: const SizedBox()),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            const Icon(Icons.favorite_border, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('${post.likeCount}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(width: 16),
            const Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('${post.commentCount}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ]),
        ),
      ]),
    );
  }
}

class _MembersTab extends StatefulWidget {
  final String groupId;
  final List<String> members;
  final List<String> admins;
  const _MembersTab({required this.groupId, required this.members, required this.admins});
  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  late List<String> _members;

  @override
  void initState() {
    super.initState();
    _members = List.from(widget.members);
  }

  bool get _isAdmin {
    final uid = context.read<AuthProvider>().currentUser?.uid;
    return uid != null && widget.admins.contains(uid);
  }

  void _removeMember(String uid) {
    final groupProvider = context.read<GroupProvider>();
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Member'),
        content: const Text('Remove this member from the group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _members.remove(uid));
              try {
                await groupProvider.removeMember(widget.groupId, uid);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Member removed'), duration: Duration(seconds: 2)));
              } catch (_) {
                if (mounted) setState(() => _members.add(uid));
                messenger.showSnackBar(
                  const SnackBar(content: Text('Could not remove member. Try again.')));
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_members.isEmpty) {
      return const EmptyState(
      icon: Icons.people_outline,
      title: 'No members yet',
      subtitle: 'Invite others to join this group.',
    );
    }
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: AppColors.backgroundGrey,
        child: Row(children: [
          const Icon(Icons.people_outline, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text('${_members.length} member${_members.length == 1 ? '' : 's'}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary)),
        ]),
      ),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _members.length,
        itemBuilder: (_, i) {
          final uid = _members[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: CircleAvatar(backgroundColor: AppColors.dark,
              child: Text(uid.isNotEmpty ? uid[0].toUpperCase() : '?',
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
            title: Text('Member ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(uid, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            onTap: () => context.push('/users/$uid'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.primary),
                tooltip: 'Message member',
                onPressed: () => context.push('/conversation/${uid}_dm?name=Member+${i + 1}'),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
              if (_isAdmin) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.remove_circle_outline, size: 18, color: Colors.red.shade300),
                  tooltip: 'Remove member',
                  onPressed: () => _removeMember(uid),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
              ],
            ]),
          );
        },
      )),
    ]);
  }
}
