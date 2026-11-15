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

  // The feed for the chosen lens (For You, Friends, a Daily, a group chat):
  // loaded once, then extended as the user nears the end, so clips never
  // reshuffle mid-scroll. Clips already seen are left out by the feed.
  List<ClipData> _feed = [];
  Map<String, ClipProof> _proof = {}; // clipId -> "liked by" label
  String? _moreId; // first "More like this" clip in a group view
  bool _loadingFeed = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _feedGen = 0; // bumps on every lens switch, so late results are dropped

  List<ClipLens> _lenses = const [ClipLens.forYou];
  ClipLens _lens = ClipLens.forYou;
  bool _showLenses = false;

  Future<void> _loadLenses() async {
    try {
      final lenses = await FeedService.getClipLenses();
      if (mounted) setState(() => _lenses = lenses);
    } catch (e) {
      print('Clips: lenses failed: $e');
    }
  }

  Future<void> _loadFeed() async {
    final gen = _feedGen;
    try {
      final page = await FeedService.getClipFeedPage(lens: _lens);
      if (!mounted || gen != _feedGen) return;
      setState(() {
        _feed = page.clips;
        _proof = Map.of(page.proof);
        _moreId = page.firstMoreId;
        _noMore = page.clips.isEmpty;
        _loadingFeed = false;
      });
    } catch (e) {
      print('Clips: feed load failed: $e');
      if (mounted && gen == _feedGen) setState(() => _loadingFeed = false);
    }
  }

  /// Fetches the next batch, skipping everything already in the feed.
  Future<void> _loadMore() async {
    if (_loadingMore || _noMore || widget.pinnedClips != null) return;
    _loadingMore = true;
    final gen = _feedGen;
    try {
      final page = await FeedService.getClipFeedPage(
          lens: _lens, exclude: _feed.map((c) => c.id).toSet());
      if (!mounted || gen != _feedGen) return;
      setState(() {
        if (page.clips.isEmpty) {
          _noMore = true;
        } else {
          _feed.addAll(page.clips);
          _proof.addAll(page.proof);
          _moreId ??= page.firstMoreId;
        }
      });
    } catch (e) {
      print('Clips: load more failed: $e');
    } finally {
      if (gen == _feedGen) _loadingMore = false;
    }
  }

  void _selectLens(ClipLens lens) {
    if (lens == _lens) {
      setState(() => _showLenses = false);
      return;
    }
    // A fresh controller so the new feed starts at its first clip.
    final old = _pageController;
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    PreloadedMediaPool.instance.clearWindow();
    setState(() {
      _feedGen++;
      _lens = lens;
      _showLenses = false;
      _feed = [];
      _proof = {};
      _moreId = null;
      _noMore = false;
      _loadingMore = false;
      _loadingFeed = true;
      _currentPage = 0;
      _preloadedCount = -1;
    });
    _loadFeed();
  }

  @override
  void initState() {
    super.initState();
    _currentPage = widget.pinnedClips != null ? widget.startIndex : 0;
    _pageController = PageController(initialPage: _currentPage);
    if (widget.pinnedClips == null) {
      _loadFeed();
      _loadLenses();
    }
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
          else ...[
            _buildLensSwitcher(context),
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
        ],
      ),
    );
  }

  /// "For You ▾" at the top. Tapped, a row of chips drops down: For You,
  /// Friends, then the user's top Dailies and group chats.
  Widget _buildLensSwitcher(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Positioned(
      top: top + 8,
      left: 60,
      right: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showLenses = !_showLenses),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: Colors.white54, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _lens.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _showLenses ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: !_showLenses
                ? const SizedBox(width: double.infinity)
                : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [for (final l in _lenses) _lensChip(l)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lensChip(ClipLens l) {
    final selected = l == _lens;
    final icon = switch (l.kind) {
      'friends' => Icons.people_alt_outlined,
      'daily' => Icons.wb_sunny_outlined,
      'chat' => Icons.forum_outlined,
      _ => Icons.auto_awesome_outlined,
    };
    return GestureDetector(
      onTap: () => _selectLens(l),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        constraints: const BoxConstraints(maxWidth: 170),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14, color: selected ? Colors.black87 : Colors.white),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                l.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.black87 : Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
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
    if (_loadingFeed) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyan),
      );
    }

    if (_feed.isEmpty) {
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
            Text(
                _lens.isForYou
                    ? 'Clips from other users will show up here'
                    : 'Clips liked or posted in ${_lens.label} will show up here',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          ],
        ),
      );
    }

    return _buildPager(_feed);
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
        setState(() {
          _currentPage = index;
          _showLenses = false;
        });
        _preload(clips, index);
        // Close to the end: fetch the next batch in the background.
        if (index >= clips.length - 5) _loadMore();
      },
      itemCount: clips.length,
      itemBuilder: (context, index) {
        final clip = clips[index];
        return _ClipPage(
          key: ValueKey('clip-${_lens.key}-${clip.id}'),
          clip: clip,
          isActive: index == _currentPage && widget.isTabActive && !_covered,
          proof: _proof[clip.id],
          moreLikeThis: clip.id == _moreId,
        );
      },
    );
  }
}

class _ClipPage extends StatefulWidget {
  final ClipData clip;
  final bool isActive;

  /// "Sam and 2 others liked this", when people the viewer knows liked it.
  final ClipProof? proof;

  /// First clip after a group's own clips ran out.
  final bool moreLikeThis;

  const _ClipPage({
    Key? key,
    required this.clip,
    required this.isActive,
    this.proof,
    this.moreLikeThis = false,
  }) : super(key: key);

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

  // When this clip became the one on screen, and how long the user had it
  // paused since then; together they say how much of it was watched.
  DateTime? _activeSince;
  DateTime? _pauseStart;
  Duration _pausedFor = Duration.zero;

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
        _pausedFor = Duration.zero;
        _pauseStart = null;
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

  /// The clip left the screen: report how much of it was watched (time on
  /// screen, minus time paused, compared to its length; above 1.0 means it
  /// looped and they kept watching). The feed uses it for this clip's
  /// quality, to mark it as seen, and to learn what the user likes.
  void _reportWatch() {
    final since = _activeSince;
    if (since == null) return;
    _activeSince = null;

    var paused = _pausedFor;
    if (_pauseStart != null) paused += DateTime.now().difference(_pauseStart!);
    _pauseStart = null;
    _pausedFor = Duration.zero;

    final onScreen = DateTime.now().difference(since) - paused;
    final secs = onScreen.inMilliseconds / 1000.0;
    if (secs <= 0) return;

    double watched;
    if (widget.clip.isPhoto) {
      watched = secs / FeedService.photoViewSeconds(widget.clip);
    } else {
      final c = _controller;
      final total = (c != null && c.value.isInitialized)
          ? c.value.duration.inMilliseconds / 1000.0
          : 0.0;
      // Never loaded: only a quick swipe-away says anything.
      if (total <= 0) {
        if (secs >= 2) return;
        watched = 0;
      } else {
        watched = secs / total;
      }
    }
    FeedService.recordClipView(
        clip: widget.clip, watched: watched, seconds: secs);
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
          _pauseStart = DateTime.now();
        } else {
          _controller!.play();
          _userPaused = false;
          if (_pauseStart != null) {
            _pausedFor += DateTime.now().difference(_pauseStart!);
            _pauseStart = null;
          }
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
                creatorUid: widget.clip.creatorUid,
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
                if (widget.moreLikeThis) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('More like this',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 10),
                ],
                if (widget.proof != null) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite,
                          color: Colors.redAccent, size: 14),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          widget.proof!.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4)
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
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