import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'friend_request_service.dart';
import 'FriendDailyService.dart';
import 'ProfilePicManager.dart';

class StoryBar extends StatefulWidget {
  final VoidCallback onTapOwnStory;
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
  final VoidCallback onTap;
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
            onTap: hasPhotos ? onTap : null,
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

  void _openStory() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final photos = await FriendDailyService.getFriendStoryPhotos(widget.friendUserId);
    if (!mounted) return;
    if (photos.isEmpty) return;

    await FriendDailyService.markStoryViewed(widget.friendUserId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FriendStoryViewer(
          photos: photos,
          username: widget.friendUsername,
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
            onTap: _openStory,
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

// ─── Shared blurred-background photo view ────────────────────────────────────

/// Blurred, color-matched background like Instagram stories.
/// The photo itself has rounded corners and slight horizontal padding
/// so it doesn't touch the screen edges.
class StoryPhotoView extends StatelessWidget {
  final File photo;

  const StoryPhotoView({Key? key, required this.photo}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred background — same image scaled to cover full screen
        Image.file(
          photo,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => Container(color: Colors.black),
        ),
        // Heavy blur + dark tint over the background
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            color: Colors.black.withOpacity(0.35),
          ),
        ),
        // Actual photo — padded, rounded corners, fills width minus margins
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                photo,
                fit: BoxFit.fitWidth,
                width: double.infinity,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.error_outline,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Own story viewer (no progress bar) ──────────────────────────────────────

class OwnStoryViewer extends StatefulWidget {
  final List<File> photos;

  const OwnStoryViewer({Key? key, required this.photos}) : super(key: key);

  @override
  State<OwnStoryViewer> createState() => _OwnStoryViewerState();
}

class _OwnStoryViewerState extends State<OwnStoryViewer> {
  int _currentIndex = 0;

  void _nextPhoto() {
    if (_currentIndex < widget.photos.length - 1) {
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
            // Blurred background + rounded photo
            Positioned.fill(
              child: StoryPhotoView(photo: widget.photos[_currentIndex]),
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

            // Dot indicators (only if more than one photo)
            if (widget.photos.length > 1)
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.photos.length, (i) {
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

            // Photo counter (only if more than one photo)
            if (widget.photos.length > 1)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '${_currentIndex + 1} of ${widget.photos.length}',
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
  final List<File> photos;
  final String username;

  const FriendStoryViewer({
    Key? key,
    required this.photos,
    required this.username,
  }) : super(key: key);

  @override
  State<FriendStoryViewer> createState() => _FriendStoryViewerState();
}

class _FriendStoryViewerState extends State<FriendStoryViewer>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _progressController;
  static const Duration _photoDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this, duration: _photoDuration);
    _startProgress();
  }

  void _startProgress() {
    _progressController.reset();
    _progressController.forward().then((_) {
      if (mounted) _nextPhoto();
    });
  }

  void _nextPhoto() {
    if (_currentIndex < widget.photos.length - 1) {
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
            // Blurred background + rounded photo
            Positioned.fill(
              child: StoryPhotoView(photo: widget.photos[_currentIndex]),
            ),

            // Progress bars
            Positioned(
              top: 60,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(widget.photos.length, (i) {
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

            // Photo counter
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '${_currentIndex + 1} of ${widget.photos.length}',
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