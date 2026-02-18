import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'MessageStorage.dart';
import 'SendDailyMessage.dart';
import 'MessageComments.dart';

class CommentWithContext {
  final MessageComment comment;
  final DailyMessage parentMessage;

  CommentWithContext({
    required this.comment,
    required this.parentMessage,
  });
}

class DailyCommentsScreen extends StatefulWidget {
  final DailyData daily;

  const DailyCommentsScreen({
    Key? key,
    required this.daily,
  }) : super(key: key);

  @override
  State<DailyCommentsScreen> createState() => _DailyCommentsScreenState();
}

class _DailyCommentsScreenState extends State<DailyCommentsScreen> {
  List<CommentWithContext> _myComments = [];
  List<CommentWithContext> _savedComments = []; // For future implementation
  bool _isLoading = true;
  String _selectedFilter = 'My Comments'; // 'My Comments' or 'Saved Comments'

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    // Load all messages in this daily
    final messages = await MessageStorage.loadMessages(widget.daily.id);

    List<CommentWithContext> myComments = [];

    // For each message, load its comments
    for (final message in messages) {
      final comments = await CommentStorage.loadComments(message.messageId);

      // TODO: When multi-user support is added, filter by current user ID
      // For now, all comments are "mine" since it's single-user
      for (final comment in comments) {
        myComments.add(CommentWithContext(
          comment: comment,
          parentMessage: message,
        ));
      }
    }

    // Sort by newest first
    myComments.sort((a, b) =>
        b.comment.timestamp.compareTo(a.comment.timestamp));

    if (mounted) {
      setState(() {
        _myComments = myComments;
        _isLoading = false;
      });
    }
  }

  // TODO: Implement when saved comments feature is added
  Future<void> _loadSavedComments() async {
    // This will load comments that the user has saved
    // Will be implemented when comment saving is added
    setState(() {
      _savedComments = [];
    });
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
              'Comments',
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedFilter = 'My Comments';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _selectedFilter == 'My Comments'
                                ? Colors.cyan
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        'My Comments',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _selectedFilter == 'My Comments'
                              ? Colors.cyan
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedFilter = 'Saved Comments';
                      });
                      // TODO: Load saved comments when feature is implemented
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _selectedFilter == 'Saved Comments'
                                ? Colors.cyan
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        'Saved Comments',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _selectedFilter == 'Saved Comments'
                              ? Colors.cyan
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    final displayList = _selectedFilter == 'My Comments'
        ? _myComments
        : _savedComments;

    if (displayList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _selectedFilter == 'My Comments'
                  ? Icons.comment_outlined
                  : Icons.bookmark_border,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              _selectedFilter == 'My Comments'
                  ? 'No Comments Yet'
                  : 'No Saved Comments',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedFilter == 'My Comments'
                  ? 'Comments you post will appear here'
                  : 'Save comments to see them here',
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
      itemCount: displayList.length,
      separatorBuilder: (context, index) => Divider(
        height: 32,
        color: Colors.grey[200],
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final item = displayList[index];
        return _buildCommentItem(item);
      },
    );
  }

  Widget _buildCommentItem(CommentWithContext item) {
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
            // Parent message preview
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.message, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Text(
                        'On message',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.parentMessage.text ?? '[Image]',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),

            // The comment itself
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.comment.text,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Bottom bar with timestamp and like button
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(
                          Icons.access_time,
                          size: 13,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTimestamp(item.comment.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        // Like button
                        GestureDetector(
                          onTap: () {
                            // TODO: When API is ready, sync like status to server
                            setState(() {
                              item.comment.isLiked = !item.comment.isLiked;
                            });
                            // Save updated comment
                            CommentStorage.loadComments(item.comment.messageId).then((comments) {
                              CommentStorage.saveComments(item.comment.messageId, comments);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            child: Row(
                              children: [
                                Icon(
                                  item.comment.isLiked ? Icons.favorite : Icons.favorite_border,
                                  color: item.comment.isLiked ? Colors.red : Colors.grey[600],
                                  size: 20,
                                ),
                                if (item.comment.likeCount > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatLikeCount(item.comment.likeCount),
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
                        const SizedBox(width: 6),
                      ],
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
 *    - Filter comments by current user ID in _loadComments()
 *    - API endpoint: GET /api/dailies/{dailyId}/comments?userId={currentUserId}
 *    - Response: List of comments with parent message context
 *
 * 2. Saved comments feature:
 *    - Implement _loadSavedComments() to fetch saved comments
 *    - API endpoint: GET /api/users/{userId}/saved-comments?dailyId={dailyId}
 *    - Add save/unsave functionality on each comment
 *    - API endpoints:
 *      - POST /api/comments/{commentId}/save
 *      - DELETE /api/comments/{commentId}/save
 *
 * 3. Comment likes sync:
 *    - When user likes/unlikes, sync to server
 *    - API endpoints:
 *      - POST /api/comments/{commentId}/like
 *      - DELETE /api/comments/{commentId}/like
 *    - Update likeCount in real-time from server response
 *
 * 4. Real-time updates:
 *    - WebSocket or polling for new comments from others
 *    - Update UI when new comments arrive
 *
 * 5. Comment from other users:
 *    - Display user avatar/name
 *    - Different styling for current user vs others
 */