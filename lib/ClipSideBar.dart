import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import 'Share.dart';
import 'ArchiveStorage.dart';
import 'SavedItemStorage.dart';
import 'SendDailyMessage.dart';
import 'SelectArchiveFolder.dart';
import 'user_service.dart';
import 'ClipFeed.dart';
import 'FeedService.dart';

typedef LikeTrigger = void Function();

class ClipSideBar extends StatefulWidget {
  final String clipId;

  /// The clip's creator — lets likes and shares teach the feed which
  /// creators the viewer likes.
  final String? creatorUid;
  final void Function(LikeTrigger)? onLikeTriggerReady;
  final VoidCallback? onCommentTap;
  final VoidCallback? onShareTap;

  const ClipSideBar({
    Key? key,
    required this.clipId,
    this.creatorUid,
    this.onLikeTriggerReady,
    this.onCommentTap,
    this.onShareTap,
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
  bool _loadingLike = false;
  bool _isSaving = false;
  bool _isSaved = false;

  // Nullable so dispose() is safe even if initState didn't finish
  AnimationController? _burstController;
  Animation<double>? _burstScale;
  Animation<double>? _burstOpacity;

  @override
  void initState() {
    super.initState();

    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _burstScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _burstController!,
          curve: Curves.easeOut),
    );
    _burstOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _burstController!,
          curve: const Interval(0.5, 1.0, curve: Curves.easeIn)),
    );

    _loadLikeState();
    widget.onLikeTriggerReady?.call(triggerLike);
  }

  @override
  void dispose() {
    _burstController?.dispose();
    super.dispose();
  }

  Future<void> _loadLikeState() async {
    if (_uid == null) return;
    try {
      final clipDoc =
      await _firestore.collection('clips').doc(widget.clipId).get();
      final likeCount = clipDoc.data()?['likeCount'] ?? 0;
      final likeDoc = await _firestore
          .collection('clips')
          .doc(widget.clipId)
          .collection('likes')
          .doc(_uid)
          .get();
      if (mounted) {
        setState(() {
          _likeCount = likeCount;
          _liked = likeDoc.exists;
        });
      }
    } catch (e) {
      print('ClipSideBar: error loading like state: $e');
    }
  }

  Future<void> triggerLike() async {
    if (_uid == null || _loadingLike) return;

    if (!_liked) {
      _burstController?.forward(from: 0);
    }

    setState(() => _loadingLike = true);
    try {
      final likeRef = _firestore
          .collection('clips')
          .doc(widget.clipId)
          .collection('likes')
          .doc(_uid);
      final clipRef = _firestore.collection('clips').doc(widget.clipId);

      if (_liked) {
        await likeRef.delete();
        await clipRef.update({'likeCount': FieldValue.increment(-1)});
        if (mounted) {
          setState(() {
            _liked = false;
            _likeCount = (_likeCount - 1).clamp(0, 999999999);
          });
        }
      } else {
        await likeRef.set({'likedAt': FieldValue.serverTimestamp()});
        await clipRef.update({'likeCount': FieldValue.increment(1)});
        if (mounted) {
          setState(() {
            _liked = true;
            _likeCount += 1;
          });
        }
        if (widget.creatorUid != null) {
          FeedService.recordClipEvent(
              creatorUid: widget.creatorUid!,
              event: ClipEvent.like,
              clipId: widget.clipId);
        }
      }
    } catch (e) {
      print('ClipSideBar: like error: $e');
    } finally {
      if (mounted) setState(() => _loadingLike = false);
    }
  }

  void _handleShareTap() {
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like button + spark burst
        _SideButton(
          label: _formatCount(_likeCount),
          child: GestureDetector(
            onTap: triggerLike,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Spark burst
                  if (_burstController != null)
                    AnimatedBuilder(
                      animation:
                      _burstController ?? const AlwaysStoppedAnimation(0),
                      builder: (context, child) {
                        return Opacity(
                          opacity: _burstOpacity?.value ?? 0,
                          child: CustomPaint(
                            size: const Size(44, 44),
                            painter: _SparkPainter(
                                progress: _burstScale?.value ?? 0),
                          ),
                        );
                      },
                    ),
                  // Heart icon
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _liked ? Icons.favorite : Icons.favorite_border,
                      key: ValueKey(_liked),
                      color: _liked ? Colors.red : Colors.white,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Comment
        _SideButton(
          label: '0',
          child: GestureDetector(
            onTap: widget.onCommentTap,
            child: const Icon(Icons.chat_bubble_outline,
                color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 20),

        // Share
        _SideButton(
          label: '',
          child: GestureDetector(
            onTap: _handleShareTap,
            child: const Icon(Icons.reply, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 20),

        // Save
        _SideButton(
          label: '',
          child: GestureDetector(
            onTap: _handleSaveTap,
            child: _isSaving
                ? const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            )
                : Icon(
              _isSaved ? Icons.bookmark : Icons.bookmark_border,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Feed preferences
        _SideButton(
          label: '',
          child: GestureDetector(
            onTap: () => showClipFeedPreferencesSheet(context),
            child: const Icon(Icons.tune, color: Colors.white, size: 26),
          ),
        ),
      ],
    );
  }
}

// ─── Spark painter ────────────────────────────────────────────────────────────

class _SparkPainter extends CustomPainter {
  final double progress;
  static const int _sparkCount = 8;

  const _SparkPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    const minRadius = 16.0;
    const maxRadius = 24.0;
    const sparkLength = 8.0;

    for (int i = 0; i < _sparkCount; i++) {
      final angle = (2 * math.pi / _sparkCount) * i;
      final innerRadius = minRadius + (maxRadius - minRadius) * progress;
      final outerRadius = innerRadius + sparkLength * progress;

      final start = Offset(
        center.dx + innerRadius * math.cos(angle),
        center.dy + innerRadius * math.sin(angle),
      );
      final end = Offset(
        center.dx + outerRadius * math.cos(angle),
        center.dy + outerRadius * math.sin(angle),
      );

      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─── Side button with fixed label slot ───────────────────────────────────────

class _SideButton extends StatelessWidget {
  final Widget child;
  final String label;

  const _SideButton({required this.child, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 4),
        SizedBox(
          height: 16,
          child: label.isNotEmpty
              ? Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          )
              : null,
        ),
      ],
    );
  }
}