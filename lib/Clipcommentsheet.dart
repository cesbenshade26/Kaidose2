import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClipCommentSheet extends StatefulWidget {
  final String clipId;
  final VoidCallback onClose;

  const ClipCommentSheet({
    Key? key,
    required this.clipId,
    required this.onClose,
  }) : super(key: key);

  @override
  State<ClipCommentSheet> createState() => _ClipCommentSheetState();
}

class _ClipCommentSheetState extends State<ClipCommentSheet> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _posting = false;

  String? get _uid => _auth.currentUser?.uid;

  @override
  void dispose() {
    _commentController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _uid == null || _posting) return;

    setState(() => _posting = true);
    try {
      // Fetch username
      final userDoc = await _firestore.collection('users').doc(_uid).get();
      final username = userDoc.data()?['username'] ?? 'Unknown';

      await _firestore
          .collection('clips')
          .doc(widget.clipId)
          .collection('comments')
          .add({
        'text': text,
        'authorUid': _uid,
        'authorUsername': username,
        'likeCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _commentController.clear();
      _focusNode.unfocus();
    } catch (e) {
      print('ClipCommentSheet: post error: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Comments',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(Icons.close,
                      color: Colors.grey[600], size: 22),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFEEEEEE)),

          // Comments list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('clips')
                  .doc(widget.clipId)
                  .collection('comments')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.cyan),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('No comments yet',
                            style: TextStyle(
                                fontSize: 15, color: Colors.grey[500])),
                        const SizedBox(height: 4),
                        Text('Be the first to comment',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[400])),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _CommentTile(
                      commentId: doc.id,
                      clipId: widget.clipId,
                      data: data,
                    );
                  },
                );
              },
            ),
          ),

          // Comment input
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.15),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _commentController,
                      focusNode: _focusNode,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 15, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        hintStyle: TextStyle(
                            color: Colors.grey[400], fontSize: 15),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _postComment(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _postComment,
                  child: _posting
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.cyan),
                  )
                      : const Icon(Icons.send_rounded,
                      color: Colors.cyan, size: 26),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Individual comment tile ──────────────────────────────────────────────────

class _CommentTile extends StatefulWidget {
  final String commentId;
  final String clipId;
  final Map<String, dynamic> data;

  const _CommentTile({
    required this.commentId,
    required this.clipId,
    required this.data,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  bool _liked = false;
  int _likeCount = 0;
  bool _loadingLike = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.data['likeCount'] ?? 0;
    _checkLiked();
  }

  Future<void> _checkLiked() async {
    if (_uid == null) return;
    try {
      final doc = await _firestore
          .collection('clips')
          .doc(widget.clipId)
          .collection('comments')
          .doc(widget.commentId)
          .collection('likes')
          .doc(_uid)
          .get();
      if (mounted) setState(() => _liked = doc.exists);
    } catch (e) {
      print('_CommentTile: check liked error: $e');
    }
  }

  Future<void> _toggleLike() async {
    if (_uid == null || _loadingLike) return;
    setState(() => _loadingLike = true);

    try {
      final likeRef = _firestore
          .collection('clips')
          .doc(widget.clipId)
          .collection('comments')
          .doc(widget.commentId)
          .collection('likes')
          .doc(_uid);

      final commentRef = _firestore
          .collection('clips')
          .doc(widget.clipId)
          .collection('comments')
          .doc(widget.commentId);

      if (_liked) {
        await likeRef.delete();
        await commentRef
            .update({'likeCount': FieldValue.increment(-1)});
        if (mounted) {
          setState(() {
            _liked = false;
            _likeCount = (_likeCount - 1).clamp(0, 999999999);
          });
        }
      } else {
        await likeRef.set({'likedAt': FieldValue.serverTimestamp()});
        await commentRef
            .update({'likeCount': FieldValue.increment(1)});
        if (mounted) {
          setState(() {
            _liked = true;
            _likeCount += 1;
          });
        }
      }
    } catch (e) {
      print('_CommentTile: like error: $e');
    } finally {
      if (mounted) setState(() => _loadingLike = false);
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
    final username = widget.data['authorUsername'] ?? 'Unknown';
    final text = widget.data['text'] ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.cyan[700],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Username + comment text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(
                      fontSize: 14, color: Colors.black87),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Like button + count
          GestureDetector(
            onTap: _toggleLike,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  color: _liked ? Colors.red : Colors.grey[400],
                  size: 18,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatCount(_likeCount),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}