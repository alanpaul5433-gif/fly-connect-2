import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'cached_image.dart';
import '../../core/constants/app_colors.dart';

/// Coordinates inline feed videos so only ONE plays at a time. When a new
/// [FeedVideo] starts, it pauses whatever was previously active — scrolling
/// never leaves two decoders running.
class _ActiveVideo {
  static VideoPlayerController? _current;
  static void play(VideoPlayerController c) {
    if (identical(_current, c)) return;
    _current?.pause();
    _current = c;
  }

  static void release(VideoPlayerController c) {
    if (identical(_current, c)) _current = null;
  }
}

/// Inline feed video. Shows a poster thumbnail until the card scrolls into view,
/// then autoplays muted + looping. The speaker pill toggles mute; the expand
/// pill opens a fullscreen player with controls (Chewie). Prop shape mirrors
/// [CachedFeedImage] so it drops into the same feed/detail render sites.
///
/// The main video area intentionally has no tap handler, so taps fall through
/// to the parent card's onTap (open post) — the same gesture as image posts.
class FeedVideo extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final double? aspectRatio;
  final double? width;
  final double? height;

  const FeedVideo({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.aspectRatio,
    this.width,
    this.height,
  });

  @override
  State<FeedVideo> createState() => _FeedVideoState();
}

class _FeedVideoState extends State<FeedVideo> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _muted = true;
  bool _visible = false;

  Future<void> _ensureController() async {
    if (_controller != null) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (!mounted) {
        c.dispose();
        _controller = null;
        return;
      }
      setState(() => _initialized = true);
      if (_visible) _play();
    } catch (_) {
      c.dispose();
      _controller = null;
    }
  }

  void _play() {
    final c = _controller;
    if (c == null || !_initialized) return;
    _ActiveVideo.play(c);
    c.play();
    if (mounted) setState(() {});
  }

  void _pause() => _controller?.pause();

  void _onVisibility(VisibilityInfo info) {
    final nowVisible = info.visibleFraction > 0.6;
    if (nowVisible == _visible) return;
    _visible = nowVisible;
    if (nowVisible) {
      if (_controller != null && _initialized) {
        _play();
      } else {
        _ensureController();
      }
    } else {
      _pause();
    }
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() => _muted = !_muted);
    c.setVolume(_muted ? 0 : 1);
  }

  void _openFullscreen() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FullscreenVideo(url: widget.videoUrl),
      fullscreenDialog: true,
    ));
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      _ActiveVideo.release(c);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = widget.height;
    final ready = _controller != null && _initialized;
    final playing = ready && _controller!.value.isPlaying;

    final poster = (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty)
        ? CachedFeedImage(url: widget.thumbnailUrl!, width: w, height: h, fit: BoxFit.cover)
        : Container(width: w, height: h, color: AppColors.dark);

    return VisibilityDetector(
      key: Key('feedvideo-${widget.videoUrl}'),
      onVisibilityChanged: _onVisibility,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              )
            else
              poster,

            // Play affordance while the poster shows / before playback starts.
            if (!playing)
              const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 56)),

            // Mute toggle.
            Positioned(
              left: 12,
              bottom: 12,
              child: GestureDetector(
                onTap: _toggleMute,
                child: _pill(Icon(_muted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white, size: 18)),
              ),
            ),

            // Fullscreen (with controls).
            Positioned(
              right: 12,
              bottom: 12,
              child: GestureDetector(
                onTap: _openFullscreen,
                child: _pill(const Icon(Icons.fullscreen, color: Colors.white, size: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(Widget child) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(100)),
        child: child,
      );
}

/// Fullscreen player with standard transport controls (Chewie). Uses its own
/// controller so the inline feed player keeps its muted/looping state.
class _FullscreenVideo extends StatefulWidget {
  final String url;
  const _FullscreenVideo({required this.url});
  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  VideoPlayerController? _vc;
  ChewieController? _chewie;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final vc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _vc = vc;
    try {
      await vc.initialize();
      if (!mounted) {
        vc.dispose();
        return;
      }
      setState(() {
        _chewie = ChewieController(
          videoPlayerController: vc,
          autoPlay: true,
          looping: false,
          allowMuting: true,
          aspectRatio: vc.value.aspectRatio == 0 ? 16 / 9 : vc.value.aspectRatio,
        );
      });
    } catch (_) {
      vc.dispose();
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
      body: Center(
        child: _chewie != null
            ? Chewie(controller: _chewie!)
            : const CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}
