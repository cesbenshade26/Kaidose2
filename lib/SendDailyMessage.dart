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

class DailyMessage {
  final String? text;
  final String? imagePath;
  final String? videoPath;
  final DateTime timestamp;
  final String userId;
  final String messageId;
  final String dailyId;
  bool isSaved;
  final bool isFromPrompt;
  List<ChatReaction> reactions;
  final String? username;

  DailyMessage({
    this.text,
    this.imagePath,
    this.videoPath,
    required this.timestamp,
    String? userId,
    String? messageId,
    String? dailyId,
    this.isSaved = false,
    this.isFromPrompt = false,
    List<ChatReaction>? reactions,
    this.username,
  })  : userId = userId ?? 'current_user',
        messageId = messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        dailyId = dailyId ?? 'unknown_daily',
        reactions = reactions ?? [];

  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'user_id': userId,
      'daily_id': dailyId,
      'text': text,
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
    return DailyMessage(
      text: json['text'],
      imagePath: json['image_path'],
      videoPath: json['video_path'],
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

  bool get hasContent => (text != null && text!.trim().isNotEmpty) || imagePath != null || videoPath != null;

  bool isFromCurrentUser() => userId == 'current_user';

  int get reactionCount => reactions.length;

  bool get hasUserReacted => reactions.any((r) => r.userId == 'current_user');
}

class DailyMessageWidget extends StatefulWidget {
  final DailyMessage message;
  final bool isCurrentUser;
  final VoidCallback? onReply;
  final Function(String)? onEdit;
  final VoidCallback? onSaveToggle;
  final Function(String)? onReactionAdded;

  const DailyMessageWidget({
    Key? key,
    required this.message,
    this.isCurrentUser = true,
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
      final currentUserId = 'current_user';
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

    if (widget.onReactionAdded != null) {
      widget.onReactionAdded!(emoji);
    }
  }

  void _toggleReaction(String emoji, List<ChatReaction> reactions) {
    final currentUserId = 'current_user';
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
      final archives = ArchiveStorage.archives;
      if (archives.length == 1) {
        await SavedItemStorage.saveItem(archives[0].id, widget.message);
      } else if (context.mounted) {
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

  void _toggleOptionsMenu() => setState(() => _showOptionsMenu = !_showOptionsMenu);

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final messageWidth = screenWidth * 0.85;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Username label above message
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              widget.message.username ?? (widget.isCurrentUser ? 'You' : 'Unknown'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: messageWidth,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.cyan.withOpacity(0.3), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyan.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.message.imagePath != null)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        child: Image.file(
                          File(widget.message.imagePath!),
                          width: messageWidth,
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (widget.message.videoPath != null)
                      SizedBox(
                        width: messageWidth,
                        child: AspectRatio(
                          aspectRatio: 9 / 16,
                          child: VideoClipPlayer(
                            videoFile: File(widget.message.videoPath!),
                            autoPlay: true,
                            looping: true,
                            fit: BoxFit.contain,
                          ),
                        ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: MessageReactionsDisplay(
                          reactions: widget.message.reactions,
                          currentUserId: 'current_user',
                          onReactionTap: (emoji) => _toggleReaction(emoji, widget.message.reactions),
                        ),
                      ),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.05),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTimestamp(widget.message.timestamp),
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: _showReactionPicker,
                                child: Icon(
                                  Icons.add_reaction_outlined,
                                  size: 20,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: _handleReply,
                                child: Row(
                                  children: [
                                    Icon(Icons.comment_outlined, size: 20, color: Colors.grey[600]),
                                    if (_commentCount > 0) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        '$_commentCount',
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: _toggleSave,
                                child: Icon(
                                  widget.message.isSaved ? Icons.bookmark : Icons.bookmark_border,
                                  size: 20,
                                  color: widget.message.isSaved ? Colors.cyan : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
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