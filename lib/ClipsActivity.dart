import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'clip_service.dart';
import 'MediaPreloader.dart';
import 'ClipMusic.dart';
import 'PhotoFlipper.dart';
import 'ClipSideBar.dart';
import 'Clipcommentsheet.dart';
import 'DataSaver.dart';
import 'ReduceMotion.dart';

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

  // Clips showing in a profile grid right now (plus the next row), kept
  // ready alongside the pins. Keys are the viewer's pool keys.
  Map<String, String> _onScreenVideos = {};
  List<String> _onScreenImages = [];

  /// The grid tells us which clips are on screen; they're kept ready to
  /// play so tapping one never waits. Cheap to call often: nothing happens
  /// unless the set changed.
  void setOnScreen(Map<String, String> videos, List<String> images) {
    if (mapEquals(videos, _onScreenVideos) &&
        listEquals(images, _onScreenImages)) {
      return;
    }
    _onScreenVideos = videos;
    _onScreenImages = images;
    _warmPinnedVideos();
  }

  /// Keeps your pinned clips, and whatever a profile grid is showing, ready
  /// so they open instantly: videos get a ready-to-play controller, photos
  /// are downloaded ahead of time.
  void _warmPinnedVideos() {
    final list = clips ?? const <ClipData>[];
    final pinned = list.where(isPinned).take(ClipService.maxPins).toList();
    PreloadedMediaPool.instance.setProtected(
      {
        for (final c in pinned)
          if (!c.isPhoto && c.videoUrl.isNotEmpty) c.id: c.videoUrl,
        ..._onScreenVideos,
      },
      images: [
        for (final c in pinned)
          if (c.isPhoto) ...c.allPhotos.take(4),
        ..._onScreenImages,
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
    _onScreenVideos = {};
    _onScreenImages = [];
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

/// The Clips tab on a profile. [userId] null (or your own id) = your clips,
/// with hold-to-pin/delete. Anyone else's id = their clips, same grid and
/// viewer, pinned ones first, no editing.
class ClipsActivity extends StatefulWidget {
  final String? userId;

  const ClipsActivity({Key? key, this.userId}) : super(key: key);

  /// Opens one of YOUR clips full screen (from a "liked your clip"
  /// notification), with the rest of your clips to swipe through.
  static Future<void> openMine(BuildContext context, String clipId) async {
    final cache = MyClipsCache.instance;
    cache.start();
    // Just signed in / first open: give the list a moment to arrive.
    for (var i = 0; i < 20 && cache.clips == null; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (!context.mounted) return;
    final list = cache.clips ?? const <ClipData>[];
    final index = list.indexWhere((c) => c.id == clipId);
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That clip is no longer up')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MyClipViewer(clips: list, initialIndex: index),
      ),
    );
  }

  @override
  State<ClipsActivity> createState() => _ClipsActivityState();
}

class _ClipsActivityState extends State<ClipsActivity> {
  bool get _isOwn =>
      widget.userId == null || widget.userId == ClipService.currentUid;

  // Someone else's clips (only used when it isn't your profile).
  Stream<List<ClipData>>? _otherClips;

  /// At most this many videos are kept ready from the grid at once (phones
  /// can only hold so many video players).
  static const int _maxReadyVideos = 12;

  // Last on-screen rows handled, so scrolling only does work per new row.
  int _firstRow = -1, _lastRow = -1, _clipCount = -1;
  double _gridWidth = 0;
  final Set<String> _thumbsWarmed = {};

  String get _poolPrefix => _isOwn ? '' : 'profile:';

  /// Height of one grid row (3 across, 9:16 tiles, 1px gaps).
  double get _rowHeight {
    final cell = (_gridWidth - 2) / 3;
    return cell * 16 / 9 + 1;
  }

  /// Gets the rows on screen (and the next one) ready: the clips themselves
  /// for tapping, and thumbnails a couple of rows further down for
  /// scrolling.
  void _warmRows(List<ClipData> clips, double offset, double viewport) {
    if (_gridWidth <= 0 || clips.isEmpty) return;
    final rowH = _rowHeight;
    final first = (math.max(0.0, offset) / rowH).floor();
    final last = ((offset + viewport) / rowH).ceil();
    if (first == _firstRow && last == _lastRow && clips.length == _clipCount) {
      return;
    }
    _firstRow = first;
    _lastRow = last;
    _clipCount = clips.length;

    // Clips: what's on screen plus one row ahead (none ahead on Data Saver).
    final aheadRows = DataSaver.active ? 0 : 1;
    final from = math.min(clips.length, first * 3);
    final to = math.min(clips.length, (last + aheadRows) * 3);
    final videos = <String, String>{};
    final images = <String>[];
    for (var i = from; i < to; i++) {
      final c = clips[i];
      if (c.isPhoto) {
        images.addAll(c.allPhotos.take(4));
      } else if (c.videoUrl.isNotEmpty && videos.length < _maxReadyVideos) {
        videos['$_poolPrefix${c.id}'] = c.videoUrl;
      }
    }
    MyClipsCache.instance.setOnScreen(videos, images);

    // Thumbnails: two more rows beyond that, so scrolling never shows a
    // blank tile.
    final thumbsTo = math.min(clips.length, (last + aheadRows + 2) * 3);
    for (var i = from; i < thumbsTo; i++) {
      final url = clips[i].thumbnailUrl;
      if (url == null || url.isEmpty || !_thumbsWarmed.add(url)) continue;
      precacheImage(ClipThumb.provider(url), context).catchError((_) {
        _thumbsWarmed.remove(url);
      });
    }
  }

  @override
  void dispose() {
    // Stop keeping this grid's clips ready (pins stay ready).
    MyClipsCache.instance.setOnScreen({}, []);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (_isOwn) {
      // Normally already running (Profile starts it); this is a safety net.
      MyClipsCache.instance.start();
    } else {
      _otherClips = ClipService.getUserClips(widget.userId!);
    }
  }

  /// Their pinned clips first (in pin order), then newest first.
  List<ClipData> _arrangeOther(List<ClipData> list) {
    final pinned = list.where((c) => c.isPinned).toList()
      ..sort((a, b) => a.pinnedAt!.compareTo(b.pinnedAt!));
    final rest = list.where((c) => !c.isPinned).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...pinned, ...rest];
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
      backgroundColor: kc.surface,
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
                color: kc.grey(300),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                MyClipsCache.instance.isPinned(clip)
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
                color: kc.text,
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
    if (!_isOwn) return _buildOther();

    final cache = MyClipsCache.instance;
    return AnimatedBuilder(
      animation: cache,
      builder: (context, _) {
        final clips = cache.clips;
        if (clips == null) {
          return cache.failed ? _errorState() : _loadingState();
        }
        if (clips.isEmpty) return _emptyState();
        return _buildGrid(
          clips,
          pinned: cache.isPinned,
          fallbackToVideo: (c) => cache.thumbFailed(c.id),
          onLongPress: _showClipMenu,
        );
      },
    );
  }

  Widget _buildOther() {
    return StreamBuilder<List<ClipData>>(
      stream: _otherClips,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) return _errorState();
        if (!snapshot.hasData) return _loadingState();
        final clips = _arrangeOther(snapshot.data!);
        if (clips.isEmpty) return _emptyState();
        return _buildGrid(
          clips,
          pinned: (c) => c.isPinned,
          // Thumbnails are only made for your own old clips; for anyone
          // else's clip without one, show the video's first frame.
          fallbackToVideo: (c) =>
          c.thumbnailUrl == null || c.thumbnailUrl!.isEmpty,
        );
      },
    );
  }

  Widget _loadingState() =>
      Center(child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))));

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Error loading clips',
          style: TextStyle(color: kc.grey(600), fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_outlined, size: 80, color: kc.grey(400)),
          const SizedBox(height: 16),
          Text(
            'No Clips Yet',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: kc.grey(700)),
          ),
          const SizedBox(height: 8),
          Text(
            _isOwn
                ? 'Your posted clips will show up here'
                : 'Clips they post will show up here',
            style: TextStyle(fontSize: 14, color: kc.grey(600)),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(
      List<ClipData> clips, {
        required bool Function(ClipData) pinned,
        required bool Function(ClipData) fallbackToVideo,
        void Function(ClipData)? onLongPress,
      }) {
    // First screenful: get it ready as soon as the grid is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_clipCount != clips.length || _firstRow < 0) {
        _firstRow = -1;
        _warmRows(clips, 0, MediaQuery.of(context).size.height);
      }
    });
    return LayoutBuilder(
      builder: (context, box) {
        _gridWidth = box.maxWidth;
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical) {
              _warmRows(clips, n.metrics.pixels, n.metrics.viewportDimension);
            }
            return false;
          },
          child: _grid(clips,
              pinned: pinned,
              fallbackToVideo: fallbackToVideo,
              onLongPress: onLongPress),
        );
      },
    );
  }

  Widget _grid(
      List<ClipData> clips, {
        required bool Function(ClipData) pinned,
        required bool Function(ClipData) fallbackToVideo,
        void Function(ClipData)? onLongPress,
      }) {
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
        final clip = clips[index];
        return _ClipThumbnail(
          key: ValueKey(clip.id),
          clip: clip,
          fallbackToVideo: fallbackToVideo(clip),
          pinned: pinned(clip),
          showViews: _isOwn,
          onLongPress: onLongPress == null ? null : () => onLongPress(clip),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => _MyClipViewer(
                  clips: clips,
                  initialIndex: index,
                  // Someone else's clips get their own video slots, so
                  // watching them here never takes the video the Clips feed
                  // is holding for the same clip underneath.
                  poolPrefix: _isOwn ? '' : 'profile:',
                ),
              ),
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

  /// Show how many views it has (your own clips).
  final bool showViews;

  const _ClipThumbnail({
    Key? key,
    required this.clip,
    required this.onTap,
    this.onLongPress,
    this.fallbackToVideo = false,
    this.pinned = false,
    this.showViews = false,
  }) : super(key: key);

  /// 950, 1.2K, 3.4M
  static String _compact(int n) {
    String trim(double v) =>
        v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    if (n >= 1000000) return '${trim(n / 1000000)}M';
    if (n >= 1000) return '${trim(n / 1000)}K';
    return '$n';
  }

  Widget _placeholder() => Container(
    color: Colors.grey[900],
    child: Icon(Icons.videocam_outlined, color: kc.grey(700), size: 32),
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
          // Views, bottom right, over a soft shade so it reads on any
          // picture.
          if (showViews)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.only(right: 6, bottom: 5),
                  alignment: Alignment.bottomRight,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x66000000)],
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded,
                          size: 16, color: Colors.white),
                      const SizedBox(width: 1),
                      Text(
                        _compact(clip.viewCount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                        ),
                      ),
                    ],
                  ),
                ),
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
      child: Icon(Icons.videocam_outlined, color: kc.grey(700), size: 32),
    );
  }
}

// ─── A plain grid of clips (saved clips in Archives) ──────────────────────────

/// Clips in the same 3-across grid as a profile, no pins or view counts.
/// Tap opens them full screen; [onLongPress] for a menu.
class ClipGrid extends StatelessWidget {
  final List<ClipData> clips;
  final void Function(ClipData)? onLongPress;

  /// Keeps these videos apart from the Clips feed's in the preloader.
  final String poolPrefix;

  const ClipGrid({
    Key? key,
    required this.clips,
    this.onLongPress,
    this.poolPrefix = 'saved:',
  }) : super(key: key);

  /// Opens [clips] full screen at [index] (swipe through the rest).
  static Future<void> openViewer(
      BuildContext context, List<ClipData> clips, int index,
      {String poolPrefix = 'saved:'}) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _MyClipViewer(
              clips: clips, initialIndex: index, poolPrefix: poolPrefix),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
        childAspectRatio: 9 / 16,
      ),
      itemCount: clips.length,
      itemBuilder: (context, index) {
        final clip = clips[index];
        return _ClipThumbnail(
          key: ValueKey(clip.id),
          clip: clip,
          onLongPress: onLongPress == null ? null : () => onLongPress!(clip),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _MyClipViewer(
                clips: clips,
                initialIndex: index,
                poolPrefix: poolPrefix,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Full-screen viewer ───────────────────────────────────────────────────────

class _MyClipViewer extends StatefulWidget {
  final List<ClipData> clips;
  final int initialIndex;

  /// Prefix for this viewer's video slots in the preloader.
  final String poolPrefix;

  const _MyClipViewer({
    required this.clips,
    required this.initialIndex,
    this.poolPrefix = '',
  });

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
      id: (c) => '${widget.poolPrefix}${c.id}',
      url: (c) => c.isPhoto ? (c.photoUrl ?? '') : c.videoUrl,
      isImage: (c) => c.isPhoto,
      photos: (c) => c.allPhotos,
      ahead: DataSaver.clipsAhead,
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
                poolKey: '${widget.poolPrefix}${widget.clips[index].id}',
                clip: widget.clips[index],
                isActive: index == _currentPage,
              );
            },
          ),
          // Back arrow
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 22,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 6)]),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single clip page ─────────────────────────────────────────────────────────

/// Where the caption and side bar sit: just above the progress bar. This
/// viewer is full screen (no bottom bar), so it clears the phone's home
/// indicator first.
double _overlayBottom(BuildContext context) =>
    MediaQuery.of(context).padding.bottom + 14;

class _MyClipPage extends StatefulWidget {
  final ClipData clip;
  final bool isActive;

  /// This clip's slot in the preloader (its id, maybe with a prefix).
  final String poolKey;

  const _MyClipPage({
    required this.clip,
    required this.isActive,
    required this.poolKey,
  });

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
        .lease(widget.poolKey, widget.clip.videoUrl);
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
    // or disposes it. Done after this frame: pausing during teardown makes
    // the progress bar redraw while the screen is locked (crash).
    final c = _controller;
    final key = widget.poolKey;
    final isPhoto = widget.clip.isPhoto;
    Future.microtask(() {
      try {
        c?.pause();
      } catch (_) {}
      if (!isPhoto) PreloadedMediaPool.instance.release(key);
    });
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
    // Reduce Motion (phone setting): like it, but no floating heart.
    if (ReduceMotion.of(context)) return;
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
              child: ClipCommentSheet(
                clipId: widget.clip.id,
                creatorUid: widget.clip.creatorUid,
                onClose: _closeComments,
              ),
            ),

          // Side buttons — hidden when comments open
          AnimatedBuilder(
            animation: _commentAnimation,
            builder: (context, child) {
              return Positioned(
                right: 6,
                bottom: _overlayBottom(context) + 2,
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
              caption: widget.clip.caption,
              // On someone's profile: blocking them or "Not interested"
              // just closes the viewer.
              onHidden: (_) => Navigator.of(context).maybePop(),
            ),
          ),

          // Caption
          AnimatedBuilder(
            animation: _commentAnimation,
            builder: (context, child) {
              final bottomOffset = _overlayBottom(context) +
                  sheetHeight * _commentAnimation.value;
              return Positioned(
                bottom: bottomOffset,
                left: 14,
                right: 70,
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
                  playedColor: Colors.white,
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
        child: Center(
            child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC)))),
      );
    }
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text('Could not load clip',
              style: TextStyle(color: kc.grey(500))),
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