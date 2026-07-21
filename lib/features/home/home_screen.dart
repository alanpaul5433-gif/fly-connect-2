import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/widgets/shared_widgets.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/inline_error_banner.dart';
import '../../shared/providers/post_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/providers/promotion_provider.dart';
import '../../shared/models/models.dart';
import 'post_details_screen.dart';
import 'edit_post_screen.dart';
import 'story_viewer_screen.dart';
import 'main_shell.dart' show AppDrawer;
import '../../shared/widgets/cached_image.dart';
import '../../shared/widgets/feed_video.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Distinguishes "feed is still loading" from "feed loaded but empty".
  // Without this, the home screen flashes "No posts yet" on every cold
  // start before Firestore returns — which feels broken.
  bool _initialLoadComplete = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PostProvider>().listenFeed();
    });
    // Fail-safe: after 4s assume the feed has loaded (or failed silently)
    // so we don't show skeletons forever.
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _initialLoadComplete = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: const AppTopBar(
        showMenuIcon: true,
        actions: [TopBarActions()],
      ),
      body: Column(children: [
        // Quick-access shortcut chips (navigate to sections, not filter)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(
                label: 'Feed',
                active: true,
                onTap: () => context.read<PostProvider>().listenFeed(),
              ),
              _FilterChip(label: 'Deals', active: false, onTap: () => context.push(AppRoutes.offers)),
              _FilterChip(label: 'Groups', active: false, onTap: () => context.push('/groups-list')),
              _FilterChip(label: 'Events', active: false, onTap: () => context.push('/events')),
              _FilterChip(label: 'Matches', active: false, onTap: () => context.push('/match')),
            ],
          ),
        ),
        // Stories row is pinned above the feed so "Your Story"/"Nearby" stay
        // reachable in every state — empty, loading, error, and populated.
        // (Previously it was item 0 of the feed list and vanished whenever the
        // feed had no posts.)
        _StoriesRow(),
        Expanded(
          child: Selector<PostProvider, (List<PostModel>, String?, bool, bool)>(
            // Rebuild only when the feed list identity or its status flags
            // change — not on every unrelated PostProvider notify (e.g. a
            // like/save toggle the card already handles optimistically).
            selector: (_, p) => (p.feed, p.feedError, p.feedHasMore, p.feedLoadingMore),
            builder: (context, _, __) {
              // Status flags + methods are read non-reactively; the Selector
              // above is what gates rebuilds.
              final provider = context.read<PostProvider>();
              final posts = provider.feed;
              final feedError = provider.feedError;
              // First real data arrived → mark load complete so future
              // refreshes don't flicker skeletons.
              if (posts.isNotEmpty && !_initialLoadComplete) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _initialLoadComplete = true);
                });
              }
              // Stream error + no cached posts → take over the screen with
              // the banner above the empty area. With cached posts present,
              // the banner sits above them so the user keeps reading what
              // we have while we retry.
              if (feedError != null && posts.isEmpty) {
                return Column(children: [
                  InlineErrorBanner(
                    message: feedError,
                    onRetry: provider.listenFeed,
                  ),
                  const Expanded(child: SizedBox.shrink()),
                ]);
              }
              if (posts.isEmpty) {
                // While we're waiting for the first feed snapshot, show
                // skeleton cards instead of an empty state — skeletons
                // tell the user "content is coming" instead of "this is
                // broken / there's nothing here".
                if (!_initialLoadComplete) {
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: const [
                      FeedPostSkeleton(),
                      Divider(color: AppColors.backgroundGrey, thickness: 6, height: 6),
                      FeedPostSkeleton(),
                      Divider(color: AppColors.backgroundGrey, thickness: 6, height: 6),
                      FeedPostSkeleton(),
                    ],
                  );
                }
                return const _EmptyFeed();
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => provider.listenFeed(),
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  // promos + posts + footer (stories are pinned outside the list)
                  itemCount: posts.length + 2,
                  separatorBuilder: (_, i) => i == 0
                      ? const Divider(color: AppColors.backgroundGrey, thickness: 6, height: 6)
                      : const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == 0) return const _PromoStrip();
                    if (i == posts.length + 1) {
                      // Footer: load-more or end-of-feed indicator
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 24, horizontal: 16),
                        child: Center(
                          child: provider.feedHasMore
                              ? SizedBox(
                                  height: 36,
                                  child: ElevatedButton.icon(
                                    onPressed: provider.feedLoadingMore
                                        ? null
                                        : () => provider.loadMoreFeed(),
                                    icon: provider.feedLoadingMore
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child:
                                                CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white),
                                          )
                                        : const Icon(Icons.expand_more,
                                            size: 16),
                                    label: Text(
                                        provider.feedLoadingMore
                                            ? 'Loading…'
                                            : 'Load more',
                                        style:
                                            const TextStyle(fontSize: 12)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.dark,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                    ),
                                  ),
                                )
                              : const Text(
                                  "You're all caught up.",
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                ),
                        ),
                      );
                    }
                    // H12: a stable key tied to post identity. Without it,
                    // Flutter reuses _PostCardState positionally, so when the
                    // feed prepends a new post the like/save state and counts —
                    // seeded once in initState — stay attached to the wrong row.
                    final post = posts[i - 1];
                    return _PostCard(key: ValueKey(post.id), post: post, index: i - 1);
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: active ? AppColors.dark : AppColors.backgroundGrey,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: Text(label, style: TextStyle(
            color: active ? Colors.white : AppColors.textSecondary,
            fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.article_outlined,
    title: 'No posts yet',
    subtitle: 'Be the first to share something with your crew!',
    actionLabel: 'Share a Post',
    onAction: () => context.push(AppRoutes.createPost),
  );
}

// ── Stories Row ──────────────────────────────────────────────
class _StoriesRow extends StatefulWidget {
  @override
  State<_StoriesRow> createState() => _StoriesRowState();
}

class _StoriesRowState extends State<_StoriesRow> {
  String? _myStoryUrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadMyStory();
  }

  Future<void> _loadMyStory() async {
    final uid = context.read<AuthProvider>().currentUser?.uid;
    if (uid == null) return;
    final url = await context.read<UserProvider>().getMyStory(uid);
    if (mounted) setState(() => _myStoryUrl = url);
  }

  Future<void> _pickMyStory() async {
    final userProvider = context.read<UserProvider>();
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _uploading = true);
    try {
      final url = await userProvider.postStory(bytes);
      if (mounted) setState(() { _myStoryUrl = url; _uploading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not post story: $e'),
        backgroundColor: Colors.red));
    }
  }

  void _viewMyStory() {
    if (_myStoryUrl == null) return;
    final currentUser = context.read<AuthProvider>().currentUser;
    if (currentUser == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => StoryViewerScreen(
        user: currentUser,
        storyImageUrl: _myStoryUrl!,
        isOwn: true,
      ),
    )).then((_) => _loadMyStory());
  }

  @override
  Widget build(BuildContext context) {
    // Only "Your Story" is shown until a backend-backed multi-user stories
    // feed ships. We intentionally no longer render fake stories for other
    // users — this one is real (Firestore + Storage backed), just mine-only.
    final hasStory = _myStoryUrl != null;
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: GestureDetector(
              onTap: _uploading ? null : (hasStory ? _viewMyStory : _pickMyStory),
              child: Column(children: [
                Stack(children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: hasStory ? Border.all(color: AppColors.primary, width: 2.5) : null,
                      color: AppColors.backgroundGrey,
                    ),
                    child: ClipOval(
                      child: _uploading
                          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                          : hasStory
                              ? CachedFeedImage(url: _myStoryUrl!, fit: BoxFit.cover)
                              : const Icon(Icons.person, color: AppColors.textSecondary, size: 28),
                    ),
                  ),
                  if (!hasStory)
                    // "Add story" affordance — UI control, needs 3:1 vs the
                    // grey/white surrounding background. Flip to dark.
                    Positioned(bottom: 0, right: 0,
                      child: Container(width: 20, height: 20,
                        decoration: BoxDecoration(color: AppColors.dark, shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5)),
                        child: const Icon(Icons.add, size: 12, color: AppColors.primary))),
                ]),
                const SizedBox(height: 4),
                const Text('Your Story', style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
          // Link to nearby users as a lightweight "discover" shortcut
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: GestureDetector(
              onTap: () => context.push(AppRoutes.nearby),
              child: Column(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2.5),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: CircleAvatar(
                      backgroundColor: AppColors.dark,
                      child: Icon(Icons.people_alt_outlined,
                          color: AppColors.primary, size: 22),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Nearby',
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Promo Strip (horizontal scroller of active deals) ───────
class _PromoStrip extends StatelessWidget {
  const _PromoStrip();

  @override
  Widget build(BuildContext context) {
    return Consumer<PromotionProvider>(
      builder: (context, provider, _) {
        final promos = provider.activePromotions.take(8).toList();
        if (promos.isEmpty) return const SizedBox.shrink();

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(children: [
                  const Icon(Icons.local_offer_rounded, size: 18, color: AppColors.dark),
                  const SizedBox(width: 6),
                  const Text('Crew Deals',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.offers),
                    child: const Text('See all',
                        style: TextStyle(
                            color: AppColors.dark,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ]),
              ),
              SizedBox(
                height: 168,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: promos.length,
                  itemBuilder: (_, i) => _PromoMiniCard(promo: promos[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PromoMiniCard extends StatelessWidget {
  final PromotionModel promo;
  const _PromoMiniCard({required this.promo});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/promotions/${promo.id}'),
      child: Container(
        width: 220,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.backgroundGrey,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            promo.imageUrl != null
                ? CachedFeedImage(
                    url: promo.imageUrl!,
                    height: 90,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: _placeholder(),
                  )
                : _placeholder(),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('-${promo.discountPercent}%',
                    style: const TextStyle(
                        color: AppColors.dark,
                        fontWeight: FontWeight.w800,
                        fontSize: 11)),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(promo.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(promo.businessName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: 90,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1D27), Color(0xFF2D3142)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.local_offer, size: 28, color: AppColors.primary),
      ),
    );
  }
}

// ── Post Card ────────────────────────────────────────────────
class _PostCard extends StatefulWidget {
  final PostModel post;
  final int index;
  const _PostCard({super.key, required this.post, required this.index});
  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  bool _liked = false;
  bool _saved = false;
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _checkLiked();
    _checkSaved();
  }

  @override
  void didUpdateWidget(_PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Safety net for H12: the ValueKey should keep each State bound to one
    // post, but if an element is ever reused for a DIFFERENT post, re-seed from
    // the new post rather than showing the previous one's like/save state.
    // Guarded on id change so it never fights the optimistic toggle for the
    // same post (a snapshot re-emit must not stomp an in-flight like).
    if (oldWidget.post.id != widget.post.id) {
      _likeCount = widget.post.likeCount;
      _liked = false;
      _saved = false;
      _checkLiked();
      _checkSaved();
    }
  }

  Future<void> _checkLiked() async {
    final liked = await context.read<PostProvider>().isLiked(widget.post.id);
    if (mounted) setState(() => _liked = liked);
  }

  Future<void> _checkSaved() async {
    final saved = await context.read<PostProvider>().isSaved(widget.post.id);
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _toggleSave() async {
    final provider = context.read<PostProvider>();
    final wasSaved = _saved;
    setState(() => _saved = !_saved);
    try {
      if (_saved) {
        await provider.savePost(widget.post.id);
      } else {
        await provider.unsavePost(widget.post.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saved = wasSaved);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save post. Please try again.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _toggleLike() async {
    final provider = context.read<PostProvider>();
    final wasLiked = _liked;
    setState(() { _liked = !_liked; _likeCount += _liked ? 1 : -1; });
    try {
      if (_liked) {
        await provider.likePost(widget.post.id, postAuthorId: widget.post.authorId);
      } else {
        await provider.unlikePost(widget.post.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likeCount += _liked ? 1 : -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not update like. Please try again.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _openPost() {
    Navigator.push(context,
      MaterialPageRoute(builder: (_) => PostDetailsScreen(post: widget.post)));
  }

  void _copyPostLink() {
    final link = 'https://flyconnect.co/posts/${widget.post.id}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Post link copied to clipboard'),
      duration: Duration(seconds: 2),
    ));
  }

  bool get _isOwnPost =>
      context.read<AuthProvider>().currentUser?.uid == widget.post.authorId;

  void _editPost() {
    Navigator.pop(context); // close the options sheet
    Navigator.push(context,
      MaterialPageRoute(builder: (_) => EditPostScreen(post: widget.post)));
  }

  void _showOptions() {
    final isOwn = _isOwnPost;
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: const Text('Share post'),
          onTap: () { Navigator.pop(context); _copyPostLink(); }),
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('Copy link'),
          onTap: () { Navigator.pop(context); _copyPostLink(); }),
        if (isOwn) ...[
          ListTile(leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit post'),
            onTap: _editPost),
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete post', style: TextStyle(color: Colors.red)),
            onTap: () { Navigator.pop(context); _confirmDeletePost(); }),
        ] else
          ListTile(leading: const Icon(Icons.flag_outlined, color: Colors.red),
            title: const Text('Report post', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await context.read<PostProvider>().reportPost(widget.post.id);
                messenger.showSnackBar(const SnackBar(
                  content: Text('Post reported. Our team will review it.'),
                  backgroundColor: Colors.red,
                ));
              } catch (e) {
                // Likely the rate-limit guard — surface to the user
                messenger.showSnackBar(SnackBar(
                  content: Text(e.toString().replaceFirst('Exception: ', '')),
                  backgroundColor: Colors.orange,
                ));
              }
            }),
      ])));
  }

  Future<void> _confirmDeletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ));
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PostProvider>().deletePost(widget.post.id,
        mediaUrls: widget.post.mediaUrls, thumbnailUrl: widget.post.thumbnailUrl);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Could not delete post. Please try again.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          GestureDetector(
            onTap: () => context.push('/users/${p.authorId}'),
            child: CachedAvatar(
              url: p.authorPhotoUrl,
              radius: 20,
              backgroundColor: AppColors.backgroundGrey,
              fallback: Text(p.authorName.isNotEmpty ? p.authorName[0] : '?', style: const TextStyle(color: AppColors.dark)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(onTap: () => context.push('/users/${p.authorId}'),
              child: Text(p.authorName, style: AppTextStyles.labelMedium)),
            Text(
              '${timeago.format(p.createdAt)}${p.editedAt != null ? ' · edited' : ''}',
              style: AppTextStyles.caption,
            ),
          ])),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
            tooltip: 'More options',
            onPressed: _showOptions,
          ),
        ])),
      // Image / gradient fallback
      GestureDetector(
        onDoubleTap: _toggleLike,
        onTap: _openPost,
        child: (p.mediaType == 'video' && p.mediaUrls.isNotEmpty)
            ? RepaintBoundary(
                child: FeedVideo(
                  videoUrl: p.mediaUrls.first,
                  thumbnailUrl: p.thumbnailUrl,
                  aspectRatio: p.aspectRatio,
                  height: 280,
                  width: double.infinity,
                ),
              )
            : p.mediaUrls.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.zero,
                child: RepaintBoundary(
                  child: CachedFeedImage(
                    url: p.mediaUrls.first,
                    height: 280,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: Container(height: 280, color: AppColors.backgroundGrey,
                        child: const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))),
                    errorWidget: Container(height: 280, color: AppColors.backgroundGrey,
                        child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textSecondary)),
                  ),
                ))
            : Container(
                height: 180,
                width: double.infinity, // fill the row; otherwise the tint
                // shrink-wraps to the caption text and looks half-width.
                // Text-only posts share one subtle, on-brand navy tint instead
                // of a random Material colour per index (which read as broken).
                color: AppColors.dark.withValues(alpha: 0.05),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(p.authorName, style: AppTextStyles.labelMedium),
                    const SizedBox(height: 8),
                    Text(
                      p.caption.length > 100 ? p.caption.substring(0, 100) : p.caption,
                      style: AppTextStyles.bodyMedium,
                    ),
                  ],
                ),
              ),
      ),
      // Actions
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: Row(children: [
        GestureDetector(onTap: _toggleLike, child: Row(children: [
          AnimatedSwitcher(duration: const Duration(milliseconds: 200),
            child: Icon(_liked ? Icons.favorite : Icons.favorite_border,
              key: ValueKey(_liked), size: 24,
              color: _liked ? Colors.red : AppColors.textPrimary)),
          const SizedBox(width: 4),
          Text('$_likeCount', style: AppTextStyles.bodySmall),
        ])),
        const SizedBox(width: 16),
        GestureDetector(onTap: _openPost, child: Row(children: [
          const Icon(Icons.chat_bubble_outline, size: 22, color: AppColors.textPrimary),
          const SizedBox(width: 4),
          Text('${p.commentCount}', style: AppTextStyles.bodySmall),
        ])),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.share_outlined, size: 22, color: AppColors.textPrimary),
          tooltip: 'Share post',
          onPressed: _copyPostLink,
        ),
        IconButton(
          icon: Icon(
            _saved ? Icons.bookmark : Icons.bookmark_border,
            size: 22,
            color: _saved ? AppColors.primary : AppColors.textPrimary,
          ),
          tooltip: _saved ? 'Remove from saved' : 'Save post',
          onPressed: _toggleSave,
        ),
      ])),
      // Caption
      if (p.caption.isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: RichText(text: TextSpan(style: AppTextStyles.bodyMedium, children: [
            TextSpan(text: '${p.authorName} ', style: AppTextStyles.labelMedium),
            TextSpan(text: p.caption.length > 120 ? '${p.caption.substring(0, 120)}... ' : p.caption),
            if (p.caption.length > 120) TextSpan(text: 'more',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          ]))),
      if (p.commentCount > 0)
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: GestureDetector(onTap: _openPost,
            child: Text('View all ${p.commentCount} comments',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)))),
    ]);
  }
}
