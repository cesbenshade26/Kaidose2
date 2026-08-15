import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'clip_service.dart';
import 'ClipSideBar.dart';
import 'ClipCommentSheet.dart';

class ClipsActivity extends StatefulWidget {
  const ClipsActivity({Key? key}) : super(key: key);

  @override
  State<ClipsActivity> createState() => _ClipsActivityState();
}

class _ClipsActivityState extends State<ClipsActivity> {
  late Stream<List<ClipData>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = ClipService.getMyClips();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClipData>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          );
        }

        if (snapshot.hasError) {
          print('ClipsActivity error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading clips',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final clips = snapshot.data ?? [];

        if (clips.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_outlined,
                    size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No Clips Yet',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your posted clips will show up here',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 1,
            mainAxisSpacing: 1,
            childAspectRatio: 9 / 16,
          ),
          itemCount: clips.length,
          itemBuilder: (context, index) {
            return _ClipThumbnail(
              clip: clips[index],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _MyClipViewer(
                      clips: clips,
                      initialIndex: index,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─── Thumbnail — shows first frame, no play button ───────────────────────────

class _ClipThumbnail extends StatefulWidget {
  final ClipData clip;
  final VoidCallback onTap;

  const _ClipThumbnail({required this.clip, required this.onTap});

  @override
  State<_ClipThumbnail> createState() => _ClipThumbnailState();
}

class _ClipThumbnailState extends State<_ClipThumbnail> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _loadFirstFrame();
  }

  Future<void> _loadFirstFrame() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.clip.videoUrl),
      );
      await controller.initialize();
      await controller.seekTo(Duration.zero);
      await controller.pause();
      if (mounted) {
        setState(() {
          _controller = controller;
          _initialized = true;
        });
      } else {
        controller.dispose();
      }
    } catch (e) {
      print('_ClipThumbnail: error loading first frame: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        color: Colors.black,
        child: _initialized && _controller != null
            ? SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        )
            : Container(
          color: Colors.grey[900],
          child: Icon(Icons.videocam_outlined,
              color: Colors.grey[700], size: 32),
        ),
      ),
    );
  }
}

// ─── Full-screen viewer ───────────────────────────────────────────────────────

class _MyClipViewer extends StatefulWidget {
  final List<ClipData> clips;
  final int initialIndex;

  const _MyClipViewer({required this.clips, required this.initialIndex});

  @override
  State<_MyClipViewer> createState() => _MyClipViewerState();
}

class _MyClipViewerState extends State<_MyClipViewer> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: widget.clips.length,
            physics: const ClampingScrollPhysics(),
            itemBuilder: (context, index) {
              return _MyClipPage(
                clip: widget.clips[index],
                isActive: index == _currentPage,
              );
            },
          ),
          // Back arrow
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back,
                    color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single clip page ─────────────────────────────────────────────────────────

class _MyClipPage extends StatefulWidget {
  final ClipData clip;
  final bool isActive;

  const _MyClipPage({required this.clip, required this.isActive});

  @override
  State<_MyClipPage> createState() => _MyClipPageState();
}

class _MyClipPageState extends State<_MyClipPage>
    with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _userPaused = false;

  LikeTrigger? _likeTrigger;

  // Comment sheet
  bool _showComments = false;
  late AnimationController _commentAnimController;
  late Animation<double> _commentAnimation;
  static const double _sheetFraction = 0.55;

  // Floating heart
  late AnimationController _floatingHeartController;
  late Animation<double> _floatingHeartScale;
  late Animation<double> _floatingHeartOpacity;
  Offset _floatingHeartPosition = Offset.zero;
  bool _showFloatingHeart = false;

  @override
  void initState() {
    super.initState();
    _loadVideo();

    _commentAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _commentAnimation = CurvedAnimation(
      parent: _commentAnimController,
      curve: Curves.easeOutCubic,
    );

    _floatingHeartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _floatingHeartScale = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.0, end: 1.3), weight: 40),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.3, end: 1.0), weight: 20),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.0), weight: 40),
    ]).animate(_floatingHeartController);
    _floatingHeartOpacity = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.0), weight: 40),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(_floatingHeartController);
  }

  @override
  void didUpdateWidget(_MyClipPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive && !_userPaused) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  Future<void> _loadVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.clip.videoUrl),
      );
      await controller.initialize();
      controller.setLooping(true);
      if (mounted) {
        setState(() { _controller = controller; _isLoading = false; });
        if (widget.isActive) controller.play();
      } else {
        controller.dispose();
      }
    } catch (e) {
      print('_MyClipPage: load error: $e');
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _commentAnimController.dispose();
    _floatingHeartController.dispose();
    super.dispose();
  }

  void _openComments() {
    setState(() => _showComments = true);
    _commentAnimController.forward();
  }

  void _closeComments() {
    _commentAnimController.reverse().then((_) {
      if (mounted) setState(() => _showComments = false);
    });
  }

  void _onSingleTap(Offset position) {
    if (_showComments) { _closeComments(); return; }
    final size = MediaQuery.of(context).size;
    if (position.dx > size.width / 3 &&
        position.dx < size.width * 2 / 3 &&
        position.dy > size.height / 3 &&
        position.dy < size.height * 2 / 3) {
      if (_controller == null) return;
      setState(() {
        if (_controller!.value.isPlaying) {
          _controller!.pause();
          _userPaused = true;
        } else {
          _controller!.play();
          _userPaused = false;
        }
      });
    }
  }

  void _onDoubleTap(Offset position) {
    _likeTrigger?.call();
    setState(() {
      _floatingHeartPosition = position;
      _showFloatingHeart = true;
    });
    _floatingHeartController.forward(from: 0).then((_) {
      if (mounted) setState(() => _showFloatingHeart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = screenHeight * _sheetFraction;

    return GestureDetector(
      onTapUp: (details) => _onSingleTap(details.globalPosition),
      onDoubleTapDown: (details) => _onDoubleTap(details.globalPosition),
      onDoubleTap: () {},
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Black background
          Container(color: Colors.black),

          // Clip area — shrinks when comments open
          AnimatedBuilder(
            animation: _commentAnimation,
            builder: (context, child) {
              final shrinkFraction = _commentAnimation.value;
              final availableHeight =
                  screenHeight - sheetHeight * shrinkFraction;
              final clipWidth = MediaQuery.of(context).size.width *
                  (1 - 0.15 * shrinkFraction);

              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: availableHeight,
                child: Center(
                  child: ClipRRect(
                    borderRadius:
                    BorderRadius.circular(12 * shrinkFraction),
                    child: SizedBox(
                      width: clipWidth,
                      height: availableHeight,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: _buildVideoContent(),
          ),

          // Comment sheet
          if (_showComments)
            AnimatedBuilder(
              animation: _commentAnimation,
              builder: (context, child) {
                final offset =
                    (1 - _commentAnimation.value) * sheetHeight;
                return Positioned(
                  bottom: -offset,
                  left: 0,
                  right: 0,
                  height: sheetHeight,
                  child: child!,
                );
              },
              child: ClipCommentSheet(onClose: _closeComments),
            ),

          // Side buttons
          Positioned(
            right: 12,
            bottom: 80,
            child: ClipSideBar(
              clipId: widget.clip.id,
              onLikeTriggerReady: (trigger) => _likeTrigger = trigger,
              onCommentTap: _openComments,
            ),
          ),

          // Caption
          AnimatedBuilder(
            animation: _commentAnimation,
            builder: (context, child) {
              final bottomOffset =
                  60 + sheetHeight * _commentAnimation.value;
              return Positioned(
                bottom: bottomOffset,
                left: 16,
                right: 72,
                child: child!,
              );
            },
            child: widget.clip.caption.isNotEmpty
                ? Text(
              widget.clip.caption,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                shadows: [
                  Shadow(color: Colors.black54, blurRadius: 4)
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            )
                : const SizedBox(),
          ),

          // Progress bar
          if (_controller != null && _controller!.value.isInitialized)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.cyan,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white10,
                ),
              ),
            ),

          // Floating heart
          if (_showFloatingHeart)
            Positioned(
              left: _floatingHeartPosition.dx - 45,
              top: _floatingHeartPosition.dy - 45,
              child: AnimatedBuilder(
                animation: _floatingHeartController,
                builder: (context, child) => Opacity(
                  opacity: _floatingHeartOpacity.value,
                  child: Transform.scale(
                    scale: _floatingHeartScale.value,
                    child: const Icon(Icons.favorite,
                        color: Colors.red,
                        size: 90,
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 8)
                        ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoContent() {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
            child: CircularProgressIndicator(color: Colors.cyan)),
      );
    }
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text('Could not load clip',
              style: TextStyle(color: Colors.grey[500])),
        ),
      );
    }
    if (_controller != null && _controller!.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
          ),
          if (!_controller!.value.isPlaying && _userPaused)
            const Center(
              child: Icon(Icons.play_arrow_rounded,
                  color: Colors.white70, size: 72),
            ),
        ],
      );
    }
    return Container(color: Colors.black);
  }
}