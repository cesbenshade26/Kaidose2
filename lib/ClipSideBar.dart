import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Share.dart';
import 'ArchiveStorage.dart';
import 'SavedItemStorage.dart';
import 'SendDailyMessage.dart';
import 'SelectArchiveFolder.dart';
import 'user_service.dart';
import 'FeedService.dart';
import 'SafetyService.dart';
import 'SafetySheets.dart';

typedef LikeTrigger = void Function();

class ClipSideBar extends StatefulWidget {
  final String clipId;

  /// The clip's creator — lets likes and shares teach the feed which
  /// creators the viewer likes.
  final String? creatorUid;
  final void Function(LikeTrigger)? onLikeTriggerReady;
  final VoidCallback? onCommentTap;
  final VoidCallback? onShareTap;

  /// The clip should leave the feed: "Not interested" (false) or its
  /// creator was blocked (true: drop all their clips).
  final void Function(bool wholeCreator)? onHidden;

  /// The clip's caption, kept with a report so it can be reviewed.
  final String? caption;

  const ClipSideBar({
    Key? key,
    required this.clipId,
    this.creatorUid,
    this.onLikeTriggerReady,
    this.onCommentTap,
    this.onShareTap,
    this.onHidden,
    this.caption,
  }) : super(key: key);

  @override
  State<ClipSideBar> createState() => _ClipSideBarState();
}

class _ClipSideBarState extends State<ClipSideBar>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  bool _liked = false;
  int _likeCount = 0;
  int _commentCount = 0;
  bool _loadingLike = false;
  bool _isSaving = false;
  bool _isSaved = false;

  // The heart's "pop" when liked (squish, overshoot, settle) and a small
  // dip when unliked. Nullable so dispose() is safe even if initState
  // didn't finish.
  AnimationController? _popController;
  Animation<double>? _likeScale;
  Animation<double>? _unlikeScale;
  bool _poppingLike = true;

  @override
  void initState() {
    super.initState();

    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _likeScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.72)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 18),
      TweenSequenceItem(
          tween: Tween(begin: 0.72, end: 1.28)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 32),
      TweenSequenceItem(
          tween: Tween(begin: 1.28, end: 0.94)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 25),
      TweenSequenceItem(
          tween: Tween(begin: 0.94, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 25),
    ]).animate(_popController!);
    _unlikeScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.82), weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 0.82, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 60),
    ]).animate(_popController!);

    _loadLikeState();
    widget.onLikeTriggerReady?.call(triggerLike);
  }

  @override
  void dispose() {
    _popController?.dispose();
    super.dispose();
  }

  Future<void> _loadLikeState() async {
    if (_uid == null) return;
    try {
      final clipDoc =
      await _firestore.collection('clips').doc(widget.clipId).get();
      final likeCount = clipDoc.data()?['likeCount'] ?? 0;
      final commentCount = clipDoc.data()?['commentCount'] ?? 0;
      final likeDoc = await _firestore
          .collection('clips')
          .doc(widget.clipId)
          .collection('likes')
          .doc(_uid)
          .get();
      if (mounted) {
        setState(() {
          _likeCount = likeCount;
          _commentCount = commentCount is num ? commentCount.toInt() : 0;
          _liked = likeDoc.exists;
        });
      }
    } catch (e) {
      print('ClipSideBar: error loading like state: $e');
    }
  }

  /// Like / unlike. The heart changes (and pops) the instant it's tapped;
  /// the save happens behind it and is undone on screen if it fails.
  Future<void> triggerLike() async {
    if (_uid == null || _loadingLike) return;
    final wasLiked = _liked;

    _poppingLike = !wasLiked;
    _popController?.forward(from: 0);
    setState(() {
      _loadingLike = true;
      _liked = !wasLiked;
      _likeCount = wasLiked
          ? (_likeCount - 1).clamp(0, 999999999)
          : _likeCount + 1;
    });

    try {
      final likeRef = _firestore
          .collection('clips')
          .doc(widget.clipId)
          .collection('likes')
          .doc(_uid);
      final clipRef = _firestore.collection('clips').doc(widget.clipId);

      if (wasLiked) {
        await likeRef.delete();
        await clipRef.update({'likeCount': FieldValue.increment(-1)});
      } else {
        await likeRef.set({'likedAt': FieldValue.serverTimestamp()});
        await clipRef.update({'likeCount': FieldValue.increment(1)});
        if (widget.creatorUid != null) {
          FeedService.recordClipEvent(
              creatorUid: widget.creatorUid!,
              event: ClipEvent.like,
              clipId: widget.clipId);
        }
      }
    } catch (e) {
      print('ClipSideBar: like error: $e');
      // Put it back the way it was.
      if (mounted) {
        setState(() {
          _liked = wasLiked;
          _likeCount = wasLiked
              ? _likeCount + 1
              : (_likeCount - 1).clamp(0, 999999999);
        });
      }
    } finally {
      if (mounted) setState(() => _loadingLike = false);
    }
  }

  void _handleShareTap() {
    // Shares count toward the clip's quality in the feed.
    _firestore
        .collection('clips')
        .doc(widget.clipId)
        .update({'shareCount': FieldValue.increment(1)})
        .catchError((e) => print('ClipSideBar: share count error: $e'));
    if (widget.creatorUid != null) {
      FeedService.recordClipEvent(
          creatorUid: widget.creatorUid!,
          event: ClipEvent.share,
          clipId: widget.clipId);
    }
    if (widget.onShareTap != null) {
      // Lets whatever screen hosts this sidebar apply the same
      // dilate/move-up treatment it already uses for comments.
      widget.onShareTap!();
    } else {
      // Fallback: open the sheet directly with no dilation.
      showShareSheet(context, clipId: widget.clipId);
    }
  }

  Future<void> _handleSaveTap() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await ArchiveStorage.loadFromStorage();
      final archives = ArchiveStorage.archives;

      final clipDoc = await _firestore.collection('clips').doc(widget.clipId).get();
      if (!clipDoc.exists) {
        throw Exception('Clip not found');
      }

      final data = clipDoc.data()!;
      final videoUrl = data['videoUrl'] as String? ?? '';
      final caption = data['caption'] as String? ?? '';

      if (videoUrl.isEmpty) {
        throw Exception('Clip has no video URL');
      }

      String username = 'You';
      if (_uid != null) {
        final user = await UserService().getUserById(_uid!);
        if (user?.username != null && user!.username.isNotEmpty) {
          username = user.username;
        }
      }

      // messageId is the clip's own id, so re-saving the same clip
      // naturally dedupes via SavedItemStorage's existing check.
      final message = DailyMessage(
        text: caption.isNotEmpty ? caption : null,
        videoPath: videoUrl,
        timestamp: DateTime.now(),
        messageId: widget.clipId,
        dailyId: 'clip',
        userId: _uid ?? 'current_user',
        username: username,
      );

      if (archives.length == 1) {
        await SavedItemStorage.saveItem(archives[0].id, message);
        if (mounted) {
          setState(() => _isSaved = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to ${archives[0].name}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (mounted) {
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => SelectArchiveFolderScreen(
              message: message,
              showDailyOption: false,
            ),
          ),
        );
        if (saved == true && mounted) {
          setState(() => _isSaved = true);
        }
      }
    } catch (e) {
      print('ClipSideBar: save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving clip: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatCount(int count) {
    if (count == 0) return '0';
    if (count >= 1000000) {
      final m = count / 1000000;
      return m == m.truncateToDouble()
          ? '${m.toInt()}M'
          : '${m.toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      final k = count / 1000;
      return k == k.truncateToDouble()
          ? '${k.toInt()}K'
          : '${k.toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Tight, even spacing; a 44px tap area for every button; a count only
    // under the buttons that have one.
    const gap = SizedBox(height: 6);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like: the heart squishes, pops past full size and settles as it
        // fills in; unliking gives a small dip.
        _SideButton(
          label: _formatCount(_likeCount),
          onTap: triggerLike,
          child: AnimatedBuilder(
            animation: _popController ?? const AlwaysStoppedAnimation(0.0),
            builder: (context, child) {
              final anim = _poppingLike ? _likeScale : _unlikeScale;
              return Transform.scale(scale: anim?.value ?? 1.0, child: child);
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Icon(
                _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(_liked),
                color: _liked ? const Color(0xFFFF3B5C) : Colors.white,
                size: 32,
                shadows: _iconShadow,
              ),
            ),
          ),
        ),
        gap,

        // Comment
        _SideButton(
          label: _formatCount(_commentCount),
          onTap: widget.onCommentTap,
          child: const Icon(Icons.chat_bubble_outline_rounded,
              color: Colors.white, size: 29, shadows: _iconShadow),
        ),
        gap,

        // Share
        _SideButton(
          onTap: _handleShareTap,
          // A forward arrow (the reply arrow, mirrored).
          child: Transform.flip(
            flipX: true,
            child: const Icon(Icons.reply_rounded,
                color: Colors.white, size: 32, shadows: _iconShadow),
          ),
        ),
        gap,

        // Save
        _SideButton(
          onTap: _handleSaveTap,
          child: _isSaving
              ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2.5),
          )
              : Icon(
            _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: Colors.white,
            size: 30,
            shadows: _iconShadow,
          ),
        ),

        // More: Not interested / Report / Block (other people's clips)
        if (widget.creatorUid != null &&
            widget.creatorUid!.isNotEmpty &&
            widget.creatorUid != _uid) ...[
          gap,
          _SideButton(
            onTap: _openMore,
            child: const Icon(Icons.more_horiz_rounded,
                color: Colors.white, size: 30, shadows: _iconShadow),
          ),
        ],
      ],
    );
  }
}

extension _ClipMoreMenu on _ClipSideBarState {
  /// "⋯": Not interested, Report, Block (only on other people's clips).
  void _openMore() {
    final creator = widget.creatorUid ?? '';
    SafetyMenu.show(context, [
      SafetyMenuItem(
        icon: Icons.not_interested_rounded,
        label: 'Not interested',
        subtitle: "You'll see fewer clips like this",
        onTap: () {
          SafetyService.instance
              .notInterestedIn(clipId: widget.clipId, creatorUid: creator);
          widget.onHidden?.call(false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Got it. You'll see fewer clips like this."),
            backgroundColor: Colors.black87,
            duration: Duration(seconds: 2),
          ));
        },
      ),
      SafetyMenuItem(
        icon: Icons.flag_outlined,
        label: 'Report clip',
        destructive: true,
        onTap: () async {
          await ReportSheet.show(
            context,
            target: ReportTarget.clip,
            targetId: widget.clipId,
            ownerUid: creator,
            path: 'clips/${widget.clipId}',
            preview: widget.caption,
          );
          if (SafetyService.instance.isBlocked(creator)) {
            widget.onHidden?.call(true);
          }
        },
      ),
      SafetyMenuItem(
        icon: Icons.block_rounded,
        label: 'Block creator',
        destructive: true,
        onTap: () async {
          if (await BlockFlow.confirmAndBlock(context, creator)) {
            widget.onHidden?.call(true);
          }
        },
      ),
    ]);
  }
}

// Soft shadow so white icons stay visible on bright clips.
const List<Shadow> _iconShadow = [Shadow(color: Colors.black45, blurRadius: 6)];

// ─── Side button ──────────────────────────────────────────────────────────────

/// One side bar button: a 44x44 tap area with the icon centered, and its
/// count right under it when there is one.
class _SideButton extends StatelessWidget {
  final Widget child;
  final String label;
  final VoidCallback? onTap;

  const _SideButton({required this.child, this.label = '', this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 44, height: 40, child: Center(child: child)),
          if (label.isNotEmpty)
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.0,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
        ],
      ),
    );
  }
}