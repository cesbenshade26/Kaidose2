import 'package:flutter/material.dart';
import 'dart:io';
import 'ArchiveStorage.dart';
import 'SelectArchiveFolder.dart';
import 'SavedItemStorage.dart';
import 'MessageComments.dart';
import 'chat_reactions.dart';
import 'message_service.dart';
import 'package:video_player/video_player.dart';
import 'VideoClipPlayer.dart';
import 'NetworkVideoPlayer.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'FeedService.dart';
import 'DailyShare.dart';
import 'UserProfileScreen.dart';

/// One photo or video attached to a message. A message can carry several
/// of these — picking multiple items from the gallery grid at once
/// produces one message with several media items, shown as a swipeable
/// carousel, rather than several separate messages.
class DailyMediaItem {
  final String path; // local file path, or a Storage download URL once uploaded
  final bool isVideo;

  const DailyMediaItem({required this.path, required this.isVideo});

  Map<String, dynamic> toJson() => {'path': path, 'is_video': isVideo};

  factory DailyMediaItem.fromJson(Map<String, dynamic> json) => DailyMediaItem(
    path: json['path'] as String,
    isVideo: json['is_video'] as bool? ?? false,
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
      reactions: (json['reactions'] as List?)
          ?.map((r) => ChatReaction.fromJson(r))
          .toList() ?? [],
      username: json['username'],
    );
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
      color: Colors.grey[200],
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey[400]),
        const SizedBox(height: 8),
        Text(
          'Media no longer available',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
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
    if (item.isVideo) {
      return _CarouselVideoPage(
        path: item.path,
        isNetwork: _isNetworkVideoPath(item.path),
        isActive: isActive,
      );
    }

    return _isNetworkVideoPath(item.path)
        ? Image.network(
      item.path,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.grey[200],
          child: const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          _brokenMediaPlaceholder(widget.width),
    )
        : Image.file(
      File(item.path),
      fit: BoxFit.cover,
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
                        color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
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
    required this.path,
    required this.isNetwork,
    required this.isActive,
  });

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
          child: Icon(Icons.error_outline, color: Colors.grey[600], size: 40),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.cyan)),
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

  const DailyMessageWidget({
    Key? key,
    required this.message,
    this.isCurrentUser = true,
    this.showUsername = true,
    this.groupedWithPrevious = false,
    this.dailyTitle,
    this.isPrivateDaily = false,
    this.onReply,
    this.onEdit,
    this.onSaveToggle,
    this.onReactionAdded,
  }) : super(key: key);

  @override
  State<DailyMessageWidget> createState() => _DailyMessageWidgetState();
}

class _DailyMessageWidgetState extends State<DailyMessageWidget> {
  bool _showOptionsMenu = false;
  bool _showComments = false;
  // Short text messages only: whether the react/comment/save row is open.
  bool _actionsExpanded = false;
  int _commentCount = 0;
  final MessageService _messageService = MessageService();

  @override
  void initState() {
    super.initState();
    _loadCommentCount();
  }

  Future<void> _loadCommentCount() async {
    final count = await CommentStorage.getCommentCount(widget.message.messageId);
    if (mounted) setState(() => _commentCount = count);
  }

  void _showReactionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
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
                    color: Colors.grey[300],
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

  void _toggleSave() async {
    setState(() => widget.message.isSaved = !widget.message.isSaved);
    if (widget.message.isSaved) {
      await ArchiveStorage.loadFromStorage();
      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SelectArchiveFolderScreen(message: widget.message),
          ),
        );
      }
    }
    if (widget.onSaveToggle != null) widget.onSaveToggle!();
  }

  void _handleReply() => setState(() => _showComments = !_showComments);

  /// Opens the "send to chat" sheet for this message.
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
    ShareToChatSheet.show(
      context,
      SharedDailyContent(
        dailyId: m.dailyId,
        dailyTitle: widget.dailyTitle ?? '',
        isPrivate: widget.isPrivateDaily,
        text: text,
        media: media,
      ),
    );
  }

  void _toggleOptionsMenu() => setState(() => _showOptionsMenu = !_showOptionsMenu);

  // ─── Shared pieces ─────────────────────────────────────────────────────────

  Widget _actionIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int count = 0,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Text(
                '$count',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// React, comment, save — kept together at the left edge so they line up
  /// down the screen no matter how long each message is.
  Widget _buildActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actionIcon(
          icon: Icons.add_reaction_outlined,
          color: Colors.grey[600]!,
          onTap: _showReactionPicker,
        ),
        _actionIcon(
          icon: Icons.comment_outlined,
          color: Colors.grey[600]!,
          onTap: _handleReply,
          count: _commentCount,
        ),
        _actionIcon(
          icon: widget.message.isSaved ? Icons.bookmark : Icons.bookmark_border,
          color: widget.message.isSaved ? Colors.cyan : Colors.grey[600]!,
          onTap: _toggleSave,
        ),
        if (widget.dailyTitle != null)
          _actionIcon(
            icon: Icons.send_outlined,
            color: Colors.grey[600]!,
            onTap: _shareToChat,
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
      padding: const EdgeInsets.only(left: 6, bottom: 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canOpen
            ? () => UserProfileScreen.open(context, uid,
            username: widget.message.username)
            : null,
        child: Text(
          widget.message.username ?? (widget.isCurrentUser ? 'You' : 'Unknown'),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey[600],
          ),
        ),
      ),
    );
  }

  /// Long-press on a text message (the three-dot button only exists on
  /// media cards now). Only the author gets anything to do.
  void _showMessageOptions() {
    if (!widget.isCurrentUser) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
          ],
        ),
      ),
    );
  }

  /// Text-only messages: a bubble that is only as wide as its content
  /// (capped at 85% of the screen), text on top, actions below it, no date.
  static const TextStyle _bubbleTextStyle = TextStyle(
    fontSize: 15,
    color: Colors.black87,
    height: 1.3,
  );

  // Roughly the width of the react/comment/save row.
  static const double _actionsRowWidth = 118;

  /// A message is "short" when it is a single line narrower than the
  /// actions row — those get a bare pill that opens on tap, since the
  /// icons would otherwise be bigger than the message itself.
  bool _isShortText(String text, double maxWidth) {
    if (text.contains('\n')) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _bubbleTextStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth - 28);
    return !painter.didExceedMaxLines && painter.width < _actionsRowWidth;
  }

  /// What a collapsed short message still shows without a tap, trailing its
  /// text on the same line: a comment count and/or a saved bookmark.
  Widget _buildCollapsedState() {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_commentCount > 0) ...[
            Icon(Icons.comment_outlined, size: 13, color: Colors.grey[600]),
            const SizedBox(width: 3),
            Text('$_commentCount',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
          if (_commentCount > 0 && widget.message.isSaved)
            const SizedBox(width: 8),
          if (widget.message.isSaved)
            const Icon(Icons.bookmark, size: 13, color: Colors.cyan),
        ],
      ),
    );
  }

  Widget _buildTextBubble(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.85;
    final text = widget.message.text ?? '';
    final isShort = _isShortText(text, maxWidth);
    // Long messages always show their actions; short ones only when opened
    // (or while their comments are showing, which need the row open).
    final showActions = !isShort || _actionsExpanded || _showComments;
    final hasCollapsedState =
        isShort && !showActions && (_commentCount > 0 || widget.message.isSaved);

    return Container(
      margin: EdgeInsets.fromLTRB(16, widget.groupedWithPrevious ? 1 : 5, 16, 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showUsername) _buildUsername(),
          GestureDetector(
            onLongPress: _showMessageOptions,
            onTap: isShort
                ? () => setState(() => _actionsExpanded = !_actionsExpanded)
                : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.cyan.withOpacity(0.35), width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isShort)
                      // One line: whatever trails the text (the open action
                      // row, or the small comment/saved markers) sits to its
                      // right, so opening it never pushes the messages below
                      // down — important when messages are stacked tight.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(14, 7,
                                  (showActions || hasCollapsedState) ? 8 : 14, 7),
                              child: Text(text, style: _bubbleTextStyle),
                            ),
                            if (showActions)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _buildActions(),
                              )
                            else if (hasCollapsedState)
                              _buildCollapsedState(),
                          ],
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 7, 14, 0),
                          child: Text(text, style: _bubbleTextStyle),
                        ),
                        // Flush left under the text, so the bubble is only as
                        // wide as the text.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(9, 0, 14, 1),
                          child: _buildActions(),
                        ),
                      ],
                      if (widget.message.reactions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                          child: DailyMessageReactionsDisplay(
                            reactions: widget.message.reactions,
                            currentUserId: 'current_user',
                            onReactionTap: (emoji) =>
                                _toggleReaction(emoji, widget.message.reactions),
                          ),
                        ),
                      if (_showComments)
                        SizedBox(
                          width: maxWidth,
                          child: MessageCommentsSection(
                            messageId: widget.message.messageId,
                            onCommentsChanged: _loadCommentCount,
                          ),
                        ),
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

  @override
  Widget build(BuildContext context) {
    if (widget.message.media.isEmpty) return _buildTextBubble(context);

    final screenWidth = MediaQuery.of(context).size.width;
    final messageWidth = screenWidth * 0.85;

    return Container(
      margin: EdgeInsets.fromLTRB(16, widget.groupedWithPrevious ? 2 : 6, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showUsername) _buildUsername(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: messageWidth,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.cyan.withOpacity(0.35), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyan.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.message.media.length == 1 && !widget.message.media.first.isVideo)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        child: _isNetworkVideoPath(widget.message.media.first.path)
                            ? Image.network(
                          widget.message.media.first.path,
                          width: messageWidth,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              width: messageWidth,
                              height: 200,
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(color: Colors.cyan),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) =>
                              _brokenMediaPlaceholder(messageWidth),
                        )
                            : Image.file(
                          File(widget.message.media.first.path),
                          width: messageWidth,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _brokenMediaPlaceholder(messageWidth),
                        ),
                      ),
                    if (widget.message.media.length == 1 && widget.message.media.first.isVideo)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        child: SizedBox(
                          width: messageWidth,
                          child: AspectRatio(
                            aspectRatio: 4 / 5,
                            // A shared clip's videoPath is a remote Firebase
                            // Storage URL; a video recorded/picked directly in
                            // the Daily is a local file path. Route each to
                            // the player that can actually handle it.
                            child: _isNetworkVideoPath(widget.message.media.first.path)
                                ? NetworkVideoPlayer(url: widget.message.media.first.path)
                                : VideoClipPlayer(
                              videoFile: File(widget.message.media.first.path),
                              autoPlay: true,
                              looping: true,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    if (widget.message.media.length > 1)
                      _DailyMessageMediaCarousel(
                        media: widget.message.media,
                        width: messageWidth,
                      ),
                    if (widget.message.text != null && widget.message.text!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          widget.message.text!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),

                    if (widget.message.reactions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: DailyMessageReactionsDisplay(
                          reactions: widget.message.reactions,
                          currentUserId: 'current_user',
                          onReactionTap: (emoji) => _toggleReaction(emoji, widget.message.reactions),
                        ),
                      ),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.04),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildActions(),
                      ),
                    ),
                    if (_showComments)
                      MessageCommentsSection(
                        messageId: widget.message.messageId,
                        onCommentsChanged: _loadCommentCount,
                      ),
                  ],
                ),
              ),

              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: Colors.white,
                    radius: 14,
                    child: Icon(Icons.more_vert, size: 18, color: Colors.black54),
                  ),
                  onPressed: _toggleOptionsMenu,
                ),
              ),

              if (_showOptionsMenu)
                Positioned(
                  top: 40,
                  right: 8,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      children: [
                        if (widget.isCurrentUser)
                          InkWell(
                            onTap: () {
                              setState(() => _showOptionsMenu = false);
                              widget.onEdit?.call(widget.message.messageId);
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text("Edit"),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
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
      spacing: 8,
      runSpacing: 8,
      children: groupedReactions.entries.map((entry) {
        final emoji = entry.key;
        final reactionList = entry.value;
        final count = reactionList.length;
        final hasUserReacted = reactionList.any((r) => r.userId == currentUserId);

        return GestureDetector(
          onTap: onReactionTap != null ? () => onReactionTap!(emoji) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hasUserReacted
                  ? Colors.cyan.withOpacity(0.12)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasUserReacted
                    ? Colors.cyan
                    : Colors.grey[300]!,
                width: hasUserReacted ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedReactionEmoji(emoji: emoji, size: 22),
                if (count > 1) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hasUserReacted ? Colors.cyan[700] : Colors.grey[700],
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