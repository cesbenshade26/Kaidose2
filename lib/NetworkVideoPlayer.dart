import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Minimal inline player for a remote (network) video — tap to toggle
/// play/pause, autoplays + loops on load. Shared by any message-style
/// widget that needs to play a video from a URL (Daily messages, chat
/// messages, anywhere else later) rather than a local file.
class NetworkVideoPlayer extends StatefulWidget {
  final String url;

  const NetworkVideoPlayer({Key? key, required this.url}) : super(key: key);

  @override
  State<NetworkVideoPlayer> createState() => _NetworkVideoPlayerState();
}

class _NetworkVideoPlayerState extends State<NetworkVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      controller.setLooping(true);
      controller.play();
    }).catchError((e) {
      print('NetworkVideoPlayer: init error: $e');
      if (mounted) setState(() => _hasError = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !_initialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 40, color: Colors.grey[500]),
              const SizedBox(height: 8),
              Text(
                'Video unavailable',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (!_initialized || controller == null) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(color: Colors.cyan),
        ),
      );
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          if (!controller.value.isPlaying)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
            ),
        ],
      ),
    );
  }
}