import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/providers/post_provider.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/cached_image.dart';
import 'post_details_screen.dart';

/// Lists the signed-in user's bookmarked posts (`PostProvider.watchSavedPosts`).
/// Tapping a tile pushes [PostDetailsScreen] directly with the already-loaded
/// [PostModel] rather than going through `/posts/:id` (that route exists for
/// the fetch-by-id case — see PostByIdScreen).
class SavedPostsScreen extends StatelessWidget {
  const SavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Saved Posts',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<PostModel>>(
        stream: context.read<PostProvider>().watchSavedPosts(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = snap.data!;
          if (posts.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.bookmark_border, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                const Text('No saved posts yet', style: TextStyle(color: Colors.grey)),
              ]),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(2),
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
                        child: Center(child: Text(
                            post.caption.isNotEmpty ? post.caption[0] : '🔖',
                            style: const TextStyle(fontSize: 24)))),
              );
            },
          );
        },
      ),
    );
  }
}
