import 'package:flutter/material.dart';
import 'AppColors.dart';
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
  List<CommentWithContext> _savedComments = [];
  bool _isLoading = true;
  String _selectedFilter = 'My Comments';

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    // Your comments in this Daily (one query), matched to their posts.
    final results = await Future.wait([
      MessageStorage.loadMessages(widget.daily.id),
      CommentStorage.mineInDaily(widget.daily.id),
    ]);
    final messages = results[0] as List<DailyMessage>;
    final comments = results[1] as List<MessageComment>;
    final byId = {for (final m in messages) m.messageId: m};

    final myComments = <CommentWithContext>[
      for (final c in comments)
        if (byId[c.messageId] != null)
          CommentWithContext(comment: c, parentMessage: byId[c.messageId]!),
    ];

    if (mounted) {
      setState(() {
        _myComments = myComments;
        _isLoading = false;
      });
    }
  }

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
      backgroundColor: kc.background,
      appBar: AppBar(
        backgroundColor: kc.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: kc.text, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comments',
              style: TextStyle(
                color: kc.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.daily.title,
              style: TextStyle(
                color: kc.grey(600),
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
                bottom: BorderSide(color: kc.grey(200), width: 1),
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
                              : kc.grey(600),
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
                              : kc.grey(600),
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
          ? Center(
        child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))),
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
              color: kc.grey(300),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedFilter == 'My Comments'
                  ? 'No Comments Yet'
                  : 'No Saved Comments',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: kc.grey(700),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedFilter == 'My Comments'
                  ? 'Comments you post will appear here'
                  : 'Save comments to see them here',
              style: TextStyle(
                fontSize: 14,
                color: kc.grey(500),
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
        color: kc.grey(200),
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
          color: kc.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: kc.adapt(const Color(0xFFE8EAED)),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
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
                color: kc.grey(50),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kc.grey(200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.message, size: 14, color: kc.grey(500)),
                      const SizedBox(width: 6),
                      Text(
                        'On message',
                        style: TextStyle(
                          fontSize: 11,
                          color: kc.grey(500),
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
                      color: kc.grey(700),
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
                    item.comment.username ?? 'You',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kc.grey(700),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.comment.text,
                    style: TextStyle(
                      fontSize: 15,
                      color: kc.text,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Bottom bar with timestamp and like button
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: kc.adapt(const Color(0xFFF7F8FA)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(
                          Icons.access_time,
                          size: 13,
                          color: kc.grey(600),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTimestamp(item.comment.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: kc.grey(600),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        // Like button
                        GestureDetector(
                          onTap: () async {
                            await CommentStorage.toggleLike(item.comment);
                            _loadComments();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            child: Row(
                              children: [
                                Icon(
                                  item.comment.isLiked ? Icons.favorite : Icons.favorite_border,
                                  color: item.comment.isLiked ? Colors.red : kc.grey(600),
                                  size: 20,
                                ),
                                if (item.comment.likeCount > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatLikeCount(item.comment.likeCount),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: kc.grey(600),
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