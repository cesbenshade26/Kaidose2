import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MessageComment {
  final String id;
  final String messageId; // Parent message ID
  final String text;
  final DateTime timestamp;
  bool isLiked;
  int likeCount;

  MessageComment({
    String? id,
    required this.messageId,
    required this.text,
    required this.timestamp,
    this.isLiked = false,
    this.likeCount = 0,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
    'id': id,
    'message_id': messageId,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'is_liked': isLiked,
    'like_count': likeCount,
  };

  factory MessageComment.fromJson(Map<String, dynamic> json) => MessageComment(
    id: json['id'],
    messageId: json['message_id'],
    text: json['text'],
    timestamp: DateTime.parse(json['timestamp']),
    isLiked: json['is_liked'] ?? false,
    likeCount: json['like_count'] ?? 0,
  );
}

class CommentStorage {
  static const String _prefix = 'message_comments_';

  static Future<void> saveComments(String messageId, List<MessageComment> comments) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = comments.map((c) => c.toJson()).toList();
    await prefs.setString('$_prefix$messageId', json.encode(jsonList));
  }

  static Future<List<MessageComment>> loadComments(String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('$_prefix$messageId');
    if (jsonString == null) return [];
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((j) => MessageComment.fromJson(j)).toList();
  }

  static Future<int> getCommentCount(String messageId) async {
    final comments = await loadComments(messageId);
    return comments.length;
  }
}

class MessageCommentsSection extends StatefulWidget {
  final String messageId;
  final VoidCallback? onCommentsChanged;

  const MessageCommentsSection({
    Key? key,
    required this.messageId,
    this.onCommentsChanged,
  }) : super(key: key);

  @override
  State<MessageCommentsSection> createState() => _MessageCommentsSectionState();
}

class _MessageCommentsSectionState extends State<MessageCommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<MessageComment> _comments = [];

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final comments = await CommentStorage.loadComments(widget.messageId);
    if (mounted) {
      setState(() {
        _comments = comments;
      });
    }
  }

  Future<void> _saveComments() async {
    await CommentStorage.saveComments(widget.messageId, _comments);
    if (widget.onCommentsChanged != null) {
      widget.onCommentsChanged!();
    }
  }

  void _addComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final comment = MessageComment(
      messageId: widget.messageId,
      text: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _comments.add(comment);
      _commentController.clear();
    });

    _saveComments();

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleLike(int index) {
    setState(() {
      _comments[index].isLiked = !_comments[index].isLiked;
    });
    _saveComments();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return '1m';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 365) return '${diff.inDays}d';
    return '${(diff.inDays / 365).floor()}y';
  }

  String _formatLikeCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) {
      final k = count / 1000;
      if (k == k.floor()) return '${k.toInt()}k';
      return '${k.toStringAsFixed(k < 10 ? 1 : 0)}k';
    }
    final m = count / 1000000;
    return '${m.toInt()}m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Divider
        Divider(height: 1, color: Colors.grey[200]),

        // Comments list
        if (_comments.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _comments.length,
              itemBuilder: (context, index) {
                final comment = _comments[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Timestamp
                      Text(
                        _formatTimestamp(comment.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Comment text
                      Expanded(
                        child: Text(
                          comment.text,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                      // Like button
                      GestureDetector(
                        onTap: () => _toggleLike(index),
                        child: Row(
                          children: [
                            if (comment.likeCount > 0) ...[
                              Text(
                                _formatLikeCount(comment.likeCount),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Icon(
                              comment.isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 16,
                              color: comment.isLiked ? Colors.red : Colors.grey[400],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

        // Input field
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[400],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Colors.cyan),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _addComment(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _addComment,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.cyan,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}