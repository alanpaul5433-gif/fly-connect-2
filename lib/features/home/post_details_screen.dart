import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_colors.dart';
import '../../shared/providers/post_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/cached_image.dart';

class PostDetailsScreen extends StatefulWidget {
  final PostModel post;
  const PostDetailsScreen({super.key, required this.post});
  @override State<PostDetailsScreen> createState() => _PostDetailsScreenState();
}

class _PostDetailsScreenState extends State<PostDetailsScreen> {
  final TextEditingController _ctrl = TextEditingController();
  bool _isLiked = false;
  bool _isSaved = false;
  int _likeCount = 0;

  void _sharePost() {
    final link = 'https://flyconnect.app/posts/${widget.post.id}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Post link copied to clipboard'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _toggleSave() async {
    final provider = context.read<PostProvider>();
    setState(() => _isSaved = !_isSaved);
    if (_isSaved) {
      await provider.savePost(widget.post.id);
    } else {
      await provider.unsavePost(widget.post.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_isSaved ? 'Post saved' : 'Removed from saved'),
      duration: const Duration(seconds: 1),
    ));
  }

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _checkLike();
    _checkSaved();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _checkLike() async {
    final liked = await context.read<PostProvider>().isLiked(widget.post.id);
    if (mounted) setState(() => _isLiked = liked);
  }

  Future<void> _checkSaved() async {
    final saved = await context.read<PostProvider>().isSaved(widget.post.id);
    if (mounted) setState(() => _isSaved = saved);
  }

  Future<void> _toggleLike() async {
    final provider = context.read<PostProvider>();
    setState(() { _isLiked = !_isLiked; _likeCount += _isLiked ? 1 : -1; });
    if (_isLiked) { await provider.likePost(widget.post.id); }
    else { await provider.unlikePost(widget.post.id); }
  }

  Future<void> _comment() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    await context.read<PostProvider>().addComment(widget.post.id, text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0.5,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
        title: const Text('Post', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () => _showOptions(context)),
        ],
      ),
      body: Column(children: [
        Expanded(child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(
              leading: CachedAvatar(
                url: widget.post.authorPhotoUrl,
                radius: 20,
                backgroundColor: AppColors.dark,
                fallback: Text(widget.post.authorName.isNotEmpty ? widget.post.authorName[0] : '?', style: const TextStyle(color: Colors.white)),
              ),
              title: Text(widget.post.authorName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(timeago.format(widget.post.createdAt)),
            ),
            if (widget.post.mediaUrls.isNotEmpty)
              CachedFeedImage(
                url: widget.post.mediaUrls.first,
                width: double.infinity,
                height: 300,
                fit: BoxFit.cover,
                placeholder: Container(
                    height: 300,
                    color: AppColors.backgroundGrey,
                    child: const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2))),
                errorWidget: Container(
                    height: 300,
                    color: AppColors.backgroundGrey,
                    child: const Icon(Icons.image_not_supported_outlined,
                        color: AppColors.textSecondary, size: 48)),
              ),
            Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(onTap: _toggleLike, child: Row(children: [
                  Icon(_isLiked ? Icons.favorite : Icons.favorite_border,
                    color: _isLiked ? Colors.red : Colors.grey, size: 26),
                  const SizedBox(width: 4),
                  Text('$_likeCount', style: const TextStyle(fontSize: 14)),
                ])),
                const SizedBox(width: 20),
                const Icon(Icons.chat_bubble_outline, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${widget.post.commentCount}', style: const TextStyle(fontSize: 14)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.share_outlined, color: Colors.grey), onPressed: _sharePost),
                IconButton(
                  icon: Icon(_isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: _isSaved ? AppColors.primary : Colors.grey),
                  onPressed: _toggleSave,
                ),
              ]),
              const SizedBox(height: 8),
              RichText(text: TextSpan(style: const TextStyle(color: Colors.black, fontSize: 14), children: [
                TextSpan(text: '${widget.post.authorName} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: widget.post.caption),
              ])),
            ])),
            const Divider(),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Comments', style: TextStyle(fontWeight: FontWeight.bold))),
          ])),
          StreamBuilder<List<CommentModel>>(
            stream: context.read<PostProvider>().watchComments(widget.post.id),
            builder: (context, snap) {
              final comments = snap.data ?? [];
              return SliverList(delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final c = comments[i];
                  return ListTile(
                    leading: CachedAvatar(
                      url: c.authorPhotoUrl,
                      radius: 16,
                      backgroundColor: AppColors.dark,
                      fallback: Text(c.authorName.isNotEmpty ? c.authorName[0] : '?', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                    title: RichText(text: TextSpan(style: const TextStyle(color: Colors.black, fontSize: 13), children: [
                      TextSpan(text: '${c.authorName} ', style: const TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: c.text),
                    ])),
                    subtitle: Text(timeago.format(c.createdAt), style: const TextStyle(fontSize: 11)),
                  );
                },
                childCount: comments.length,
              ));
            },
          ),
        ])),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                hintText: 'Add a comment...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.primary)),
              ),
            )),
            const SizedBox(width: 8),
            // Send button on a white comment-bar → flip to dark for 3:1
            // contrast (UI component carrying action).
            GestureDetector(onTap: _comment,
              child: Container(width: 42, height: 42,
                decoration: const BoxDecoration(color: AppColors.dark, shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: AppColors.primary, size: 20))),
          ]),
        ),
      ]),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.flag_outlined, color: Colors.red), title: const Text('Report post'),
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
            messenger.showSnackBar(SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
              backgroundColor: Colors.orange,
            ));
          }
        }),
      ListTile(leading: const Icon(Icons.share_outlined), title: const Text('Share'), onTap: () => Navigator.pop(context)),
      ListTile(leading: const Icon(Icons.link), title: const Text('Copy link'), onTap: () => Navigator.pop(context)),
    ])));
  }
}
