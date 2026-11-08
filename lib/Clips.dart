import 'PhotoFlipper.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'clip_service.dart';
import 'ClipSideBar.dart';
import 'Clipcommentsheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'Add.dart';
import 'FeedService.dart';
import 'UserProfileScreen.dart';
import 'MediaPreloader.dart';
import 'ClipMusic.dart';

class ClipsWidget extends StatefulWidget {
  final bool isTabActive;

  /// Viewer mode (opened from Search): plays exactly these clips, starting at
  /// [startIndex], with a back button instead of the + button. Null = the
  /// normal ranked feed.
  final List<ClipData>? pinnedClips;
  final int startIndex;

  const ClipsWidget({
    Key? key,
    this.isTabActive = true,
    this.pinnedClips,
    this.startIndex = 0,
  }) : super(key: key);

  @override
  State<ClipsWidget> createState() => _ClipsWidgetState();
}

class _ClipsWidgetState extends State<ClipsWidget> {
  late PageController _pageController;
  int _currentPage = 0;
  // True while the Add Clip screen is open on top, so the clip underneath
  // pauses instead of playing behind it.
  bool _covered = false;

  // Feed order, decided once per session by FeedService.rankClipIds so clips
  // never reshuffle under the user mid-scroll. Clips that arrive later are
  // appended; deleted ones drop out.
  List<String>? _order;
  bool _ranking = false;

  Future<void> _rankOnce(List<ClipData> clips) async {
    if (_ranking || _order != null || clips.isEmpty) return;
    _ranking = true;
    List<String> order;
    try {
      order = await FeedService.rankClipIds(clips);
    } catch (e) {
      print('Clips: ranking failed, using newest-first: $e');
      order = clips.map((c) => c.id).toList();
    }
    if (mounted) setState(() => _order = order);
  }

  List<ClipData> _applyOrder(List<ClipData> clips) {
    final order = _order!;
    final byId = {for (final c in clips) c.id: c};
    final ordered = <ClipData>[
      for (final id in order)
        if (byId.containsKey(id)) byId[id]!,
    ];
    final known = order.toSet();
    ordered.addAll(clips.where((c) => !known.contains(c.id)));
    return ordered;
  }

  @override
  void initState() {
    super.initState();
    _currentPage = widget.pinnedClips != null ? widget.startIndex : 0;
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    PreloadedMediaPool.instance.clearWindow();
    super.dispose();
  }

  int _preloadedCount = -1;

  /// Keeps the clip on screen and the next few below it ready to play (and
  /// one above), the same way your own clips viewer does.
  void _preload(List<ClipData> clips, int index) {
    PreloadedMediaPool.instance.preloadAround<ClipData>(
      clips,
      index,
      id: (c) => c.id,
      url: (c) => c.isPhoto ? (c.photoUrl ?? '') : c.videoUrl,
      isImage: (c) => c.isPhoto,
      photos: (c) => c.allPhotos,
      ahead: 3,
      behind: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
              child: widget.pinnedClips != null
                  ? _buildPager(widget.pinnedClips!)
                  : _buildFeed()),
          if (widget.pinnedClips != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 1),
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 22),
                ),
              ),
            )
          else
          // Add a clip: opens the Add Clip screen, and closing it comes
          // straight back here.
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: GestureDetector(
                onTap: _openAddClip,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 1),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 24),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openAddClip() async {
    setState(() => _covered = true);
    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: kAddRouteName),
        builder: (context) =>
        const AddWidget(destination: AddDestination.clip),
        fullscreenDialog: true,
      ),
    );
    if (mounted) setState(() => _covered = false);
  }

  Widget _buildFeed() {
    return StreamBuilder<List<ClipData>>(
      stream: ClipService.getOtherUsersClips(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          );
        }

        var clips = snapshot.data ?? [];

        if (clips.isNotEmpty && _order == null) {
          _rankOnce(clips);
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          );
        }
        if (_order != null) clips = _applyOrder(clips);

        if (clips.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_off_outlined,
                    size: 80, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text('No clips yet',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[400])),
                const SizedBox(height: 8),
                Text('Clips from other users will show up here',
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey[600])),
              ],
            ),
          );
        }

        return _buildPager(clips);
      },
    );
  }

  Widget _buildPager(List<ClipData> clips) {
    // First build, or clips were added/removed: (re)start the preload window.
    if (clips.length != _preloadedCount) {
      _preloadedCount = clips.length;
      final at = _currentPage.clamp(0, clips.isEmpty ? 0 : clips.length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && clips.isNotEmpty) _preload(clips, at);
      });
    }
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      onPageChanged: (index) {
        setState(() => _currentPage = index);
        _preload(clips, index);
      },
      itemCount: clips.length,
      itemBuilder: (context, index) {
        return _ClipPage(
          clip: clips[index],
          isActive: index == _currentPage && widget.isTabActive && !_covered,
        );
      },
    );
  }
}

class _ClipPage extends StatefulWidget {
  final ClipData clip;
  final bool isActive;

  const _ClipPage({required this.clip, required this.isActive});

  @override
  State<_ClipPage> createState() => _ClipPageState();
}

class _ClipPageState extends State<_ClipPage>
    with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _userPaused = false;

  LikeTrigger? _likeTrigger;

  // When this clip became the one on screen; used to tell a skip from a
  // watch when it stops being active.
  DateTime? _activeSince;

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
    if (widget.isActive) _activeSince = DateTime.now();
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
  void didUpdateWidget(_ClipPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _activeSince = DateTime.now();
      } else {
        _reportWatch();
      }
      if (widget.isActive && !_userPaused) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  Future<void> _loadVideo() async {
    // Photo clips have no video to load; they're just shown as an image.
    if (widget.clip.isPhoto) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      // Borrowed from the preloader: usually already initialised, so it
      // plays the moment the page appears.
      final controller = await PreloadedMediaPool.instance
          .lease(widget.clip.id, widget.clip.videoUrl);
      if (!mounted) return;
      if (controller == null) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
        return;
      }
      // A clip with a song plays that instead of its own audio.
      controller.setVolume(widget.clip.music != null ? 0 : 1);
      setState(() {
        _controller = controller;
        _isLoading = false;
      });
      if (widget.isActive && !_userPaused) controller.play();
    } catch (e) {
      print('_ClipPage: load error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  /// Quick swipe-away = skipped; watching most of it = watched. Anything in
  /// between says nothing either way.
  void _reportWatch() {
    final since = _activeSince;
    if (since == null) return;
    _activeSince = null;

    final secs = DateTime.now().difference(since).inMilliseconds / 1000.0;
    final c = _controller;
    final total = (c != null && c.value.isInitialized)
        ? c.value.duration.inMilliseconds / 1000.0
        : null;

    ClipEvent? event;
    if (secs < 2) {
      event = ClipEvent.skipped;
    } else if (widget.clip.isPhoto) {
      if (secs >= 4) event = ClipEvent.watched;
    } else if (total != null && total > 0 && secs >= total * 0.8) {
      event = ClipEvent.watched;
    }
    if (event != null) {
      FeedService.recordClipEvent(
          creatorUid: widget.clip.creatorUid,
          event: event,
          clipId: widget.clip.id,
          terms: widget.clip.terms);
    }
  }

  @override
  void dispose() {
    _reportWatch();
    try {
      _controller?.pause();
    } catch (_) {}
    if (!widget.clip.isPhoto) {
      PreloadedMediaPool.instance.release(widget.clip.id);
    }
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
    if (_showComments) {
      _closeComments();
      return;
    }
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
    final screenWidth = MediaQuery.of(context).size.width;
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

          // The clip's song (if any); plays only while this clip is on screen.
          ClipMusicPlayer(track: widget.clip.music, active: widget.isActive),

          // ── Clip area — shrinks when comments open ──
          AnimatedBuilder(
            animation: _commentAnimation,
            builder: (context, child) {
              final shrink = _commentAnimation.value;
              // How much vertical space the sheet takes
              final sheetOffset = sheetHeight * shrink;
              // Clip occupies full height minus sheet, anchored to top
              final clipHeight = screenHeight - sheetOffset;
              // Gentle horizontal shrink so white shows on sides
              final clipWidth = screenWidth * (1 - 0.15 * shrink);

              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                // Clip fills from top down to where sheet starts
                height: clipHeight,
                child: Center(
                  child: ClipRRect(
                    borderRadius:
                    BorderRadius.circular(12 * shrink),
                    child: SizedBox(
                      width: clipWidth,
                      // Use full clipHeight so video fills vertically
                      height: clipHeight,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: _buildVideoContent(),
          ),

          // ── Comment sheet ──
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
              child: ClipCommentSheet(
                clipId: widget.clip.id,
                onClose: _closeComments,
              ),
            ),

          // ── Side buttons — hidden when comments open ──
          AnimatedBuilder(
            animation: _commentAnimation,
            builder: (context, child) {
              return Positioned(
                right: 12,
                bottom: 80,
                child: AnimatedOpacity(
                  opacity: 1 - _commentAnimation.value,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: _showComments,
                    child: child,
                  ),
                ),
              );
            },
            child: ClipSideBar(
              clipId: widget.clip.id,
              creatorUid: widget.clip.creatorUid,
              onLikeTriggerReady: (trigger) => _likeTrigger = trigger,
              onCommentTap: _openComments,
            ),
          ),

          // ── Username + caption — slides up with sheet ──
          AnimatedBuilder(
            animation: _commentAnimation,
            builder: (context, child) {
              final bottomOffset =
                  60.0 + sheetHeight * _commentAnimation.value;
              return Positioned(
                bottom: bottomOffset,
                left: 16,
                right: 72,
                child: child!,
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => UserProfileScreen.open(
                      context, widget.clip.creatorUid,
                      username: widget.clip.creatorUsername),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.cyan.withOpacity(0.3),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            widget.clip.creatorUsername.isNotEmpty
                                ? widget.clip.creatorUsername[0]
                                .toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '@${widget.clip.creatorUsername}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          shadows: [
                            Shadow(
                                color: Colors.black54, blurRadius: 4)
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.clip.caption.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
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
                  ),
                ],
              ],
            ),
          ),

          // ── Progress bar ──
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

          // ── Floating heart ──
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
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.red,
                      size: 90,
                      shadows: [
                        Shadow(
                            color: Colors.black38, blurRadius: 8)
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoContent() {
    if (widget.clip.isPhoto) {
      return PhotoFlipper(urls: widget.clip.allPhotos);
    }
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  color: Colors.grey[600], size: 48),
              const SizedBox(height: 12),
              Text('Could not load clip',
                  style: TextStyle(color: Colors.grey[500])),
            ],
          ),
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