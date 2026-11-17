import 'StoryPhotoFrame.dart';
import 'StoryMusic.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'friend_request_service.dart';
import 'FriendDailyService.dart';
import 'ProfilePicManager.dart';
import 'StoryMediaItem.dart';
import 'VideoClipPlayer.dart';
import 'CircleRevealTransition.dart';
import 'StoryRing.dart';
import 'DailyShare.dart';
import 'SafetyService.dart';
import 'SafetySheets.dart';
import 'package:video_player/video_player.dart';

// Story circles, sized to match Instagram's.
const double _kRing = 84; // outer size, ring included
const double _kGap = 3; // white space between ring and picture
const double _kPic = _kRing - 2 * (_kGap + 3);
const double _kBarHeight = 116; // circle + name, with a little slack

class StoryBar extends StatefulWidget {
  /// Re-sorts every story bar (viewed stories move to the end). Dailies
  /// calls this on pull-to-refresh and when you scroll back to the top.
  static final ValueNotifier<int> reorder = ValueNotifier<int>(0);

  final void Function(Offset tapPosition) onTapOwnStory;
  final bool hasOwnPhotosToday;
  final bool hasViewedAllOwnPhotos;

  const StoryBar({
    Key? key,
    required this.onTapOwnStory,
    required this.hasOwnPhotosToday,
    required this.hasViewedAllOwnPhotos,
  }) : super(key: key);

  @override
  State<StoryBar> createState() => _StoryBarState();
}

class _StoryBarState extends State<StoryBar> with WidgetsBindingObserver {
  final FriendRequestService _friendRequestService = FriendRequestService();
  List<String> _friendUserIds = [];
  Map<String, String> _friendUsernames = {};

  StreamSubscription? _friendsSubscription;
  StreamSubscription? _authSubscription;

  void _onSafety() {
    if (mounted) setState(() {});
  }

  // The streams are made once (not on every rebuild, which re-read
  // Firestore and made the bar flicker).
  Stream<Set<String>>? _storiesStream;
  String _storiesFor = '';
  Stream<Set<String>>? _viewedStream;

  Stream<Set<String>> _storyStream() {
    final key = _friendUserIds.join(',');
    if (_storiesStream == null || key != _storiesFor) {
      _storiesFor = key;
      _storiesStream =
          FriendDailyService.getFriendsWithStoryToday(_friendUserIds);
    }
    return _storiesStream!;
  }

  // Order of the friends' circles. Unwatched stories first, watched ones
  // at the end (like Instagram). It's only re-sorted at set moments (app
  // opened/resumed, pull to refresh, scrolling back to the top, a new
  // story showing up), never right after you watch one, so circles don't
  // jump around under your finger.
  List<String> _order = [];
  bool _resort = true;

  List<String> _ordered(List<String> withStory, Set<String> viewed) {
    final current = withStory.toSet();
    final known = _order.toSet();
    if (_resort || !known.containsAll(current)) {
      _resort = false;
      _order = [
        ...withStory.where((id) => !viewed.contains(id)),
        ...withStory.where(viewed.contains),
      ];
    } else {
      // Someone's story ended: just drop them.
      _order = _order.where(current.contains).toList();
    }
    return _order;
  }

  void _onReorder() {
    if (!mounted) return;
    setState(() => _resort = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onReorder();
  }

  @override
  void initState() {
    super.initState();
    SafetyService.instance.changes.addListener(_onSafety);
    StoryBar.reorder.addListener(_onReorder);
    WidgetsBinding.instance.addObserver(this);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _friendsSubscription?.cancel();
        _friendsSubscription = null;
        if (mounted) {
          setState(() {
            _friendUserIds = [];
            _friendUsernames = {};
          });
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadFriends();
        });
      }
    });

    if (FirebaseAuth.instance.currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFriends();
      });
    }
  }

  void _loadFriends() {
    if (FirebaseAuth.instance.currentUser == null) return;

    _friendsSubscription?.cancel();
    _friendsSubscription = _friendRequestService
        .getAcceptedFriends()
        .listen((friends) {
      if (!mounted) return;
      if (FirebaseAuth.instance.currentUser == null) return;

      final ids = <String>[];
      final names = <String, String>{};
      final currentUid = _friendRequestService.currentUserId;

      for (final f in friends) {
        final friendId = f.fromUserId == currentUid ? f.toUserId : f.fromUserId;
        final friendName = f.fromUserId == currentUid ? f.toUsername : f.fromUsername;
        ids.add(friendId);
        names[friendId] = friendName;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && FirebaseAuth.instance.currentUser != null) {
          setState(() {
            _friendUserIds = ids;
            _friendUsernames = names;
          });
        }
      });
    }, onError: (e) {
      print('StoryBar: friend stream error: $e');
    });
  }

  @override
  void dispose() {
    SafetyService.instance.changes.removeListener(_onSafety);
    StoryBar.reorder.removeListener(_onReorder);
    WidgetsBinding.instance.removeObserver(this);
    _friendsSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const SizedBox(height: _kBarHeight);
    }

    return SizedBox(
      height: _kBarHeight,
      child: StreamBuilder<Set<String>>(
        stream: _storyStream(),
        builder: (context, storySnapshot) {
          final friendsWithStory = storySnapshot.data ?? {};

          return StreamBuilder<Set<String>>(
            stream: _viewedStream ??= FriendDailyService.getViewedStoriesStream(),
            builder: (context, viewedSnapshot) {
              final viewedFriends = viewedSnapshot.data ?? {};

              // Muted friends' stories stay out of the bar.
              final safety = SafetyService.instance;
              final withStory = _friendUserIds
                  .where((id) =>
              friendsWithStory.contains(id) && !safety.hidesCreator(id))
                  .toList();
              final visibleFriends = _ordered(withStory, viewedFriends);

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                itemCount: 1 + visibleFriends.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _OwnStoryCircle(
                      onTap: widget.onTapOwnStory,
                      hasPhotos: widget.hasOwnPhotosToday,
                      hasViewedAll: widget.hasViewedAllOwnPhotos,
                    );
                  }

                  final friendId = visibleFriends[index - 1];
                  final friendName = _friendUsernames[friendId] ?? 'Friend';
                  final hasViewed = viewedFriends.contains(friendId);

                  return _FriendStoryCircle(
                    friendUserId: friendId,
                    friendUsername: friendName,
                    hasViewed: hasViewed,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _OwnStoryCircle extends StatelessWidget {
  final void Function(Offset tapPosition) onTap;
  final bool hasPhotos;
  final bool hasViewedAll;

  const _OwnStoryCircle({
    required this.onTap,
    required this.hasPhotos,
    required this.hasViewedAll,
  });

  @override
  Widget build(BuildContext context) {
    final showCyanRing = hasPhotos && !hasViewedAll;
    final profilePic = ProfilePicManager.globalProfilePic;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTapDown: hasPhotos ? (details) => onTap(details.globalPosition) : null,
            child: Container(
              width: _kRing,
              height: _kRing,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: showCyanRing ? Colors.cyan : Colors.grey[350]!,
                  width: showCyanRing ? 3 : 1.5,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.all(_kGap),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300],
                ),
                child: ClipOval(
                  child: profilePic != null && profilePic.existsSync()
                      ? Image.file(
                    profilePic,
                    fit: BoxFit.cover,
                    width: _kPic,
                    height: _kPic,
                    key: ValueKey(profilePic.path),
                  )
                      : const _DefaultAvatar(size: _kPic),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const SizedBox(
            width: _kRing + 6,
            child: Text(
              'Your story',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendStoryCircle extends StatefulWidget {
  final String friendUserId;
  final String friendUsername;
  final bool hasViewed;

  const _FriendStoryCircle({
    required this.friendUserId,
    required this.friendUsername,
    required this.hasViewed,
  });

  @override
  State<_FriendStoryCircle> createState() => _FriendStoryCircleState();
}

class _FriendStoryCircleState extends State<_FriendStoryCircle> {
  String? _profilePicBase64;

  @override
  void initState() {
    super.initState();
    _loadFriendProfilePic();
  }

  Future<void> _loadFriendProfilePic() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.friendUserId)
          .get();
      final base64 = doc.data()?['profilePicBase64'] as String?;
      if (mounted && base64 != null) {
        setState(() => _profilePicBase64 = base64);
      }
    } catch (e) {
      print('FriendStoryCircle: Error loading pic: $e');
    }
  }

  void _openStory(Offset tapPosition) {
    FriendStory.open(
      context,
      userId: widget.friendUserId,
      username: widget.friendUsername,
      center: tapPosition,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTapDown: (details) => _openStory(details.globalPosition),
            child: Container(
              width: _kRing,
              height: _kRing,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: !widget.hasViewed ? Colors.cyan : Colors.grey[350]!,
                  width: !widget.hasViewed ? 3 : 1.5,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.all(_kGap),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300],
                ),
                child: ClipOval(
                  child: _profilePicBase64 != null
                      ? Image.memory(
                    base64Decode(_profilePicBase64!),
                    fit: BoxFit.cover,
                    width: _kPic,
                    height: _kPic,
                    errorBuilder: (_, __, ___) => const _DefaultAvatar(size: _kPic),
                  )
                      : const _DefaultAvatar(size: _kPic),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: _kRing + 6,
            child: Text(
              widget.friendUsername,
              maxLines: 1,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared blurred-background story media view ──────────────────────────────

/// Blurred, color-matched background like Instagram stories, for photos.
/// Videos skip the blur treatment (no cheap way to grab a still frame for
/// it) and just render centered on black instead.
class StoryMediaView extends StatelessWidget {
  final StoryMediaItem media;

  const StoryMediaView({Key? key, required this.media}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (media.isVideo) {
      // Fills the whole screen, cropping as needed — no padding, no
      // letterboxing, matching the "edge to edge" look requested.
      return Container(
        color: Colors.black,
        child: SizedBox.expand(
          child: VideoClipPlayer(
            videoFile: media.file,
            autoPlay: true,
            looping: true,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return StoryPhotoFrame(file: media.file);
  }
}

// ─── Own story viewer ────────────────────────────────────────────────────────

/// Your own story looks and plays exactly like a friend's (progress bars,
/// auto-advance), titled "Your story". Each post counts as watched as it
/// comes up, so the ring turns grey everywhere once you've seen them all.
class OwnStoryViewer extends StatelessWidget {
  final List<StoryMediaItem> items;

  /// Which post to open on (the first one you haven't seen yet).
  final int initialIndex;

  const OwnStoryViewer({Key? key, required this.items, this.initialIndex = 0})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FriendStoryViewer(
      items: items,
      username: 'Your story',
      initialIndex: initialIndex,
      onShown: (i) => OwnStory.markViewed(items[i].file.path),
    );
  }
}

/// Opens someone's story from anywhere (story bar, their profile): loads
/// it, marks it watched, and starts at the first post you haven't seen.
class FriendStory {
  FriendStory._();

  static Future<void> open(
      BuildContext context, {
        required String userId,
        required String username,
        required Offset center,
      }) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final items = await FriendDailyService.getFriendStoryPhotos(userId);
    if (!context.mounted || items.isEmpty) return;

    await FriendDailyService.markStoryViewed(userId);

    // If you've already watched some of today's posts and they've posted
    // more since, open at the first new one (the old ones stay one tap back).
    final seen = await StorySeen.get(userId);
    final start = (seen > 0 && seen < items.length) ? seen : 0;
    if (!context.mounted) return;

    await Navigator.push(
      context,
      CircleRevealRoute(
        center: center,
        builder: (context) => FriendStoryViewer(
          items: items,
          username: username,
          userId: userId,
          initialIndex: start,
        ),
      ),
    );
  }
}

// ─── Friend story viewer (with progress bar) ─────────────────────────────────

class FriendStoryViewer extends StatefulWidget {
  final List<StoryMediaItem> items;
  final String username;
  final String userId;

  /// Which post to open on (the first one you haven't seen yet).
  final int initialIndex;

  /// Called with each post's index as it comes on screen.
  final void Function(int index)? onShown;

  const FriendStoryViewer({
    Key? key,
    required this.items,
    required this.username,
    this.userId = '',
    this.initialIndex = 0,
    this.onShown,
  }) : super(key: key);

  @override
  State<FriendStoryViewer> createState() => _FriendStoryViewerState();
}

class _FriendStoryViewerState extends State<FriendStoryViewer>
    with SingleTickerProviderStateMixin {
  late int _currentIndex =
  widget.initialIndex.clamp(0, widget.items.length - 1);
  late AnimationController _progressController;
  static const Duration _photoDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this, duration: _photoDuration);
    _startProgress();
  }

  // Videos play for their real length instead of the 5 seconds a photo
  // gets (looked up once per video).
  final Map<String, Duration> _videoLengths = {};

  Future<Duration> _lengthOf(StoryMediaItem item) async {
    if (!item.isVideo) return _photoDuration;
    final known = _videoLengths[item.file.path];
    if (known != null) return known;
    final c = VideoPlayerController.file(item.file);
    var length = _photoDuration;
    try {
      await c.initialize();
      final d = c.value.duration;
      if (d > Duration.zero) length = d;
    } catch (_) {
    } finally {
      c.dispose();
    }
    _videoLengths[item.file.path] = length;
    return length;
  }

  // The Daily the post on screen was added from (public ones only).
  Map<String, dynamic>? _source;

  Future<void> _resolveSource(int index) async {
    _source = null; // the next post's tag (if any) fades in once known
    final item = widget.items[index];
    final src = item.source ?? await StorySource.lookup(item.file);
    if (!mounted || index != _currentIndex) return;
    final title = (src?['dailyTitle'] as String?)?.trim() ?? '';
    final show = src != null &&
        src['private'] != true &&
        title.isNotEmpty &&
        (src['dailyId'] as String?)?.isNotEmpty == true;
    setState(() => _source = show ? src : null);
  }

  /// Close the story and open the Daily the post came from.
  void _openSourceDaily() {
    final id = _source?['dailyId'] as String?;
    if (id == null) return;
    DailyShareLink.prepare(id);
    final nav = Navigator.of(context);
    nav.pop();
    DailyShareLink.open(nav.context, id);
  }

  Widget _sourceTag(double bottomInset) {
    final title = (_source?['dailyTitle'] as String?)?.trim() ?? '';
    return Positioned(
      left: 14,
      bottom: bottomInset + 18,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _source == null
            ? const SizedBox.shrink()
            : GestureDetector(
          key: ValueKey(title),
          behavior: HitTestBehavior.opaque,
          onTap: _openSourceDaily,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.38),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.white.withOpacity(0.18), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wb_sunny_outlined,
                      size: 13, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'From $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded,
                      size: 15, color: Colors.white.withOpacity(0.8)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Someone else's story: report it, mute or block them. The story
  /// pauses while any of this is on screen.
  Future<void> _openMenu() async {
    _progressController.stop();
    final uid = widget.userId;
    final name = widget.username;
    final s = SafetyService.instance;
    final today = DateTime.now().toIso8601String().split('T')[0];
    String? picked;
    await SafetyMenu.show(context, [
      SafetyMenuItem(
        icon: Icons.flag_outlined,
        label: 'Report story',
        destructive: true,
        onTap: () => picked = 'report',
      ),
      SafetyMenuItem(
        icon: s.isMuted(uid) ? Icons.volume_up_outlined : Icons.volume_off_outlined,
        label: s.isMuted(uid) ? 'Unmute $name' : 'Mute $name',
        subtitle: s.isMuted(uid) ? null : "Hide their story and clips. They won't know.",
        onTap: () => picked = 'mute',
      ),
      SafetyMenuItem(
        icon: Icons.block_rounded,
        label: 'Block $name',
        destructive: true,
        onTap: () => picked = 'block',
      ),
    ]);
    if (!mounted) return;

    var close = false;
    if (picked == 'report') {
      await ReportSheet.show(
        context,
        target: ReportTarget.story,
        targetId: '${uid}_$today',
        ownerUid: uid,
        ownerName: name,
        path: 'users/$uid/daily_story/$today',
      );
      close = s.isBlocked(uid); // blocked them from the thank-you screen
    } else if (picked == 'mute') {
      final mute = !s.isMuted(uid);
      await s.setMuted(uid, mute);
      close = mute;
    } else if (picked == 'block') {
      close = await BlockFlow.confirmAndBlock(context, uid, username: name);
    }
    if (!mounted) return;
    if (close) {
      Navigator.of(context).pop();
    } else {
      final index = _currentIndex;
      _progressController.forward().then((_) {
        if (mounted && index == _currentIndex) _nextPhoto();
      });
    }
  }

  Future<void> _startProgress() async {
    final index = _currentIndex;
    _resolveSource(index);
    if (widget.userId.isNotEmpty) {
      StorySeen.set(widget.userId, index + 1);
    }
    widget.onShown?.call(index);
    _progressController.reset();
    final length = await _lengthOf(widget.items[index]);
    if (!mounted || index != _currentIndex) return;
    _progressController.duration = length;
    _progressController.forward(from: 0).then((_) {
      if (mounted && index == _currentIndex) _nextPhoto();
    });
  }

  void _nextPhoto() {
    if (_currentIndex < widget.items.length - 1) {
      setState(() => _currentIndex++);
      _startProgress();
    } else {
      Navigator.pop(context);
    }
  }

  void _prevPhoto() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _startProgress();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          final x = details.globalPosition.dx;
          final width = MediaQuery.of(context).size.width;
          if (x < width / 3) {
            _prevPhoto();
          } else {
            _nextPhoto();
          }
        },
        child: Stack(
          children: [
            // Blurred background + rounded photo/video
            Positioned.fill(
              child: StoryMediaView(media: widget.items[_currentIndex]),
            ),

            // The post's song, if it has one
            // (Positioned so this zero-size widget doesn't shrink the Stack.)
            Positioned(
              left: 0,
              top: 0,
              child: StoryMusicLayer(
                key: ValueKey(widget.items[_currentIndex].file.path),
                item: widget.items[_currentIndex],
              ),
            ),

            // "From ___" tag when the post came from a public Daily
            _sourceTag(bottomInset),

            // Progress bars, just under the status bar
            Positioned(
              top: topInset + 8,
              left: 10,
              right: 10,
              child: Row(
                children: List.generate(widget.items.length, (i) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: i == _currentIndex
                            ? AnimatedBuilder(
                          animation: _progressController,
                          builder: (_, __) => LinearProgressIndicator(
                            value: _progressController.value,
                            valueColor:
                            const AlwaysStoppedAnimation(Colors.white),
                            backgroundColor: Colors.white.withOpacity(0.35),
                            minHeight: 2.5,
                          ),
                        )
                            : LinearProgressIndicator(
                          value: i < _currentIndex ? 1.0 : 0.0,
                          valueColor:
                          const AlwaysStoppedAnimation(Colors.white),
                          backgroundColor: Colors.white.withOpacity(0.35),
                          minHeight: 2.5,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Name on the left, plain X on the right, both under the bars
            Positioned(
              top: topInset + 18,
              left: 14,
              right: 4,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
                      ),
                    ),
                  ),
                  if (widget.userId.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openMenu,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white,
                          size: 26,
                          shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
                        ),
                      ),
                    ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 28,
                        shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DefaultAvatar extends StatelessWidget {
  final double size;
  const _DefaultAvatar({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey[300],
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: size * 0.1875,
            child: Container(
              width: size * 0.3125,
              height: size * 0.3125,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[600],
              ),
            ),
          ),
          Positioned(
            bottom: -size * 0.125,
            child: Container(
              width: size * 0.875,
              height: size * 0.5,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(size * 0.4375),
                  topRight: Radius.circular(size * 0.4375),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// How many of a friend's posts you've watched today, so reopening their
/// story starts at the first new one.
class StorySeen {
  static String _key(String uid) {
    final n = DateTime.now();
    return 'story_seen_${uid}_${n.year}-${n.month}-${n.day}';
  }

  static Future<int> get(String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getInt(_key(uid)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> set(String uid, int count) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (count > (p.getInt(_key(uid)) ?? 0)) {
        await p.setInt(_key(uid), count);
      }
    } catch (_) {}
  }
}