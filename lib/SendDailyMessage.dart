import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'AppColors.dart';
import 'dart:io';
import 'ArchiveStorage.dart';
import 'SelectArchiveFolder.dart';
import 'SavedItemStorage.dart';
import 'MessageComments.dart';
import 'chat_reactions.dart';
import 'message_service.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'FeedService.dart';
import 'DailyShare.dart';
import 'Share.dart';
import 'AddToMyDaily.dart';
import 'UserProfileScreen.dart';
import 'MessageStorage.dart';
import 'GroupAvatar.dart';
import 'SafetyService.dart';
import 'SafetySheets.dart';
import 'MediaAspect.dart';
import 'DailyPostActivity.dart' show InlineVideo;
import 'DailyBan.dart';

/// One photo or video attached to a message. A message can carry several
/// of these — picking multiple items from the gallery grid at once
/// produces one message with several media items, shown as a swipeable
/// carousel, rather than several separate messages.
class DailyMediaItem {
  final String path; // local file path, or a Storage download URL once uploaded
  final bool isVideo;

  /// Videos only: a still frame, uploaded when the video is posted. It's
  /// what a Daily's cover shows when this video wins.
  final String? thumb;

  const DailyMediaItem({required this.path, required this.isVideo, this.thumb});

  Map<String, dynamic> toJson() => {
    'path': path,
    'is_video': isVideo,
    if (thumb != null) 'thumb': thumb,
  };

  factory DailyMediaItem.fromJson(Map<String, dynamic> json) => DailyMediaItem(
    path: json['path'] as String,
    isVideo: json['is_video'] as bool? ?? false,
    thumb: json['thumb'] as String?,
  );
}

class DailyMessage {
  final String? text;
  final List<DailyMediaItem> media;
  final DateTime timestamp;
  final String userId;
  final String messageId;
  final String dailyId;
  bool isSaved;
  final bool isFromPrompt;
  List<ChatReaction> reactions;
  final String? username;

  // Guarantees a unique id even for several messages constructed within
  // the same millisecond (e.g. building one per item in a loop) — a
  // plain millisecondsSinceEpoch string could collide there, and since
  // Firestore writes use this as the document id, a collision silently
  // overwrites one message with another.
  static int _idCounter = 0;
  static String _generateMessageId() {
    _idCounter++;
    return '${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }

  DailyMessage({
    this.text,
    String? imagePath,
    String? videoPath,
    List<DailyMediaItem>? media,
    required this.timestamp,
    String? userId,
    String? messageId,
    String? dailyId,
    this.isSaved = false,
    this.isFromPrompt = false,
    List<ChatReaction>? reactions,
    String? username,
  })  : media = media ??
      [
        if (imagePath != null) DailyMediaItem(path: imagePath, isVideo: false),
        if (videoPath != null) DailyMediaItem(path: videoPath, isVideo: true),
      ],
        userId = userId ?? 'current_user',
        messageId = messageId ?? _generateMessageId(),
        dailyId = dailyId ?? 'unknown_daily',
        reactions = reactions ?? [],
        username = username ?? 'You';

  // Backward-compat convenience getters — return the first image/video in
  // `media`, if any. Anything that only ever expected a single
  // image/video (older code, or a legacy saved message) keeps working
  // unchanged; it just won't show additional items in a multi-item
  // message.
  String? get imagePath {
    for (final m in media) {
      if (!m.isVideo) return m.path;
    }
    return null;
  }

  String? get videoPath {
    for (final m in media) {
      if (m.isVideo) return m.path;
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'user_id': userId,
      'daily_id': dailyId,
      'text': text,
      'media': media.map((m) => m.toJson()).toList(),
      // Legacy single-path fields, kept in sync with the first
      // image/video in `media`, for any older code reading them directly.
      'image_path': imagePath,
      'video_path': videoPath,
      'timestamp': timestamp.toIso8601String(),
      'is_saved': isSaved,
      'is_from_prompt': isFromPrompt,
      'reactions': reactions.map((r) => r.toJson()).toList(),
      'username': username,
    };
  }

  factory DailyMessage.fromJson(Map<String, dynamic> json) {
    List<DailyMediaItem> media;
    final rawMedia = json['media'] as List?;

    if (rawMedia != null && rawMedia.isNotEmpty) {
      media = rawMedia
          .map((m) => DailyMediaItem.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList();
    } else {
      // A message saved before the media list existed — fall back to its
      // old single image_path/video_path fields.
      media = [
        if (json['image_path'] != null)
          DailyMediaItem(path: json['image_path'], isVideo: false),
        if (json['video_path'] != null)
          DailyMediaItem(path: json['video_path'], isVideo: true),
      ];
    }

    return DailyMessage(
      text: json['text'],
      media: media,
      timestamp: DateTime.parse(json['timestamp']),
      userId: json['user_id'],
      messageId: json['message_id'],
      dailyId: json['daily_id'] ?? 'unknown_daily',
      isSaved: json['is_saved'] ?? false,
      isFromPrompt: json['is_from_prompt'] ?? false,
      reactions: _readReactions(json),
      username: json['username'],
    );
  }

  /// Reactions live in two places:
  ///  - `reactions`: the old list, from before reactions were saved one
  ///    person at a time
  ///  - `reactionsBy.{uid}`: one entry per person, written on its own so two
  ///    people reacting at once can't erase each other. `removed: true`
  ///    means that person took their reaction back.
  static List<ChatReaction> _readReactions(Map<String, dynamic> json) {
    final byUser = <String, ChatReaction>{};
    for (final r in (json['reactions'] as List?) ?? const []) {
      try {
        final reaction = ChatReaction.fromJson(r);
        byUser[reaction.userId] = reaction;
      } catch (_) {}
    }
    final map = json['reactionsBy'];
    if (map is Map) {
      map.forEach((uid, value) {
        if (value is! Map) return;
        if (value['removed'] == true) {
          byUser.remove('$uid');
          return;
        }
        final ts = value['timestamp'];
        byUser['$uid'] = ChatReaction(
          emoji: (value['emoji'] as String?) ?? '',
          userId: '$uid',
          username: (value['username'] as String?) ?? '',
          timestamp: ts is String
              ? (DateTime.tryParse(ts) ?? DateTime.now())
              : DateTime.now(),
        );
      });
    }
    return byUser.values.where((r) => r.emoji.isNotEmpty).toList();
  }

  bool get hasContent => (text != null && text!.trim().isNotEmpty) || media.isNotEmpty;

  bool isFromCurrentUser() => userId == 'current_user';

  int get reactionCount => reactions.length;

  bool get hasUserReacted => reactions.any((r) => r.userId == 'current_user');
}

/// True if a video message's path is a remote URL (e.g. a clip shared into
/// a Daily from Firebase Storage) rather than a local file path (e.g. a
/// video recorded/picked directly within the Daily).
bool _isNetworkVideoPath(String path) {
  return path.startsWith('http://') || path.startsWith('https://');
}

Widget _brokenMediaPlaceholder(double width) {
  return Container(
    width: width,
    height: 200,
    decoration: BoxDecoration(
      color: kc.grey(200),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image_outlined, size: 48, color: kc.grey(400)),
        const SizedBox(height: 8),
        Text(
          'Media no longer available',
          style: TextStyle(color: kc.grey(600), fontSize: 14),
        ),
      ],
    ),
  );
}

/// Swipeable carousel for a message with more than one photo/video —
/// same footprint (width, 9:16 aspect ratio) as a single-item message so
/// the bubble itself never changes size, just what's inside it. Dots at
/// the bottom track position; PageView's own physics-driven swipe is
/// what gives the smooth, glitch-free transition between items.
class _DailyMessageMediaCarousel extends StatefulWidget {
  final List<DailyMediaItem> media;
  final double width;

  const _DailyMessageMediaCarousel({required this.media, required this.width});

  @override
  State<_DailyMessageMediaCarousel> createState() => _DailyMessageMediaCarouselState();
}

class _DailyMessageMediaCarouselState extends State<_DailyMessageMediaCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildItem(DailyMediaItem item, bool isActive) {
    final path = LocalMediaAlias.resolve(item.path);
    if (item.isVideo) {
      return _CarouselVideoPage(
        key: ValueKey(path),
        path: path,
        isNetwork: _isNetworkVideoPath(path),
        isActive: isActive,
      );
    }

    return _isNetworkVideoPath(path)
        ? Image(
      image: CachedNetworkImageProvider(path),
      gaplessPlayback: true,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: kc.grey(200),
          child: Center(
            child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          _brokenMediaPlaceholder(widget.width),
    )
        : Image.file(
      File(path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) =>
          _brokenMediaPlaceholder(widget.width),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      child: SizedBox(
        width: widget.width,
        child: AspectRatio(
          // 4:5 — enough presence to matter without dominating the
          // thread the way a full story-style 9:16 would. Still needs to
          // be consistent across every page, or swiping between items
          // would visibly jump.
          aspectRatio: 4 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: widget.media.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) => _buildItem(widget.media[index], index == _currentPage),
              ),
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.media.length, (index) {
                    final isActive = index == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? kc.surface : Colors.white.withOpacity(0.4),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 2),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A video page within the carousel — self-contained (own
/// VideoPlayerController) so playback can be tied precisely to whether
/// this specific page is the one currently swiped to. Handles both a
/// local file and a network URL. Tap anywhere to play/pause manually.
class _CarouselVideoPage extends StatefulWidget {
  final String path;
  final bool isNetwork;
  final bool isActive;

  const _CarouselVideoPage({
    Key? key,
    required this.path,
    required this.isNetwork,
    required this.isActive,
  }) : super(key: key);

  @override
  State<_CarouselVideoPage> createState() => _CarouselVideoPageState();
}

class _CarouselVideoPageState extends State<_CarouselVideoPage> {
  VideoPlayerController? _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final controller = widget.isNetwork
        ? VideoPlayerController.networkUrl(Uri.parse(widget.path))
        : VideoPlayerController.file(File(widget.path));

    try {
      await controller.initialize();
      controller.setLooping(true);
      if (mounted) {
        setState(() => _controller = controller);
        // Only autoplay if this page is already the one being looked at
        // — matters when the carousel opens with a non-first page active
        // (not currently possible here, but keeps the logic correct).
        if (widget.isActive) controller.play();
      } else {
        controller.dispose();
      }
    } catch (e) {
      print('_CarouselVideoPage: init error: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void didUpdateWidget(covariant _CarouselVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive && _controller != null) {
      // Swiped to this page → play; swiped away → pause. This is the
      // actual fix for "sits on the first frame" — the old approach had
      // no concept of which page was actually being looked at.
      if (widget.isActive) {
        _controller!.play();
      } else {
        _controller!.pause();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Icon(Icons.error_outline, color: kc.grey(600), size: 40),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC)))),
      );
    }

    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          // Manual play/pause fallback — visible whenever paused, so
          // there's always a clear way to resume even if autoplay logic
          // above doesn't cover some edge case.
          if (!controller.value.isPlaying)
            const Center(
              child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 64),
            ),
        ],
      ),
    );
  }
}

class DailyMessageWidget extends StatefulWidget {
  final DailyMessage message;
  final bool isCurrentUser;
  final VoidCallback? onReply;
  final Function(String)? onEdit;
  final VoidCallback? onSaveToggle;
  final Function(String)? onReactionAdded;

  /// False for the 2nd, 3rd... message in a run from the same person — the
  /// group's first message already shows the name.
  final bool showUsername;

  /// True when this message continues a group, so it sits right against the
  /// one above it instead of leaving the usual gap.
  final bool groupedWithPrevious;

  /// The Daily this message lives in. When given, a "send to chat" button
  /// appears with the other message actions.
  final String? dailyTitle;
  final bool isPrivateDaily;

  /// The viewer is this Daily's owner or a moderator: they can delete
  /// anyone's post.
  final bool canModerate;

  /// ...and may ban this post's author (not the owner; moderators can't
  /// ban other moderators).
  final bool canBanAuthor;

  /// This is one of your Dailies (not a guest visit from For You): saving
  /// can keep a post "only in this Daily" (its Saved screen).
  final bool inMyDailies;

  const DailyMessageWidget({
    Key? key,
    required this.message,
    this.isCurrentUser = true,
    this.showUsername = true,
    this.groupedWithPrevious = false,
    this.dailyTitle,
    this.isPrivateDaily = false,
    this.canModerate = false,
    this.canBanAuthor = false,
    this.inMyDailies = true,
    this.onReply,
    this.onEdit,
    this.onSaveToggle,
    this.onReactionAdded,
  }) : super(key: key);

  @override
  State<DailyMessageWidget> createState() => _DailyMessageWidgetState();
}

class _DailyMessageWidgetState extends State<DailyMessageWidget> {
  bool _showComments = false;
  // Text messages: whether the react/comment/share/save row is open.
  bool _actionsExpanded = false;
  int _commentCount = 0;
  final MessageService _messageService = MessageService();

  @override
  void initState() {
    super.initState();
    _loadCommentCount();
    SavedItems.items.addListener(_savedChanged);
  }

  @override
  void dispose() {
    SavedItems.items.removeListener(_savedChanged);
    super.dispose();
  }

  /// Saved by YOU (each person's saves are their own).
  bool get _saved => SavedItems.isPostSaved(
      widget.message.dailyId, widget.message.messageId);

  void _savedChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCommentCount() async {
    final count = await CommentStorage.getCommentCount(
        widget.message.dailyId, widget.message.messageId);
    if (mounted) setState(() => _commentCount = count);
  }

  void _showReactionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: kc.grey(300),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ReactionPicker(
                  onReactionSelected: (emoji) {
                    _addReaction(emoji);
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addReaction(String emoji) {
    setState(() {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
      final existingIdx = widget.message.reactions.indexWhere(
              (r) => r.userId == currentUserId
      );

      if (existingIdx != -1) {
        // User already reacted - show message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can only react once per message'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Add new reaction
      widget.message.reactions.add(ChatReaction(
        emoji: emoji,
        userId: currentUserId,
        username: 'You',
        timestamp: DateTime.now(),
      ));
    });

    // Saves only this person's reaction, so it can't erase anyone else's.
    final me = FirebaseAuth.instance.currentUser;
    if (me != null) {
      MessageStorage.setReaction(
        dailyId: widget.message.dailyId,
        messageId: widget.message.messageId,
        userId: me.uid,
        username: me.displayName ?? widget.message.username ?? '',
        emoji: emoji,
      );
    }

    // The feed learns from what you react to.
    FeedService.recordEventForDailyId(
        widget.message.dailyId, FeedEvent.react);

    if (widget.onReactionAdded != null) {
      widget.onReactionAdded!(emoji);
    }
  }

  void _toggleReaction(String emoji, List<ChatReaction> reactions) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final userReaction = reactions.firstWhere(
          (r) => r.userId == currentUserId,
      orElse: () => ChatReaction(emoji: '', userId: '', username: '', timestamp: DateTime.now()),
    );

    if (userReaction.emoji.isNotEmpty) {
      if (userReaction.emoji == emoji) {
        // Tapped their own reaction - remove it
        setState(() {
          widget.message.reactions.removeWhere(
                  (r) => r.userId == currentUserId
          );
        });
        MessageStorage.removeReaction(
          dailyId: widget.message.dailyId,
          messageId: widget.message.messageId,
          userId: currentUserId,
        );

        if (widget.onReactionAdded != null) {
          widget.onReactionAdded!(emoji);
        }
      } else {
        // User already reacted with different emoji - show message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can only react once per message'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      // No existing reaction - add it
      _addReaction(emoji);
    }
  }

  /// Bookmark: saved already -> unsave. Otherwise "Save to…": folders,
  /// or (in your own Dailies) only in this Daily.
  Future<void> _toggleSave() async {
    final m = widget.message;
    final key = SavedItems.postKey(m.dailyId, m.messageId);
    final messenger = ScaffoldMessenger.of(context);
    void say(String t) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(t), duration: const Duration(seconds: 2)));

    if (_saved) {
      await SavedItems.unsave(key);
      say('Removed from saved');
    } else {
      await ArchiveStorage.loadFromStorage();
      if (!mounted) return;
      final picked = await showSaveToSheet(context,
          allowDailyOnly: widget.inMyDailies);
      if (picked == null) return;
      final ok = await SavedItems.savePost(
          dailyId: m.dailyId, messageId: m.messageId, archiveIds: picked);
      if (!ok) {
        say("Couldn't save. Try again.");
      } else if (picked.isEmpty) {
        say('Saved in this Daily');
      } else {
        final names = picked
            .map((id) => ArchiveStorage.byId(id)?.name)
            .whereType<String>()
            .toList();
        say(names.length == 1 ? 'Saved to ${names.first}' : 'Saved');
      }
    }
    if (widget.onSaveToggle != null) widget.onSaveToggle!();
  }

  void _handleReply() => setState(() => _showComments = !_showComments);

  /// Opens the Share sheet for this message (same one Clips uses): send it
  /// to a friend or group chat, add it to your own Daily, or share it out.
  void _shareToChat() {
    final m = widget.message;
    // Only media that's already uploaded (a URL) can be sent to a chat.
    final media = [
      for (final item in m.media)
        if (_isNetworkVideoPath(item.path))
          SharedMediaItem(url: item.path, isVideo: item.isVideo),
    ].take(6).toList();
    final text = (m.text ?? '').trim();

    if (text.isEmpty && media.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This is still uploading, try again in a moment'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final title = widget.dailyTitle ?? '';
    showShareSheet(
      context,
      daily: SharedDailyContent(
        dailyId: m.dailyId,
        dailyTitle: title,
        isPrivate: widget.isPrivateDaily,
        text: text,
        media: media,
      ),
      onAddToMyDaily: () => AddToMyDaily.fromDailyMessage(
        context,
        text: text,
        media: [for (final item in m.media) MyDailyMedia(item.path, item.isVideo)],
        authorUid: m.userId,
        authorName: m.username ?? '',
        dailyId: m.dailyId,
        dailyTitle: title,
        isPrivate: widget.isPrivateDaily,
      ),
    );
  }

  // ─── Shared pieces ─────────────────────────────────────────────────────────

  Widget _actionIcon({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    int count = 0,
    bool mirror = false,
  }) {
    final c = color ?? kc.grey(700);
    final glyph = Icon(icon, size: 20, color: c);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            mirror ? Transform.flip(flipX: true, child: glyph) : glyph,
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: kc.grey(700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// React and comment on the left; share and save on the right.
  Widget _buildActions() {
    return Row(
      children: [
        _actionIcon(
          icon: Icons.add_reaction_outlined,
          onTap: _showReactionPicker,
        ),
        _actionIcon(
          icon: _showComments
              ? Icons.mode_comment_rounded
              : Icons.mode_comment_outlined,
          color: _showComments ? Colors.cyan : null,
          onTap: _handleReply,
          count: _commentCount,
        ),
        const Spacer(),
        if (widget.dailyTitle != null)
        // Same share arrow as Clips.
          _actionIcon(
            icon: Icons.reply_rounded,
            mirror: true,
            onTap: _shareToChat,
          ),
        _actionIcon(
          icon: _saved ? Icons.bookmark : Icons.bookmark_border,
          color: _saved ? Colors.cyan : null,
          onTap: _toggleSave,
        ),
      ],
    );
  }

  Widget _buildUsername() {
    final uid = widget.message.userId;
    final canOpen = !widget.isCurrentUser &&
        uid.isNotEmpty &&
        uid != 'current_user' &&
        uid != FirebaseAuth.instance.currentUser?.uid;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canOpen
            ? () => UserProfileScreen.open(context, uid,
            username: widget.message.username)
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Their face, on the first message of each run only (that's
            // the only time this name line shows).
            MemberAvatar(
              userId: uid == 'current_user'
                  ? (FirebaseAuth.instance.currentUser?.uid ?? uid)
                  : uid,
              size: 20,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                widget.message.username ??
                    (widget.isCurrentUser ? 'You' : 'Unknown'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: kc.grey(700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Deletes this post for everyone, after a confirm. [asModerator] is the
  /// owner / a moderator removing someone else's post.
  Future<void> _confirmDelete({bool asModerator = false}) async {
    final name = widget.message.username ?? 'this person';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(asModerator ? 'Remove this post?' : 'Delete this post?'),
        content: Text(asModerator
            ? "It'll be removed for everyone in this Daily. $name won't be told."
            : "It'll be gone for everyone in this Daily."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: TextStyle(color: kc.text)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(asModerator ? 'Remove' : 'Delete',
                style: const TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final done = await MessageStorage.deleteMessage(
        widget.message.dailyId, widget.message.messageId);
    messenger.showSnackBar(SnackBar(
      content: Text(done
          ? (asModerator ? 'Post removed' : 'Post deleted')
          : "Couldn't delete it. Try again."),
      duration: const Duration(seconds: 2),
    ));
  }

  /// Long-press on any message, or the ⋯ on a photo/video. The author can edit or delete; anyone else gets
  /// report / block (plus remove and ban for the owner and moderators).
  void _showMessageOptions() {
    if (!widget.isCurrentUser) {
      _openSafetyMenu();
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: kc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onEdit?.call(widget.message.messageId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Someone else's post: report it or block them. The owner and
  /// moderators also get Remove post and Ban.
  void _openSafetyMenu() {
    final m = widget.message;
    final name = m.username ?? '';
    SafetyMenu.show(context, [
      if (widget.canModerate)
        SafetyMenuItem(
          icon: Icons.delete_outline,
          label: 'Remove post',
          subtitle: 'As a moderator',
          destructive: true,
          onTap: () => _confirmDelete(asModerator: true),
        ),
      if (widget.canBanAuthor)
        SafetyMenuItem(
          icon: Icons.gavel_rounded,
          label: name.isEmpty ? 'Ban from this Daily' : 'Ban $name from this Daily',
          destructive: true,
          onTap: () => DailyBanSheet.show(
            context,
            dailyId: m.dailyId,
            dailyTitle: widget.dailyTitle ?? 'this Daily',
            uid: m.userId,
            username: name.isEmpty ? 'this person' : name,
          ),
        ),
      SafetyMenuItem(
        icon: Icons.flag_outlined,
        label: 'Report post',
        destructive: true,
        onTap: () => ReportSheet.show(
          context,
          target: ReportTarget.dailyMessage,
          targetId: m.messageId,
          ownerUid: m.userId,
          ownerName: name,
          path: 'dailies/${m.dailyId}/daily_messages/${m.messageId}',
          preview: m.text,
          extra: {'dailyId': m.dailyId},
        ),
      ),
      SafetyMenuItem(
        icon: Icons.block_rounded,
        label: name.isEmpty ? 'Block' : 'Block $name',
        destructive: true,
        onTap: () =>
            BlockFlow.confirmAndBlock(context, m.userId, username: name),
      ),
    ]);
  }

  /// Someone you blocked: their post collapses to one quiet line.
  Widget _blockedPlaceholder() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Icon(Icons.block_rounded, size: 14, color: kc.grey(400)),
          const SizedBox(width: 6),
          Text('Post from someone you blocked',
              style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: kc.grey(500))),
        ],
      ),
    );
  }

  /// Text messages: a soft grey bubble only as wide as its words (yours get
  /// a faint cyan tint). The action row stays hidden, so quick back-and-forth
  /// reads like a chat, until the message has comments or reactions; then
  /// it's always there. Tapping a bubble opens or closes the row.
  static TextStyle get _bubbleTextStyle => TextStyle(
    fontSize: 15,
    color: kc.text,
    height: 1.3,
  );

  Color get _bubbleColor => widget.isCurrentUser
      ? (AppTheme.isDark ? kc.accentSoft : kc.adapt(const Color(0xFFE6F7FA)))
      : kc.adapt(const Color(0xFFF1F3F5));

  bool get _hasActivity =>
      _commentCount > 0 || widget.message.reactions.isNotEmpty;

  Widget _buildTextBubble(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.82;
    final text = widget.message.text ?? '';
    final showActions = _hasActivity || _actionsExpanded || _showComments;
    final reactions = widget.message.reactions;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, widget.groupedWithPrevious ? 2 : 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showUsername) _buildUsername(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _actionsExpanded = !_actionsExpanded),
            onLongPress: _showMessageOptions,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                // With the row open, wide enough for react/comment on the
                // left and share/save on the right.
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  minWidth: showActions ? 200 : 0,
                ),
                child: IntrinsicWidth(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _bubbleColor,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              14, 8, 14, showActions ? 2 : 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                  child: Text(text, style: _bubbleTextStyle)),
                              // Saved by you, while the row is closed.
                              if (_saved && !showActions) ...[
                                const SizedBox(width: 6),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 2),
                                  child: Icon(Icons.bookmark,
                                      size: 13, color: Colors.cyan),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (reactions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                            child: DailyMessageReactionsDisplay(
                              reactions: reactions,
                              currentUserId: 'current_user',
                              onReactionTap: (emoji) =>
                                  _toggleReaction(emoji, reactions),
                            ),
                          ),
                        if (showActions)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                            child: _buildActions(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Comments open under the message, as their own little card.
          if (_showComments)
            Container(
              width: maxWidth,
              margin: const EdgeInsets.only(top: 4),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: kc.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kc.adapt(const Color(0xFFE8EAED))),
              ),
              child: MessageCommentsSection(
                dailyId: widget.message.dailyId,
                messageId: widget.message.messageId,
                onCommentsChanged: _loadCommentCount,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SafetyService.instance.changes,
      builder: (context, _, __) {
        if (!widget.isCurrentUser &&
            SafetyService.instance.isBlocked(widget.message.userId)) {
          return _blockedPlaceholder();
        }
        return _buildCard(context);
      },
    );
  }

  Widget _buildCard(BuildContext context) {
    final media = widget.message.media;
    if (media.isEmpty) return _buildTextBubble(context);
    if (media.length > 1) return _buildMediaCard(context, null);
    // One photo or video: the card takes that photo's/video's shape.
    final only = media.first;
    return MediaAspectBuilder(
      path: LocalMediaAlias.resolve(only.path),
      isVideo: only.isVideo,
      thumb: only.thumb,
      builder: (context, aspect) => _buildMediaCard(context, aspect),
    );
  }

  /// The first photo/video, as the local file if this phone just posted it.
  String get _firstPath =>
      LocalMediaAlias.resolve(widget.message.media.first.path);

  Widget _buildMediaCard(BuildContext context, double? aspect) {
    final screen = MediaQuery.of(context).size;
    final maxWidth = screen.width * 0.85;
    final media = widget.message.media;
    final single = media.length == 1;
    // A tall video/photo gets a narrower card instead of a huge one or one
    // with empty space beside it; wide ones use the full width.
    final mediaSize = MediaAspect.box(aspect,
        maxW: maxWidth, maxH: screen.height * 0.55, minW: 220);
    final messageWidth = single ? mediaSize.width : maxWidth;
    final compact = messageWidth < 270;
    final caption = widget.message.text ?? '';
    final reactions = widget.message.reactions;

    Widget singleMedia() {
      final item = media.first;
      if (item.isVideo) {
        // Fills its box edge to edge, plays when on screen, ready ahead
        // of time. Works for a download URL or a still-uploading file.
        return SizedBox(
          width: mediaSize.width,
          height: mediaSize.height,
          child: ColoredBox(
            color: Colors.black,
            child: InlineVideo(
              key: ValueKey(_firstPath),
              url: _firstPath,
              thumb: item.thumb,
            ),
          ),
        );
      }
      return SizedBox(
        width: mediaSize.width,
        height: mediaSize.height,
        child: _isNetworkVideoPath(_firstPath)
            ? Image(
          image: CachedNetworkImageProvider(_firstPath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: kc.adapt(const Color(0xFFF1F3F5)),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: kc.grey(400)),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) =>
              _brokenMediaPlaceholder(messageWidth),
        )
            : Image.file(
          File(_firstPath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              _brokenMediaPlaceholder(messageWidth),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, widget.groupedWithPrevious ? 4 : 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showUsername) _buildUsername(),
          GestureDetector(
            onLongPress: _showMessageOptions,
            child: Container(
              width: messageWidth,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: kc.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kc.adapt(const Color(0xFFE8EAED))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      single
                          ? singleMedia()
                          : _DailyMessageMediaCarousel(
                        media: media,
                        width: messageWidth,
                      ),
                      // Edit / delete, or report / block (same as a
                      // long-press).
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _showMessageOptions,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.more_horiz_rounded,
                                size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Text(
                        caption,
                        style: TextStyle(
                          fontSize: compact ? 14.5 : 15,
                          color: kc.text,
                          height: 1.35,
                        ),
                      ),
                    ),
                  if (reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: DailyMessageReactionsDisplay(
                        reactions: reactions,
                        currentUserId: 'current_user',
                        onReactionTap: (emoji) =>
                            _toggleReaction(emoji, reactions),
                      ),
                    ),
                  // Posts always show their actions.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                    child: _buildActions(),
                  ),
                  if (_showComments)
                    MessageCommentsSection(
                      dailyId: widget.message.dailyId,
                      messageId: widget.message.messageId,
                      onCommentsChanged: _loadCommentCount,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// CUSTOM LARGER REACTIONS DISPLAY FOR DAILY MESSAGES
class DailyMessageReactionsDisplay extends StatelessWidget {
  final List<ChatReaction> reactions;
  final String currentUserId;
  final Function(String)? onReactionTap;

  const DailyMessageReactionsDisplay({
    Key? key,
    required this.reactions,
    required this.currentUserId,
    this.onReactionTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';

    // Group reactions by emoji
    Map<String, List<ChatReaction>> groupedReactions = {};
    for (var reaction in reactions) {
      groupedReactions.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: groupedReactions.entries.map((entry) {
        final emoji = entry.key;
        final reactionList = entry.value;
        final count = reactionList.length;
        final hasUserReacted = reactionList.any((r) => r.userId == currentUserId);

        return GestureDetector(
          onTap: onReactionTap != null ? () => onReactionTap!(emoji) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: hasUserReacted
                  ? Colors.cyan.withOpacity(0.12)
                  : kc.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasUserReacted
                    ? Colors.cyan.withOpacity(0.6)
                    : kc.adapt(const Color(0xFFE2E5E9)),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedReactionEmoji(emoji: emoji, size: 16),
                if (count > 1) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hasUserReacted ? Colors.cyan[800] : kc.grey(700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}