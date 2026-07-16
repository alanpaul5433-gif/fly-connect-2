import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/post_provider.dart';
import '../common/not_found_screen.dart';
import 'post_details_screen.dart';

/// Fetch-by-id entry point for `/posts/:postId` (notification taps, shared
/// links) — the feed-tap path still pushes [PostDetailsScreen] directly with
/// an already-loaded [PostModel]. Mirrors GroupDetailsScreen + getGroup, but
/// with a **retryable error** state kept distinct from **not found**: a
/// transient failure right after a cold-start push tap shouldn't look the
/// same as a genuinely deleted post.
class PostByIdScreen extends StatefulWidget {
  final String postId;
  const PostByIdScreen({super.key, required this.postId});

  @override
  State<PostByIdScreen> createState() => _PostByIdScreenState();
}

class _PostByIdScreenState extends State<PostByIdScreen> {
  bool _loading = true;
  bool _failed = false;
  PostModel? _post;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _failed = false; });
    try {
      final post = await context.read<PostProvider>().getPost(widget.postId);
      if (!mounted) return;
      setState(() { _post = post; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _failed = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_failed) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text('Couldn\'t load this post',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.dark,
                    elevation: 0,
                  ),
                  child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_post == null) {
      return const NotFoundScreen(
        title: 'Post not found',
        message: 'This post may have been deleted or the link is invalid.',
      );
    }
    return PostDetailsScreen(post: _post!);
  }
}
