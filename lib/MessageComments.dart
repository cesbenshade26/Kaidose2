import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Moderation.dart' show TermsGate;
import 'user_service.dart';

/// Comments on a Daily post, shared with everyone in the Daily:
///   dailies/{dailyId}/daily_messages/{messageId}/comments/{commentId}
///     {text, authorUid, authorUsername, createdAt, likedBy: [uid]}
///
/// The server checks each one (onDailyCommentModerate: removed ones get
/// `hidden: true`) and tells the post's author (notifyDailyComment).
/// Comments used to be saved only on the phone that wrote them; those are
/// uploaded the first time their post's comments are opened.
class MessageComment {
  final String id;
  final String dailyId;
  final String messageId;
  final String text;
  final DateTime timestamp;
  final String userId;
  final String? username;
  final List<String> likedBy;

  MessageComment({
    required this.id,
    required this.dailyId,
    required this.messageId,
    required this.text,
    required this.timestamp,
    required this.userId,
    this.username,
    this.likedBy = const [],
  });

  static String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get isLiked => likedBy.contains(_me);
  int get likeCount => likedBy.length;
  bool get isMine => userId == _me;

  factory MessageComment.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> d, String dailyId, String messageId) {
    final m = d.data() ?? {};
    return MessageComment(
      id: d.id,
      dailyId: dailyId,
      messageId: messageId,
      text: m['text'] as String? ?? '',
      timestamp: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      userId: m['authorUid'] as String? ?? '',
      username: m['authorUsername'] as String?,
      likedBy: List<String>.from(m['likedBy'] ?? const []),
    );
  }
}

class CommentStorage {
  CommentStorage._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _ref(
      String dailyId, String messageId) =>
      _db
          .collection('dailies')
          .doc(dailyId)
          .collection('daily_messages')
          .doc(messageId)
          .collection('comments');

  static bool _visible(Map<String, dynamic> m) => m['hidden'] != true;

  /// Oldest first, live. Removed comments don't show.
  static Stream<List<MessageComment>> watch(String dailyId, String messageId) {
    _migrateLocal(dailyId, messageId);
    return _ref(dailyId, messageId)
        .orderBy('createdAt')
        .limit(200)
        .snapshots()
        .map((s) => s.docs
        .where((d) => _visible(d.data()))
        .map((d) => MessageComment.fromDoc(d, dailyId, messageId))
        .toList());
  }

  static Future<int> getCommentCount(String dailyId, String messageId) async {
    try {
      final c = await _ref(dailyId, messageId).count().get();
      return c.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Every comment you've left in this Daily, newest first
  /// (DailyComments.dart).
  static Future<List<MessageComment>> mineInDaily(String dailyId) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return [];
    try {
      final snap = await _db
          .collectionGroup('comments')
          .where('authorUid', isEqualTo: me)
          .limit(300)
          .get();
      final out = <MessageComment>[];
      for (final d in snap.docs) {
        // dailies/{dailyId}/daily_messages/{messageId}/comments/{id}
        final parts = d.reference.path.split('/');
        if (parts.length != 6 || parts[0] != 'dailies' || parts[1] != dailyId) {
          continue; // a clip comment, or another Daily
        }
        if (!_visible(d.data())) continue;
        out.add(MessageComment.fromDoc(d, dailyId, parts[3]));
      }
      out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return out;
    } catch (e) {
      print('CommentStorage.mineInDaily: $e');
      return [];
    }
  }

  static String? _myName;

  static Future<String> _username() async {
    if (_myName != null) return _myName!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('kaidose_user');
      if (saved != null && saved.isNotEmpty) return _myName = saved;
    } catch (_) {}
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final u = await UserService().getUserById(uid);
      if (u != null && u.username.isNotEmpty) return _myName = u.username;
    }
    return '';
  }

  static Future<bool> add(String dailyId, String messageId, String text) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      await _ref(dailyId, messageId).add({
        'text': text,
        'authorUid': uid,
        'authorUsername': await _username(),
        'likedBy': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('CommentStorage.add: $e');
      return false;
    }
  }

  static Future<void> toggleLike(MessageComment c) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _ref(c.dailyId, c.messageId).doc(c.id).update({
        'likedBy': c.isLiked
            ? FieldValue.arrayRemove([uid])
            : FieldValue.arrayUnion([uid]),
      });
    } catch (e) {
      print('CommentStorage.toggleLike: $e');
    }
  }

  static Future<bool> delete(MessageComment c) async {
    try {
      await _ref(c.dailyId, c.messageId).doc(c.id).delete();
      return true;
    } catch (e) {
      print('CommentStorage.delete: $e');
      return false;
    }
  }

  // ─── Old phone-only comments ────────────────────────────────────────────

  static const String _oldPrefix = 'message_comments_';
  static final Set<String> _migrated = {};

  /// Uploads comments this phone saved the old way (only the ones you
  /// wrote), then forgets the local copy.
  static Future<void> _migrateLocal(String dailyId, String messageId) async {
    if (!_migrated.add(messageId)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_oldPrefix$messageId');
      if (raw == null) return;
      final list = (json.decode(raw) as List).whereType<Map>();
      final name = await _username();
      for (final j in list) {
        final author = j['user_id'];
        final text = (j['text'] as String? ?? '').trim();
        if (text.isEmpty || (author != uid && author != 'current_user')) continue;
        final when = DateTime.tryParse(j['timestamp'] as String? ?? '');
        await _ref(dailyId, messageId).doc('old_${j['id']}').set({
          'text': text,
          'authorUid': uid,
          'authorUsername': name,
          'likedBy': <String>[],
          'createdAt': when != null
              ? Timestamp.fromDate(when)
              : FieldValue.serverTimestamp(),
        });
      }
      await prefs.remove('$_oldPrefix$messageId');
    } catch (e) {
      _migrated.remove(messageId);
      print('CommentStorage: old comments not moved yet: $e');
    }
  }
}

class MessageCommentsSection extends StatefulWidget {
  final String dailyId;
  final String messageId;
  final VoidCallback? onCommentsChanged;

  const MessageCommentsSection({
    Key? key,
    required this.dailyId,
    required this.messageId,
    this.onCommentsChanged,
  }) : super(key: key);

  @override
  State<MessageCommentsSection> createState() => _MessageCommentsSectionState();
}

class _MessageCommentsSectionState extends State<MessageCommentsSection> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late Stream<List<MessageComment>> _stream =
  CommentStorage.watch(widget.dailyId, widget.messageId);
  int _lastCount = -1;
  bool _sending = false;

  @override
  void didUpdateWidget(MessageCommentsSection old) {
    super.didUpdateWidget(old);
    if (old.messageId != widget.messageId || old.dailyId != widget.dailyId) {
      _stream = CommentStorage.watch(widget.dailyId, widget.messageId);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sending) return;
    // Same check as every other post button (slurs etc.).
    if (!await TermsGate.readyToPost(context, text)) return;
    setState(() => _sending = true);
    final ok = await CommentStorage.add(widget.dailyId, widget.messageId, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't post your comment. Try again.")));
      return;
    }
    _commentController.clear();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _confirmDelete(MessageComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) await CommentStorage.delete(c);
  }

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
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
        Divider(height: 1, color: kc.grey(200)),

        // Comments list
        StreamBuilder<List<MessageComment>>(
          stream: _stream,
          builder: (context, snap) {
            final comments = snap.data ?? const <MessageComment>[];
            if (snap.hasData && comments.length != _lastCount) {
              final first = _lastCount == -1;
              _lastCount = comments.length;
              if (!first) {
                WidgetsBinding.instance.addPostFrameCallback(
                        (_) => widget.onCommentsChanged?.call());
              }
            }
            if (comments.isEmpty) return const SizedBox.shrink();
            return Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: comments.length,
                itemBuilder: (context, index) {
                  final comment = comments[index];
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress:
                    comment.isMine ? () => _confirmDelete(comment) : null,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Username
                          Text(
                            comment.isMine
                                ? 'You'
                                : (comment.username?.isNotEmpty == true
                                ? comment.username!
                                : 'User'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: kc.grey(700),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Timestamp
                              Text(
                                _formatTimestamp(comment.timestamp),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: kc.grey(400),
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
                                    color: kc.grey(800),
                                  ),
                                ),
                              ),
                              // Like button
                              GestureDetector(
                                onTap: () => CommentStorage.toggleLike(comment),
                                child: Row(
                                  children: [
                                    if (comment.likeCount > 0) ...[
                                      Text(
                                        _formatLikeCount(comment.likeCount),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: kc.grey(500),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Icon(
                                      comment.isLiked
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 16,
                                      color: comment.isLiked
                                          ? Colors.red
                                          : kc.grey(400),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
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
                      color: kc.grey(400),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: kc.grey(300)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: kc.grey(300)),
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
                  maxLength: 500,
                  buildCounter: (_, {required currentLength,
                    required isFocused, maxLength}) =>
                  null,
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
                  child: _sending
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(
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