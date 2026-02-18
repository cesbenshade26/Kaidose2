import 'package:flutter/material.dart';
import 'dart:io';
import 'DailyData.dart';
import 'MessageStorage.dart';
import 'SendDailyMessage.dart';

class DailyLikesScreen extends StatefulWidget {
  final DailyData daily;

  const DailyLikesScreen({
    Key? key,
    required this.daily,
  }) : super(key: key);

  @override
  State<DailyLikesScreen> createState() => _DailyLikesScreenState();
}

class _DailyLikesScreenState extends State<DailyLikesScreen> {
  List<DailyMessage> _likedMessages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLikedMessages();
  }

  Future<void> _loadLikedMessages() async {
    // Load all messages in this daily
    final messages = await MessageStorage.loadMessages(widget.daily.id);

    // Filter to only liked messages
    final likedMessages = messages.where((msg) => msg.isLiked).toList();

    // Sort by newest first
    likedMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (mounted) {
      setState(() {
        _likedMessages = likedMessages;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleLike(DailyMessage message) async {
    setState(() {
      message.isLiked = !message.isLiked;
    });

    // Update in storage
    final allMessages = await MessageStorage.loadMessages(widget.daily.id);
    await MessageStorage.saveMessages(widget.daily.id, allMessages);

    // Reload to update the list (remove if unliked)
    await _loadLikedMessages();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    // Format as date
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[timestamp.month - 1]} ${timestamp.day}';
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Liked Messages',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.daily.title,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(color: Colors.cyan),
      )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_likedMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No Liked Messages',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Messages you like will appear here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: _likedMessages.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final message = _likedMessages[index];
        return _buildMessageItem(message);
      },
    );
  }

  Widget _buildMessageItem(DailyMessage message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.cyan.withOpacity(0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.cyan.withOpacity(0.1),
              blurRadius: 8,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image if present
            if (message.imagePath != null && File(message.imagePath!).existsSync())
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
                child: Image.file(
                  File(message.imagePath!),
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: Center(
                        child: Icon(
                          Icons.error_outline,
                          color: Colors.grey[400],
                          size: 48,
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Text if present
            if (message.text != null && message.text!.trim().isNotEmpty)
              Padding(
                padding: EdgeInsets.all(message.imagePath != null ? 16 : 16),
                child: Text(
                  message.text!,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
              ),

            // Bottom bar with timestamp and actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Timestamp
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 13,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTimestamp(message.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  // Like button
                  GestureDetector(
                    onTap: () => _toggleLike(message),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      child: Row(
                        children: [
                          Icon(
                            message.isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 20,
                            color: message.isLiked ? Colors.red : Colors.grey[600],
                          ),
                          if (message.likeCount > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              _formatLikeCount(message.likeCount),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
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

/*
 * TODO: Future API Integration Points
 *
 * 1. Multi-user support:
 *    - Filter messages by current user's likes
 *    - API endpoint: GET /api/dailies/{dailyId}/messages?likedBy={currentUserId}
 *    - Response: List of messages liked by the user
 *
 * 2. Like sync:
 *    - When user unlikes, sync to server
 *    - API endpoints:
 *      - POST /api/messages/{messageId}/like
 *      - DELETE /api/messages/{messageId}/like
 *    - Update likeCount in real-time from server response
 *
 * 3. Real-time updates:
 *    - WebSocket or polling for like count updates from other users
 *    - Update UI when others like the same messages
 *
 * 4. Message interactions:
 *    - Add ability to jump to original message in daily
 *    - Show comment count on liked messages
 */