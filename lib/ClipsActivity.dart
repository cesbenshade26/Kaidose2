import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'clip_service.dart';
import 'MediaPreloader.dart';
import 'ClipMusic.dart';
import 'PhotoFlipper.dart';
import 'ClipSideBar.dart';
import 'Clipcommentsheet.dart';

// ─── Your clips, loaded ahead of time ────────────────────────────────────────

/// Holds your own clips and keeps them current, so the Clips tab on your
/// profile already has everything the moment you open it. Profile starts it
/// as soon as it appears (see [start]) and warms the first screenful of
/// thumbnails ([precacheThumbnails]).
///
/// Thumbnails are saved on the phone's disk by cached_network_image, so they
/// don't download again next time. Downloading them only uses a little
/// bandwidth; nothing is stored in Firebase beyond what's already there.
class MyClipsCache extends ChangeNotifier {
  static final MyClipsCache instance = MyClipsCache._();
  MyClipsCache._();

  /// How many thumbnails get warmed up front (about two screens of grid).
  static const int _warmCount = 24;

  /// null until the first result arrives.
  List<ClipData>? clips;
  bool failed = false;

  StreamSubscription<List<ClipData>>? _sub;
  String? _uid;
  final Set<String> _warmed = {};

  // Older clips were saved without a thumbnail; one is made for each in the
  // background (once), and the clip updates by itself when it's ready.
  final Set<String> _attempted = {};
  final Set<String> _failedThumbs = {};
  bool _backfilling = false;

  /// True if making a thumbnail for this clip failed, so the grid should
  /// fall back to loading the video's first frame.
  bool thumbFailed(String id) => _failedThumbs.contains(id);

  // Pins you've just changed, applied on screen right away. They're dropped
  // once the server's copy of the clip agrees.
  final Map<String, DateTime?> _pinOverrides = {};

  DateTime? _pinTime(ClipData c) =>
      _pinOverrides.containsKey(c.id) ? _pinOverrides[c.id] : c.pinnedAt;

  bool isPinned(ClipData c) => _pinTime(c) != null;

  int get pinnedCount => clips?.where(isPinned).length ?? 0;

  /// Pin or unpin on screen immediately (call after the save succeeded).
  void setPinnedLocally(String clipId, bool pinned) {
    _pinOverrides[clipId] = pinned ? DateTime.now() : null;
    final list = clips;
    if (list == null) return;
    clips = _arrange(list);
    _warmPinnedVideos();
    notifyListeners();
  }

  /// Keeps your pinned clips ready so they open instantly: videos get a
  /// ready-to-play controller, photos are downloaded ahead of time.
  void _warmPinnedVideos() {
    final list = clips;
    if (list == null) return;
    final pinned = list.where(isPinned).take(ClipService.maxPins).toList();
    PreloadedMediaPool.instance.setProtected(
      {
        for (final c in pinned)
          if (!c.isPhoto && c.videoUrl.isNotEmpty) c.id: c.videoUrl,
      },
      images: [
        for (final c in pinned)
          if (c.isPhoto) ...c.allPhotos.take(4),
      ],
    );
  }

  /// Starts listening to your clips. Safe to call again and again; it only
  /// restarts if a different account has signed in.
  void start() {
    final uid = ClipService.currentUid;
    if (uid == null) return;
    if (_sub != null && _uid == uid) return;

    clear();
    _uid = uid;
    _sub = ClipService.getMyClips().listen(
          (list) {
        _pinOverrides.removeWhere((id, v) {
          final matches = list.where((c) => c.id == id);
          if (matches.isEmpty) return true; // clip is gone
          return (matches.first.pinnedAt != null) == (v != null);
        });
        clips = _arrange(list);
        _warmPinnedVideos();
        failed = false;
        notifyListeners();
        _backfillMissing();
      },
      onError: (e) {
        print('MyClipsCache error: $e');
        failed = true;
        notifyListeners();
      },
    );
  }

  /// Pinned clips first, in the order they were pinned (oldest pin first, so
  /// it sits top-left); everything else stays newest first.
  List<ClipData> _arrange(List<ClipData> list) {
    final pinned = list.where(isPinned).toList()
      ..sort((a, b) => _pinTime(a)!.compareTo(_pinTime(b)!));
    // Everything else keeps its newest-first order.
    final rest = [...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...pinned, ...rest.where((c) => !isPinned(c))];
  }

  /// Forgets everything (use when logging out).
  void clear() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    clips = null;
    failed = false;
    PreloadedMediaPool.instance.clear();
    _warmed.clear();
    _pinOverrides.clear();
    _attempted.clear();
    _failedThumbs.clear();
  }

  Future<void> _backfillMissing() async {
    if (_backfilling) return;
    _backfilling = true;
    try {
      while (true) {
        final list = clips;
        if (list == null) break;
        ClipData? next;
        for (final c in list) {
          final noThumb = c.thumbnailUrl == null || c.thumbnailUrl!.isEmpty;
          if (noThumb &&
              !c.isPhoto &&
              c.videoUrl.isNotEmpty &&
              !_attempted.contains(c.id)) {
            next = c;
            break;
          }
        }
        if (next == null) break;
        _attempted.add(next.id);

        String? url;
        try {
          url = await ClipService.backfillThumbnail(next);
        } catch (e) {
          print('MyClipsCache: thumbnail backfill error: $e');
        }
        if (url == null) {
          _failedThumbs.add(next.id);
          notifyListeners();
        }
        // On success the Firestore listener delivers the updated clip.
      }
    } finally {
      _backfilling = false;
    }
  }

  /// Downloads the first screenful of thumbnails ahead of time.
  void precacheThumbnails(BuildContext context) {
    final list = clips;
    if (list == null) return;
    for (final clip in list.take(_warmCount)) {
      final url = clip.thumbnailUrl;
      if (url == null || url.isEmpty || !_warmed.add(url)) continue;
      precacheImage(ClipThumb.provider(url), context).catchError((_) {
        _warmed.remove(url); // try again next time
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// One image provider for a clip thumbnail. The grid and the pre-loader both
/// use it, so a warmed thumbnail is found instantly. Decoded small (grid
/// cells are tiny) so a screenful doesn't eat memory.
class ClipThumb {
  static ImageProvider provider(String url) =>
      ResizeImage(CachedNetworkImageProvider(url), width: 360);
}

class ClipsActivity extends StatefulWidget {
  const ClipsActivity({Key? key}) : super(key: key);

  @override
  State<ClipsActivity> createState() => _ClipsActivityState();
}

class _ClipsActivityState extends State<ClipsActivity> {
  @override
  void initState() {
    super.initState();
    // Normally already running (Profile starts it); this is a safety net.
    MyClipsCache.instance.start();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Hold a clip: pin / unpin or delete.
  Future<void> _showClipMenu(ClipData clip) async {
    HapticFeedback.mediumImpact();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                MyClipsCache.instance.isPinned(clip)
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
                color: Colors.black87,
              ),
              title: Text(
                MyClipsCache.instance.isPinned(clip)
                    ? 'Unpin from top'
                    : 'Pin to top',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w500),
              ),
              onTap: () => Navigator.pop(sheetContext, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete clip',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.red),
              ),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'pin') {
      final cache = MyClipsCache.instance;
      final nowPinned = cache.isPinned(clip);
      if (!nowPinned && cache.pinnedCount >= ClipService.maxPins) {
        _toast(
            'You can pin up to ${ClipService.maxPins} clips. Unpin one first.');
        return;
      }
      final ok = await ClipService.setPinned(clip.id, !nowPinned);
      if (!ok) {
        _toast('Couldn\'t update the pin. Try again.');
      } else {
        cache.setPinnedLocally(clip.id, !nowPinned);
      }
    } else if (choice == 'delete') {
      await _confirmDelete(clip);
    }
  }

  Future<void> _confirmDelete(ClipData clip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this clip?'),
        content: const Text(
            'It will be removed for everyone and can\'t be brought back.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ClipService.deleteClip(clip);
    // The grid updates by itself when the clip disappears.
  }

  @override
  Widget build(BuildContext context) {
    final cache = MyClipsCache.instance;
    return AnimatedBuilder(
      animation: cache,
      builder: (context, _) {
        final clips = cache.clips;

        if (clips == null) {
          if (cache.failed) {
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
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          );
        }

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
              key: ValueKey(clips[index].id),
              clip: clips[index],
              fallbackToVideo: cache.thumbFailed(clips[index].id),
              pinned: cache.isPinned(clips[index]),
              onLongPress: () => _showClipMenu(clips[index]),
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

// ─── Thumbnail — the saved thumbnail image, no play button ──────────────────

class _ClipThumbnail extends StatelessWidget {
  final ClipData clip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Only true when a thumbnail couldn't be made for this clip.
  final bool fallbackToVideo;

  /// Show the pin badge.
  final bool pinned;

  const _ClipThumbnail({
    Key? key,
    required this.clip,
    required this.onTap,
    this.onLongPress,
    this.fallbackToVideo = false,
    this.pinned = false,
  }) : super(key: key);

  Widget _placeholder() => Container(
    color: Colors.grey[900],
    child: Icon(Icons.videocam_outlined, color: Colors.grey[700], size: 32),
  );

  @override
  Widget build(BuildContext context) {
    final url = clip.thumbnailUrl;
    final hasThumb = url != null && url.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black,
            child: hasThumb
                ? Image(
              image: ClipThumb.provider(url),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              // Already warmed -> shows instantly; otherwise fades in.
              frameBuilder: (context, child, frame, sync) {
                if (sync) return child;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _placeholder(),
                    AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: child,
                    ),
                  ],
                );
              },
              errorBuilder: (_, __, ___) => _VideoFirstFrame(clip: clip),
            )
            // No thumbnail yet: one is being made in the background. Only if
            // that failed do we load a frame from the video itself.
                : (fallbackToVideo ? _VideoFirstFrame(clip: clip) : _placeholder()),
          ),
          if (clip.isMultiPhoto)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(
                Icons.collections,
                size: 16,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          if (pinned)
            const Positioned(
              top: 6,
              left: 6,
              child: Icon(
                Icons.push_pin,
                size: 16,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
        ],
      ),
    );
  }
}

/// Fallback for clips that have no saved thumbnail: loads the video just far
/// enough to show its first frame.
class _VideoFirstFrame extends StatefulWidget {
  final ClipData clip;

  const _VideoFirstFrame({required this.clip});

  @override
  State<_VideoFirstFrame> createState() => _VideoFirstFrameState();
}

class _VideoFirstFrameState extends State<_VideoFirstFrame> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _loadFirstFrame();
  }

  Future<void> _loadFirstFrame() async {
    if (widget.clip.videoUrl.isEmpty) return;
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
      print('_VideoFirstFrame: error loading first frame: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialized && _controller != null) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    }
    return Container(
      color: Colors.grey[900],
      child: Icon(Icons.videocam_outlined, color: Colors.grey[700], size: 32),
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
    _preload(_currentPage);
  }

  /// Keeps this clip and the ones just below it ready to play.
  void _preload(int index) {
    PreloadedMediaPool.instance.preloadAround<ClipData>(
      widget.clips,
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
  void dispose() {
    _pageController.dispose();
    // The pages have already given their videos back; stop keeping the
    // window ready.
    PreloadedMediaPool.instance.clearWindow();
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
            onPageChanged: (index) {
              setState(() => _currentPage = index);
              _preload(index);
            },
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

  /// Borrows the video from the preloader: usually already initialised, so
  /// it plays the moment the page appears.
  Future<void> _loadVideo() async {
    // Photo clips have no video to load; the image is shown directly.
    if (widget.clip.isPhoto) return;
    final controller = await PreloadedMediaPool.instance
        .lease(widget.clip.id, widget.clip.videoUrl);
    if (!mounted) return;
    if (controller == null) {
      setState(() { _hasError = true; _isLoading = false; });
      return;
    }
    controller.setVolume(widget.clip.music != null ? 0 : 1);
    setState(() { _controller = controller; _isLoading = false; });
    if (widget.isActive && !_userPaused) controller.play();
  }

  @override
  void dispose() {
    // Stop it and hand it back; the preloader rewinds it if it keeps it,
    // or disposes it.
    final c = _controller;
    if (c != null) {
      try {
        c.pause();
      } catch (_) {}
    }
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

          // Clip area — shrinks when comments open
          AnimatedBuilder(
            animation: _commentAnimation,
            builder: (context, child) {
              final shrink = _commentAnimation.value;
              final sheetOffset = sheetHeight * shrink;
              final clipHeight = screenHeight - sheetOffset;
              final clipWidth = screenWidth * (1 - 0.15 * shrink);

              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: clipHeight,
                child: Center(
                  child: ClipRRect(
                    borderRadius:
                    BorderRadius.circular(12 * shrink),
                    child: SizedBox(
                      width: clipWidth,
                      height: clipHeight,
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
              child: ClipCommentSheet(clipId: widget.clip.id, onClose: _closeComments),
            ),

          // Side buttons — hidden when comments open
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

  Widget _buildPhotoContent() {
    return PhotoFlipper(urls: widget.clip.allPhotos);
  }

  Widget _buildVideoContent() {
    if (widget.clip.isPhoto) return _buildPhotoContent();
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