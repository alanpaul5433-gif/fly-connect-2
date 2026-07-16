import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/providers/post_provider.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/utils/open_chat.dart';
import '../../shared/models/models.dart';
import '../home/story_viewer_screen.dart';
import '../home/post_details_screen.dart';
import '../../shared/widgets/cached_image.dart';

class ProfileScreen extends StatefulWidget {
  final bool isOwner;
  final String? userId;
  const ProfileScreen({super.key, this.isOwner = false, this.userId});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  UserModel? _user;
  bool _loading = true;
  bool _following = false;
  // If either party has blocked the other, hide the whole profile.
  // Mirrors the Nearby map's both-direction block filter.
  bool _blockedRelationship = false;
  String? _myStoryUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUser();
  }

  Future<void> _loadUser() async {
    final auth = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();

    if (widget.isOwner || widget.userId == null) {
      _user = userProvider.currentUser ??
          (auth.currentUser == null ? null :
          await userProvider.fetchUser(auth.currentUser!.uid));
      if (_user != null) _myStoryUrl = await userProvider.getMyStory(_user!.uid);
    } else {
      _user = await userProvider.fetchUser(widget.userId!);
      if (_user != null && auth.currentUser != null) {
        _following = await userProvider.isFollowing(_user!.uid);
        _blockedRelationship = await _checkBlockedRelationship(
            myUid: auth.currentUser!.uid, otherUid: _user!.uid);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Returns true if EITHER party has blocked the other.
  /// We don't surface the other user's profile in that case.
  Future<bool> _checkBlockedRelationship({
    required String myUid,
    required String otherUid,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      // 1. I blocked them?
      final mineSnap = await db
          .collection('users').doc(myUid)
          .collection('blocked').doc(otherUid)
          .get();
      if (mineSnap.exists) return true;
      // 2. They blocked me?
      final theirsSnap = await db
          .collection('users').doc(otherUid)
          .collection('blocked').doc(myUid)
          .get();
      if (theirsSnap.exists) return true;
    } catch (_) {/* fail open — better to show than to incorrectly hide */}
    return false;
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  Future<void> _toggleFollow() async {
    final userProvider = context.read<UserProvider>();
    final wasFollowing = _following;
    setState(() => _following = !_following);
    try {
      if (wasFollowing) {
        await userProvider.unfollowUser(_user!.uid);
      } else {
        await userProvider.followUser(_user!.uid);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _following = wasFollowing);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _openChat() async {
    if (_user == null) return;
    await OpenChat.withUser(
      context,
      otherUid: _user!.uid,
      otherName: _user!.name,
      otherPhotoUrl: _user!.photoUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    if (_user == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton(), backgroundColor: Colors.white),
      body: const Center(child: Text('User not found')));
    }
    if (_blockedRelationship) {
      return Scaffold(
        appBar: AppBar(
          leading: const BackButton(color: Colors.black),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.block,
                      size: 28, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                const Text('Profile unavailable',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text(
                  'You cannot view this profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isMe = widget.isOwner || widget.userId == null;
    // Respect "Public Profile" — a private account is only visible to itself
    // and accounts it has accepted a follow from.
    if (!isMe && !_following && _user!.settings['profilePublic'] == false) {
      return Scaffold(
        appBar: AppBar(
          leading: const BackButton(color: Colors.black),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline,
                      size: 28, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                const Text('This profile is private',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text(
                  'Follow this account to see their posts and info.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final u = _user!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.dark,
            leading: Navigator.canPop(context) ? IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
              tooltip: 'Back',
              onPressed: () => GoRouter.of(context).pop(),
            ) : null,
            actions: [
              if (isMe) IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                tooltip: 'Notifications',
                onPressed: () => context.push(AppRoutes.notifications)),
              IconButton(
                icon: const Icon(Icons.more_horiz, color: Colors.white),
                tooltip: 'Profile options',
                onPressed: () => _showOptions(context, isMe)),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                u.photoUrl != null
                  ? CachedFeedImage(url: u.photoUrl!, fit: BoxFit.cover,
                      errorWidget: Container(color: AppColors.dark))
                  : Container(color: AppColors.dark,
                      child: Center(child: Text(u.name.isNotEmpty ? u.name[0] : '?',
                        style: const TextStyle(color: AppColors.primary, fontSize: 72, fontWeight: FontWeight.bold)))),
                Container(decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.2), Colors.black.withValues(alpha: 0.5)]))),
              ]),
            ),
          ),
        ],
        body: SingleChildScrollView(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Avatar + actions row
            Row(children: [
              GestureDetector(
                onTap: () {
                  if (isMe && _myStoryUrl != null) {
                    final userProvider = context.read<UserProvider>();
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => StoryViewerScreen(
                          user: u, storyImageUrl: _myStoryUrl!, isOwn: true),
                    )).then((_) async {
                      final url = await userProvider.getMyStory(u.uid);
                      if (mounted) setState(() => _myStoryUrl = url);
                    });
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isMe && _myStoryUrl != null
                          ? const Color(0xFFD4F53C)
                          : AppColors.primary,
                      width: 3,
                    ),
                  ),
                  child: CircleAvatar(radius: 40,
                    backgroundColor: AppColors.dark,
                    backgroundImage: u.photoUrl != null ? NetworkImage(u.photoUrl!) : null,
                    child: u.photoUrl == null ? Text(u.name.isNotEmpty ? u.name[0] : '?',
                      style: const TextStyle(color: AppColors.primary, fontSize: 32, fontWeight: FontWeight.bold)) : null),
                ),
              ),
              const Spacer(),
              if (isMe) ...[
                _ActionIcon(icon: Icons.settings_outlined, onTap: () => context.push(AppRoutes.settings)),
                const SizedBox(width: 10),
                _PillBtn(label: 'Edit Profile', filled: true,
                  // Opens the core profile editor (avatar / name / bio / airline).
                  // The "looking for & interests" screen (editProfileDetails) is
                  // still reachable via Settings → Edit Profile.
                  // Reload on return so edits (e.g. a new avatar) show right away
                  // instead of only after the next cold start.
                  onTap: () async {
                    await context.push(AppRoutes.editProfile);
                    if (mounted) await _loadUser();
                  }),
              ] else ...[
                _ActionIcon(icon: Icons.chat_bubble_outline, onTap: _openChat),
                const SizedBox(width: 10),
                _PillBtn(label: _following ? 'Following' : 'Follow', filled: !_following,
                  onTap: _toggleFollow),
              ],
            ]),
            const SizedBox(height: 12),
            // Name, airline, position
            Text(u.name, style: AppTextStyles.h4),
            if (u.airline != null || u.position != null)
              Text('${u.airline ?? ''} ${u.position != null ? '· ${u.position}' : ''}',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary)),
            if (u.airport != null)
              Row(children: [
                const Icon(Icons.flight, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(u.airport!, style: AppTextStyles.caption),
              ]),
            if (u.bio != null && u.bio!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(u.bio!, style: AppTextStyles.bodyMedium),
            ],
            if (u.hobbies.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: u.hobbies.map((h) =>
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.backgroundGrey,
                    borderRadius: BorderRadius.circular(100)),
                  child: Text(h, style: AppTextStyles.caption))).toList()),
            ],
            const SizedBox(height: 16),
            // Passport stamps strip
            if (u.passportStamps.isNotEmpty) GestureDetector(
              onTap: () => context.push('/passport/${u.uid}'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.book, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text('${u.passportStamps.length} countries visited',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.primary, size: 18),
                ]))),
            const SizedBox(height: 16),
            // Stats row
            Row(children: [
              Expanded(child: _StatItem(value: _fmt(u.postCount), label: 'Posts')),
              _Divider(),
              Expanded(child: GestureDetector(
                onTap: _showFollowers,
                child: _StatItem(value: _fmt(u.followerCount), label: 'Followers'))),
              _Divider(),
              Expanded(child: _StatItem(value: _fmt(u.followingCount), label: 'Following')),
              _Divider(),
              Expanded(child: _StatItem(value: u.passportStamps.length.toString(), label: 'Countries')),
            ]),
          ])),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.inputBorder),
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.dark,
            indicatorWeight: 2,
            labelColor: AppColors.dark,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: const [
              Tab(icon: Icon(Icons.grid_view_rounded, size: 22)),
              Tab(icon: Icon(Icons.favorite_border, size: 22)),
              Tab(icon: Icon(Icons.flight_takeoff_outlined, size: 22)),
            ],
          ),
          const Divider(height: 1, color: AppColors.inputBorder),
          SizedBox(height: 400, child: TabBarView(controller: _tabController, children: [
            _PostsGrid(userId: u.uid),
            const _LikedPostsGrid(),
            _TripsTab(stamps: u.passportStamps),
          ])),
        ])),
      ),
    );
  }

  void _showFollowers() {
    final targetUid = _user?.uid ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, sc) => Column(children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('Followers', style: AppTextStyles.labelLarge),
          const Divider(),
          Expanded(child: FutureBuilder<List<UserModel>>(
            future: _fetchFollowers(targetUid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              }
              final followers = snap.data ?? [];
              if (followers.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No followers yet', style: TextStyle(color: Colors.grey)),
                  ),
                );
              }
              return ListView.builder(
                controller: sc,
                itemCount: followers.length,
                itemBuilder: (_, i) {
                  final u = followers[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.dark,
                      backgroundImage: u.photoUrl != null ? NetworkImage(u.photoUrl!) : null,
                      child: u.photoUrl == null ? Text(u.name.isNotEmpty ? u.name[0] : '?',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)) : null,
                    ),
                    title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${u.airline ?? ''} · ${u.position ?? ''}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    onTap: () { Navigator.pop(sheetCtx); context.push('/users/${u.uid}'); },
                  );
                },
              );
            },
          )),
        ]),
      ),
    );
  }

  Future<List<UserModel>> _fetchFollowers(String uid) async {
    if (uid.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('followers')
          .limit(50)
          .get();
      if (snap.docs.isEmpty) return [];
      final futures = snap.docs.map((d) =>
          FirebaseFirestore.instance.collection('users').doc(d.id).get());
      final userDocs = await Future.wait(futures);
      return userDocs
          .where((d) => d.exists)
          .map((d) => UserModel.fromFirestore(d))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _showOptions(BuildContext context, bool isMe) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isMe) ...[
          ListTile(leading: const Icon(Icons.share_outlined), title: const Text('Share profile'), onTap: () { Navigator.pop(context); _shareProfile(); }),
          ListTile(leading: const Icon(Icons.qr_code), title: const Text('My QR code'), onTap: () { Navigator.pop(context); _showMyQr(); }),
          ListTile(leading: const Icon(Icons.bookmark_border), title: const Text('Saved posts'), onTap: () { Navigator.pop(context); context.push(AppRoutes.savedPosts); }),
          ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Privacy settings'), onTap: () { Navigator.pop(context); context.push(AppRoutes.settings); }),
        ] else ...[
          ListTile(leading: const Icon(Icons.share_outlined), title: const Text('Share profile'), onTap: () { Navigator.pop(context); _shareProfile(); }),
          ListTile(leading: const Icon(Icons.block, color: Colors.red), title: const Text('Block user', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); _confirmBlockUser(); }),
          ListTile(leading: const Icon(Icons.flag_outlined, color: Colors.red), title: const Text('Report user', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); _reportUser(); }),
        ],
      ])));
  }

  /// Canonical shareable profile URL. Matches the in-app `/users/:userId` route
  /// (app_router.dart) and the link shape used for promotions. Deep linking is
  /// deferred for v1.0, so this opens on the web — it does not reopen the app yet.
  String _profileUrl(UserModel u) => 'https://flyconnect.co/users/${u.uid}';

  /// Share the viewed profile via the native OS share sheet. `_user` holds the
  /// correct profile for both the own-profile and other-profile cases.
  Future<void> _shareProfile() async {
    final u = _user;
    if (u == null) return;
    final url = _profileUrl(u);
    try {
      await SharePlus.instance.share(
        ShareParams(text: '${u.name} on FlyConnect\n$url', subject: '${u.name} on FlyConnect'),
      );
    } catch (_) {
      // Fallback if the native share sheet is unavailable (e.g. web/desktop):
      // copy the link, mirroring the promotions share pattern.
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile link copied to clipboard')),
      );
    }
  }

  /// Show a scannable QR code of the profile URL (own-profile only). Rendered on
  /// a white card so the default black QR modules stay readable on the dark sheet.
  void _showMyQr() {
    final u = _user;
    if (u == null) return;
    final url = _profileUrl(u);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(u.name, style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            const Text('Scan to view profile', style: AppTextStyles.caption, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: url, version: QrVersions.auto, size: 220, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              FilledButton.icon(
                onPressed: () { Navigator.pop(ctx); _shareProfile(); },
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Share'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  /// Block the viewed user. The provider write (PostProvider.blockUser) already
  /// exists and the profile both-direction filter already hides blocked users —
  /// this just wires the button to it, behind a confirm, then leaves the screen.
  Future<void> _confirmBlockUser() async {
    final target = _user;
    if (target == null) return;
    final post = context.read<PostProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block ${target.name}?'),
        content: const Text(
          "They won't be able to message you or see your profile, and they "
          "won't appear in your chats, matches, or nearby. You can unblock "
          "later from Settings.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await post.blockUser(target.uid);
      if (!mounted) return;
      setState(() => _blockedRelationship = true);
      messenger.showSnackBar(
        SnackBar(content: Text('${target.name} has been blocked')));
      if (router.canPop()) router.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Could not block user: $e'),
        backgroundColor: Colors.red));
    }
  }

  /// Report the viewed user to moderation (Apple 1.2 / Play UGC). Persists a
  /// `reports` doc via PostProvider.reportContent with the chosen reason.
  Future<void> _reportUser() async {
    final target = _user;
    if (target == null) return;
    final reason = await _pickReportReason();
    if (reason == null || !mounted) return;
    final post = context.read<PostProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await post.reportContent(
        targetType: 'user', targetId: target.uid, reason: reason);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Thanks — our team will review this report.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Could not submit report: $e'),
        backgroundColor: Colors.red));
    }
  }

  /// Canonical report reasons. Returns the chosen reason, or null if dismissed.
  Future<String?> _pickReportReason() {
    const reasons = [
      'Spam or scam',
      'Harassment or bullying',
      'Inappropriate or explicit content',
      'Fake or impersonating profile',
      'Other',
    ];
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Report this profile',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          for (final r in reasons)
            ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r)),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _ActionIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(width: 44, height: 44,
      decoration: const BoxDecoration(color: AppColors.backgroundGrey, shape: BoxShape.circle),
      child: Icon(icon, size: 20)));
}

class _PillBtn extends StatelessWidget {
  final String label; final bool filled; final VoidCallback onTap;
  const _PillBtn({required this.label, required this.filled, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: filled ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(100),
        border: filled ? null : Border.all(color: AppColors.inputBorder)),
      child: Center(child: Text(label, style: AppTextStyles.labelMedium.copyWith(
        color: filled ? AppColors.dark : AppColors.textPrimary)))));
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

class _Divider extends StatelessWidget {
  @override Widget build(BuildContext context) =>
    Container(width: 1, height: 28, color: AppColors.inputBorder);
}

class _LikedPostsGrid extends StatelessWidget {
  const _LikedPostsGrid();
  @override
  Widget build(BuildContext context) {
    return Consumer<PostProvider>(
      builder: (context, provider, _) {
        // Only posts the user has liked — not the whole feed.
        final posts = provider.feed
            .where((p) => provider.likedPostIds.contains(p.id))
            .toList();
        if (posts.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.favorite_border, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          const Text('No liked posts', style: TextStyle(color: Colors.grey)),
        ]));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
          itemCount: posts.length,
          itemBuilder: (context, i) {
            final post = posts[i];
            return post.mediaUrls.isNotEmpty
              ? CachedFeedImage(url: post.mediaUrls.first, fit: BoxFit.cover,
                  errorWidget: Container(color: AppColors.backgroundGrey))
              : Container(color: AppColors.backgroundGrey,
                  child: Center(child: Text(post.caption.isNotEmpty ? post.caption[0] : '❤️',
                    style: const TextStyle(fontSize: 24))));
          },
        );
      },
    );
  }
}

class _PostsGrid extends StatelessWidget {
  final String userId;
  const _PostsGrid({required this.userId});
  @override
  Widget build(BuildContext context) {
    return Consumer<PostProvider>(
      builder: (context, provider, _) {
        // Only this profile's own posts — not the global feed.
        final posts = provider.feed.where((p) => p.authorId == userId).toList();
        if (posts.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.grid_view_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          const Text('No posts yet', style: TextStyle(color: Colors.grey)),
        ]));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(2),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
          itemCount: posts.length,
          itemBuilder: (context, i) {
            final post = posts[i];
            return GestureDetector(
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => PostDetailsScreen(post: post))),
              child: post.mediaUrls.isNotEmpty
                ? CachedFeedImage(url: post.mediaUrls.first, fit: BoxFit.cover,
                    errorWidget: Container(color: AppColors.backgroundGrey))
                : Container(color: AppColors.backgroundGrey,
                    child: Center(child: Text(post.caption.isNotEmpty ? post.caption[0] : '📝',
                      style: const TextStyle(fontSize: 24)))));
          },
        );
      },
    );
  }
}

class _TripsTab extends StatelessWidget {
  final List<String> stamps;
  const _TripsTab({required this.stamps});

  static const List<Map<String, String>> _flags = [
    {'US': '🇺🇸'}, {'GB': '🇬🇧'}, {'JP': '🇯🇵'}, {'FR': '🇫🇷'}, {'DE': '🇩🇪'},
    {'AU': '🇦🇺'}, {'CA': '🇨🇦'}, {'IT': '🇮🇹'}, {'ES': '🇪🇸'}, {'TH': '🇹🇭'},
    {'AE': '🇦🇪'}, {'SG': '🇸🇬'}, {'MX': '🇲🇽'}, {'BR': '🇧🇷'}, {'IN': '🇮🇳'},
  ];

  String _flagFor(String code) {
    for (final m in _flags) { if (m.containsKey(code)) return m[code]!; }
    return '✈️';
  }

  @override
  Widget build(BuildContext context) {
    if (stamps.isEmpty) return const Center(child: Text('No trips yet', style: TextStyle(color: Colors.grey)));
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: stamps.length,
      itemBuilder: (_, i) => Container(
        decoration: BoxDecoration(color: AppColors.backgroundGrey, borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_flagFor(stamps[i]), style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 4),
          Text(stamps[i], style: AppTextStyles.caption),
        ])));
  }
}
