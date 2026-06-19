import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../shared/models/models.dart';
import '../../shared/mock/story_state.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/cached_image.dart';

class StoryViewerScreen extends StatefulWidget {
  final UserModel user;
  final String storyImageUrl;
  final Uint8List? imageBytes;
  final bool isOwn;

  const StoryViewerScreen({
    super.key,
    required this.user,
    this.storyImageUrl = '',
    this.imageBytes,
    this.isOwn = false,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..forward();
    _timer = Timer(const Duration(seconds: 5), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _confirmRemove() async {
    _timer?.cancel();
    _progressController.stop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Story?'),
        content: const Text('Your story will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      StoryState.instance.removeStory();
      Navigator.pop(context); // close story viewer
    } else if (mounted) {
      // Resume if cancelled
      _progressController.forward(from: _progressController.value);
      _timer = Timer(
        Duration(milliseconds: ((1 - _progressController.value) * 5000).round()),
        () { if (mounted) Navigator.pop(context); },
      );
    }
  }

  Widget _buildImage() {
    if (widget.imageBytes != null) {
      return Image.memory(widget.imageBytes!, fit: BoxFit.cover);
    }
    if (widget.storyImageUrl.isNotEmpty) {
      return CachedFeedImage(
        url: widget.storyImageUrl,
        fit: BoxFit.cover,
        placeholder: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        errorWidget: Container(
          color: AppColors.dark,
          child: const Center(
            child: Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 48),
          ),
        ),
      );
    }
    return Container(color: AppColors.dark);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(),

            // Top gradient
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 160,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),

            // Progress bar
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12, right: 12,
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (_, __) => LinearProgressIndicator(
                  value: _progressController.value,
                  backgroundColor: Colors.white30,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 2,
                ),
              ),
            ),

            // User info row
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 16, right: 16,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.dark,
                    backgroundImage: widget.user.photoUrl != null
                        ? NetworkImage(widget.user.photoUrl!)
                        : null,
                    child: widget.user.photoUrl == null
                        ? Text(widget.user.name.isNotEmpty ? widget.user.name[0] : '?',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.user.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        if (widget.user.airline != null &&
                            widget.user.airline!.isNotEmpty)
                          Text(
                            '${widget.user.airline} · ${widget.user.position ?? ''}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  // Delete button for own stories
                  if (widget.isOwn)
                    GestureDetector(
                      onTap: _confirmRemove,
                      child: Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36, height: 36,
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            const Positioned(
              bottom: 40, left: 0, right: 0,
              child: Center(
                child: Text('Tap anywhere to close',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
