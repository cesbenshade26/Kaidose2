import 'package:flutter/material.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';

class VideoClipPlayer extends StatefulWidget {
  final File videoFile;
  final bool autoPlay;
  final bool looping;
  final BoxFit fit;

  const VideoClipPlayer({
    Key? key,
    required this.videoFile,
    this.autoPlay = true,
    this.looping = true,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  State<VideoClipPlayer> createState() => _VideoClipPlayerState();
}

class _VideoClipPlayerState extends State<VideoClipPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isMuted = false;
  bool _showMuteButton = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(VideoClipPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle autoPlay changes (for when clip scrolls in/out of view)
    if (widget.autoPlay != oldWidget.autoPlay && _controller != null && _isInitialized) {
      print('VideoClipPlayer: autoPlay changed from ${oldWidget.autoPlay} to ${widget.autoPlay} for ${widget.videoFile.path}');
      if (widget.autoPlay) {
        print('  -> Starting playback');
        _controller!.setVolume(_isMuted ? 0.0 : 1.0);
        _controller!.play();
      } else {
        print('  -> Stopping playback');
        _controller!.pause();
        _controller!.setVolume(0.0);
        _controller!.seekTo(Duration.zero); // Reset to beginning
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.file(widget.videoFile);

    try {
      await _controller!.initialize();

      if (mounted) {
        _controller!.setLooping(widget.looping);

        if (widget.autoPlay) {
          print('VideoClipPlayer: Initializing with autoPlay=true for ${widget.videoFile.path}');
          _controller!.setVolume(_isMuted ? 0.0 : 1.0);
          await _controller!.play();
        } else {
          print('VideoClipPlayer: Initializing with autoPlay=false for ${widget.videoFile.path}');
          // Don't play and ensure no volume
          _controller!.setVolume(0.0);
        }

        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing video: $e');
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _controller?.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _handleTapDown(TapDownDetails details) {
    if (!_isInitialized) return;

    final RenderBox box = context.findRenderObject() as RenderBox;
    final size = box.size;
    final position = details.localPosition;

    // Define mute button area (bottom right corner, 60x60 region)
    final buttonSize = 60.0;
    final buttonArea = Rect.fromLTWH(
      size.width - buttonSize,
      size.height - buttonSize,
      buttonSize,
      buttonSize,
    );

    final exactButtonArea = Rect.fromLTWH(
      size.width - 40, // 40x40 exact button size
      size.height - 40,
      40,
      40,
    );

    // Check if tap is in exact button area
    if (exactButtonArea.contains(position)) {
      // Always toggle AND show button when tapping exact area
      _toggleMute();
      setState(() {
        _showMuteButton = true;
      });
    }
    // Check if tap is near button area (but not exact)
    else if (buttonArea.contains(position)) {
      // Just show button without toggling
      setState(() {
        _showMuteButton = true;
      });
    }
    // Tap elsewhere - hide button
    else {
      setState(() {
        _showMuteButton = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTapDown: _handleTapDown,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video player
          FittedBox(
            fit: widget.fit,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),

          // Mute button (bottom right, appears on interaction)
          Positioned(
            bottom: 8,
            right: 8,
            child: AnimatedOpacity(
              opacity: _showMuteButton ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: () {
                  _toggleMute();
                  // Keep button visible for a moment after manual tap
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) {
                      setState(() {
                        _showMuteButton = false;
                      });
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}