import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'SunColors.dart';
import 'dart:math' as math;
import 'AppColors.dart';
import 'DailyPhotoTracker.dart';
import 'DailyVideoTracker.dart';
import 'FriendDailyService.dart';
import 'FriendStoryBar.dart';
import 'StoryMediaItem.dart';
import 'CircleRevealTransition.dart';

/// Your own story (today's Your Daily photos and videos), shared by every
/// place that shows it: the story bar in Dailies and your avatar on Profile.
/// What you've already watched is remembered here too, so watching it in
/// one place turns the ring grey everywhere.
class OwnStory {
  OwnStory._();

  static final Set<String> _viewed = {};

  /// Bumps whenever something was marked as watched.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Today's photos and videos in the order they were posted. Files that
  /// are gone (e.g. from an old install) are left out.
  static List<StoryMediaItem> get items {
    final list = <StoryMediaItem>[
      ...DailyPhotoTracker.todaysPhotos
          .map((f) => StoryMediaItem(file: f, isVideo: false)),
      ...DailyVideoTracker.todaysVideos
          .map((f) => StoryMediaItem(file: f, isVideo: true)),
    ];
    list.sort((a, b) => _stamp(a.file).compareTo(_stamp(b.file)));
    return list.where((i) => i.file.existsSync()).toList();
  }

  static int _stamp(File file) {
    final name =
    file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : '';
    final m = RegExp(r'_(\d+)\.').firstMatch(name);
    return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
  }

  static bool get hasStory => items.isNotEmpty;

  static bool isViewed(String path) => _viewed.contains(path);

  /// Read-only view of what's been watched (use [markViewed] to add).
  static Set<String> get viewedPathsView => Set.unmodifiable(_viewed);

  static bool get viewedAll {
    final list = items;
    return list.isNotEmpty && list.every((i) => _viewed.contains(i.file.path));
  }

  static void markViewed(String path) {
    if (_viewed.add(path)) changes.value++;
  }

  /// Opens your story at the first post you haven't watched yet (or the
  /// start if you've seen them all), growing out of [center].
  static Future<void> open(BuildContext context, Offset center) async {
    final list = items;
    if (list.isEmpty) return;
    var start = list.indexWhere((i) => !_viewed.contains(i.file.path));
    if (start < 0) start = 0;
    await Navigator.push(
      context,
      CircleRevealRoute(
        center: center,
        builder: (_) => OwnStoryViewer(items: list, initialIndex: start),
      ),
    );
  }
}

/// The ring around an avatar: sun gradient when there's something new to watch,
/// grey once it's all been watched, nothing when there's no story. Drawn
/// outside the avatar, so the layout around it doesn't move.
class StoryRing extends StatelessWidget {
  final Widget child;
  final bool hasStory;
  final bool seen;
  final double width;
  final double gap;

  const StoryRing({
    Key? key,
    required this.child,
    required this.hasStory,
    required this.seen,
    this.width = 3.5,
    this.gap = 3,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!hasStory) return child;
    final out = gap + width;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -out,
          top: -out,
          right: -out,
          bottom: -out,
          child: IgnorePointer(
            child: CustomPaint(
              foregroundPainter: SunRingPainter(
                active: !seen,
                width: seen ? math.max(1.5, width / 2) : width,
                seenColor: context.colors.border,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.background,
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Your avatar with your story ring. Tapping opens your story when you have
/// one; otherwise [onTapNoStory] runs (e.g. open the profile picture
/// screen). Long-press always runs [onLongPress] when given.
class OwnStoryRing extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTapNoStory;
  final VoidCallback? onLongPress;

  const OwnStoryRing({
    Key? key,
    required this.child,
    this.onTapNoStory,
    this.onLongPress,
  }) : super(key: key);

  @override
  State<OwnStoryRing> createState() => _OwnStoryRingState();
}

class _OwnStoryRingState extends State<OwnStoryRing> {
  void _refresh() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    DailyPhotoTracker.addListener(_refresh);
    DailyVideoTracker.addListener(_refresh);
    OwnStory.changes.addListener(_refresh);
  }

  @override
  void dispose() {
    DailyPhotoTracker.removeListener(_refresh);
    DailyVideoTracker.removeListener(_refresh);
    OwnStory.changes.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final has = OwnStory.hasStory;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        if (has) {
          OwnStory.open(context, d.globalPosition);
        } else {
          widget.onTapNoStory?.call();
        }
      },
      onLongPress: widget.onLongPress,
      child: StoryRing(
        hasStory: has,
        seen: OwnStory.viewedAll,
        child: widget.child,
      ),
    );
  }
}

/// Someone else's avatar with their story ring (posted to their Daily or
/// sent to you). Tap opens their story the same way the story bar does.
/// On your own profile it falls back to [OwnStoryRing].
class UserStoryRing extends StatefulWidget {
  final String userId;
  final String username;
  final Widget child;

  const UserStoryRing({
    Key? key,
    required this.userId,
    required this.username,
    required this.child,
  }) : super(key: key);

  @override
  State<UserStoryRing> createState() => _UserStoryRingState();
}

class _UserStoryRingState extends State<UserStoryRing> {
  Stream<Set<String>>? _hasStory;
  Stream<Set<String>>? _viewed;

  bool get _isMe =>
      widget.userId == FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _wire();
  }

  @override
  void didUpdateWidget(UserStoryRing old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _wire();
  }

  void _wire() {
    if (_isMe) return;
    // Errors (e.g. no permission to see a stranger's story) just mean no ring.
    _hasStory = FriendDailyService.getFriendsWithStoryToday([widget.userId])
        .handleError((_) {});
    _viewed = FriendDailyService.getViewedStoriesStream().handleError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_isMe) return OwnStoryRing(child: widget.child);

    return StreamBuilder<Set<String>>(
      stream: _hasStory,
      builder: (context, storySnap) {
        final has = storySnap.data?.contains(widget.userId) ?? false;
        return StreamBuilder<Set<String>>(
          stream: _viewed,
          builder: (context, viewedSnap) {
            final seen = viewedSnap.data?.contains(widget.userId) ?? false;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: has
                  ? (d) => FriendStory.open(context,
                  userId: widget.userId,
                  username: widget.username,
                  center: d.globalPosition)
                  : null,
              child: StoryRing(hasStory: has, seen: seen, child: widget.child),
            );
          },
        );
      },
    );
  }
}