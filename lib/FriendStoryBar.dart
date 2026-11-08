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

class StoryBar extends StatefulWidget {
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

class _StoryBarState extends State<StoryBar> {
  final FriendRequestService _friendRequestService = FriendRequestService();
  List<String> _friendUserIds = [];
  Map<String, String> _friendUsernames = {};

  StreamSubscription? _friendsSubscription;
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();

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
    _friendsSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return const SizedBox(height: 140);
    }

    return SizedBox(
      height: 140,
      child: StreamBuilder<Set<String>>(
        stream: FriendDailyService.getFriendsWithStoryToday(_friendUserIds),
        builder: (context, storySnapshot) {
          final friendsWithStory = storySnapshot.data ?? {};

          return StreamBuilder<Set<String>>(
            stream: FriendDailyService.getViewedStoriesStream(),
            builder: (context, viewedSnapshot) {
              final viewedFriends = viewedSnapshot.data ?? {};

              final visibleFriends = _friendUserIds
                  .where((id) => friendsWithStory.contains(id))
                  .toList();

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTapDown: hasPhotos ? (details) => onTap(details.globalPosition) : null,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: showCyanRing ? Colors.cyan : Colors.grey[400]!,
                  width: showCyanRing ? 4 : 3,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300],
                ),
                child: ClipOval(
                  child: profilePic != null && profilePic.existsSync()
                      ? Image.file(
                    profilePic,
                    fit: BoxFit.cover,
                    width: 102,
                    height: 102,
                    key: ValueKey(profilePic.path),
                  )
                      : const _DefaultAvatar(size: 102),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Your story',
            style: TextStyle(fontSize: 12, color: Colors.black87),
            overflow: TextOverflow.ellipsis,
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

  void _openStory(Offset tapPosition) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final items = await FriendDailyService.getFriendStoryPhotos(widget.friendUserId);
    if (!mounted) return;
    if (items.isEmpty) return;

    await FriendDailyService.markStoryViewed(widget.friendUserId);

    // If you've already watched some of today's posts and they've posted
    // more since, open at the first new one (the old ones stay one tap back).
    final seen = await StorySeen.get(widget.friendUserId);
    final start = (seen > 0 && seen < items.length) ? seen : 0;
    if (!mounted) return;

    Navigator.push(
      context,
      CircleRevealRoute(
        center: tapPosition,
        builder: (context) => FriendStoryViewer(
          items: items,
          username: widget.friendUsername,
          userId: widget.friendUserId,
          initialIndex: start,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTapDown: (details) => _openStory(details.globalPosition),
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: !widget.hasViewed ? Colors.cyan : Colors.grey[400]!,
                  width: !widget.hasViewed ? 4 : 3,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300],
                ),
                child: ClipOval(
                  child: _profilePicBase64 != null
                      ? Image.memory(
                    base64Decode(_profilePicBase64!),
                    fit: BoxFit.cover,
                    width: 102,
                    height: 102,
                    errorBuilder: (_, __, ___) => const _DefaultAvatar(size: 102),
                  )
                      : const _DefaultAvatar(size: 102),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 110,
            child: Text(
              widget.friendUsername,
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

// ─── Own story viewer (no progress bar) ──────────────────────────────────────

class OwnStoryViewer extends StatefulWidget {
  final List<StoryMediaItem> items;

  /// Which post to open on (the first one you haven't seen yet).
  final int initialIndex;

  const OwnStoryViewer({Key? key, required this.items, this.initialIndex = 0})
      : super(key: key);

  @override
  State<OwnStoryViewer> createState() => _OwnStoryViewerState();
}

class _OwnStoryViewerState extends State<OwnStoryViewer> {
  late int _currentIndex =
  widget.initialIndex.clamp(0, widget.items.length - 1);

  void _nextPhoto() {
    if (_currentIndex < widget.items.length - 1) {
      setState(() => _currentIndex++);
    } else {
      Navigator.pop(context);
    }
  }

  void _prevPhoto() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  @override
  Widget build(BuildContext context) {
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

            // Close button
            Positioned(
              top: 60,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),

            // Dot indicators (only if more than one item)
            if (widget.items.length > 1)
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.items.length, (i) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _currentIndex ? 10 : 6,
                      height: i == _currentIndex ? 10 : 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _currentIndex
                            ? Colors.white
                            : Colors.white.withOpacity(0.4),
                      ),
                    );
                  }),
                ),
              ),

            // Counter (only if more than one item)
            if (widget.items.length > 1)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '${_currentIndex + 1} of ${widget.items.length}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
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

  const FriendStoryViewer({
    Key? key,
    required this.items,
    required this.username,
    this.userId = '',
    this.initialIndex = 0,
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

  void _startProgress() {
    if (widget.userId.isNotEmpty) {
      StorySeen.set(widget.userId, _currentIndex + 1);
    }
    _progressController.reset();
    _progressController.forward().then((_) {
      if (mounted) _nextPhoto();
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

            // Progress bars
            Positioned(
              top: 60,
              left: 12,
              right: 12,
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
                            backgroundColor: Colors.white.withOpacity(0.4),
                            minHeight: 3,
                          ),
                        )
                            : LinearProgressIndicator(
                          value: i < _currentIndex ? 1.0 : 0.0,
                          valueColor:
                          const AlwaysStoppedAnimation(Colors.white),
                          backgroundColor: Colors.white.withOpacity(0.4),
                          minHeight: 3,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Username
            Positioned(
              top: 74,
              left: 16,
              child: Text(
                widget.username,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),

            // Close button
            Positioned(
              top: 60,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),

            // Counter
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '${_currentIndex + 1} of ${widget.items.length}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
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