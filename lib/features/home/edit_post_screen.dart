import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../shared/providers/post_provider.dart';
import '../../shared/models/models.dart';

/// Caption + location edit for an existing post (M-7). Media is not
/// editable here — see docs/superpowers/specs/2026-07-16-m7-post-edit-chat-attachments-design.md.
/// On success, pops with the updated [PostModel] so the caller (a post
/// menu on a screen that doesn't have a live Firestore listener, like
/// PostDetailsScreen) can refresh its local display without a full reload.
class EditPostScreen extends StatefulWidget {
  final PostModel post;
  const EditPostScreen({super.key, required this.post});

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  late final TextEditingController _captionController;
  late final TextEditingController _locationController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.post.caption);
    _locationController =
        TextEditingController(text: widget.post.location ?? '');
  }

  @override
  void dispose() {
    _captionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final caption = _captionController.text.trim();
    final hasMedia = widget.post.mediaUrls.isNotEmpty;
    if (caption.isEmpty && !hasMedia) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('A text post needs a caption.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _loading = true);
    final location =
        _locationController.text.trim().isEmpty ? null : _locationController.text.trim();
    try {
      await context
          .read<PostProvider>()
          .updatePost(widget.post.id, caption: caption, location: location);
      if (!mounted) return;
      final updated = PostModel(
        id: widget.post.id,
        authorId: widget.post.authorId,
        authorName: widget.post.authorName,
        authorPhotoUrl: widget.post.authorPhotoUrl,
        mediaUrls: widget.post.mediaUrls,
        mediaType: widget.post.mediaType,
        thumbnailUrl: widget.post.thumbnailUrl,
        aspectRatio: widget.post.aspectRatio,
        durationMs: widget.post.durationMs,
        caption: caption,
        location: location,
        likeCount: widget.post.likeCount,
        commentCount: widget.post.commentCount,
        isReported: widget.post.isReported,
        reportCount: widget.post.reportCount,
        groupId: widget.post.groupId,
        createdAt: widget.post.createdAt,
        editedAt: DateTime.now(),
      );
      Navigator.pop(context, updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save changes. Please try again.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.dark),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Center(child: Text('Edit Post', style: AppTextStyles.h4)),
              ),
              ElevatedButton(
                onPressed: _loading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4F53C),
                  foregroundColor: const Color(0xFF1A1D27),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  minimumSize: const Size(80, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF1A1D27)),
                      )
                    : const Text('Save'),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  TextField(
                    controller: _captionController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                    decoration: const InputDecoration(
                      hintText: "What's on your mind?",
                      hintStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Color(0xFFF5F5F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide(color: Color(0xFF1A1D27), width: 1),
                      ),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _locationController,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.dark),
                        decoration: InputDecoration(
                          hintText: 'Add location',
                          hintStyle:
                              AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
