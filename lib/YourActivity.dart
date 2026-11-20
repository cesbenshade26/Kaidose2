import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:flutter/services.dart';
import 'ClipsActivity.dart' show ClipGrid, ClipThumb;
import 'DailyPostActivity.dart' show DailyPostCard, warmDailyPosts;
import 'DailyShare.dart';
import 'InsideArchive.dart' show showSavedMenu;
import 'MessageStorage.dart';
import 'SavedContent.dart';
import 'SendDailyMessage.dart' show DailyMessage;
import 'SettingsWidgets.dart';
import 'clip_service.dart';
import 'ReduceMotion.dart';

/// Settings → Your activity: what you've done, newest first. Only you see
/// this.
///
///   Likes      clips you liked                (users/{uid}/liked_clips,
///                                              plus older clip_likes)
///   Reactions  Daily posts you reacted to     (users/{uid}/reacted_posts)
///   Comments   on clips and Daily posts       (every "comments" you wrote)
///   Watched    clips you've watched lately    (users/{uid}/clip_views)
///
/// Hold anything to undo it (unlike, remove a reaction, delete a comment).
class YourActivityScreen extends StatefulWidget {
  const YourActivityScreen({Key? key}) : super(key: key);

  @override
  State<YourActivityScreen> createState() => _YourActivityScreenState();
}

class _YourActivityScreenState extends State<YourActivityScreen> {
  static const _tabs = [
    (Icons.favorite_border_rounded, 'Likes'),
    (Icons.add_reaction_outlined, 'Reactions'),
    (Icons.mode_comment_outlined, 'Comments'),
    (Icons.history_rounded, 'Watched'),
  ];

  final PageController _pages = PageController();
  int _tab = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() => _tab = i);
    if (ReduceMotion.of(context)) {
      _pages.jumpToPage(i);
    } else {
      _pages.animateToPage(i,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kc.background,
      appBar: AppBar(
        title: Text('Your activity',
            style: TextStyle(
                color: SettingsStyle.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: kc.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: SettingsStyle.ink),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final on = i == _tab;
                return GestureDetector(
                  onTap: () => _go(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: on ? SettingsStyle.ink : kc.grey(100),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(_tabs[i].$1,
                            size: 17,
                            color: on ? kc.background : kc.adapt(const Color(0xFF55595F))),
                        const SizedBox(width: 6),
                        Text(_tabs[i].$2,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: on ? kc.background : SettingsStyle.ink)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _tab = i),
              children: const [
                _LikesTab(),
                _ReactionsTab(),
                _CommentsTab(),
                _WatchedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared bits ──────────────────────────────────────────────────────────────

String? get _me => FirebaseAuth.instance.currentUser?.uid;
FirebaseFirestore get _db => FirebaseFirestore.instance;

/// Clips by id, in that order; deleted or removed ones are left out.
Future<List<ClipData>> _clipsByIds(List<String> ids) async {
  final found = await Future.wait(ids.map((id) async {
    try {
      final d = await _db.collection('clips').doc(id).get();
      final data = d.data();
      if (data == null || data['hidden'] == true) return null;
      return ClipData.fromFirestore(data, d.id);
    } catch (_) {
      return null;
    }
  }));
  return found.whereType<ClipData>().toList();
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 365) return '${(d.inDays / 7).floor()}w';
  return '${(d.inDays / 365).floor()}y';
}

/// "Today", "Yesterday", "This week", "This month", "Earlier".
String _bucket(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return 'This week';
  if (days < 30) return 'This month';
  return 'Earlier';
}

Widget _header(String text) => Padding(
  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
  child: Text(text,
      style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: SettingsStyle.subtle)),
);

Widget _caption(String text, {Widget? action}) => Padding(
  padding: const EdgeInsets.fromLTRB(18, 6, 10, 8),
  child: Row(
    children: [
      Expanded(
        child: Text(text,
            style:
            TextStyle(fontSize: 13, color: SettingsStyle.subtle)),
      ),
      if (action != null) action,
    ],
  ),
);

Widget _empty(IconData icon, String title, String text) => ListView(
  physics: const AlwaysScrollableScrollPhysics(),
  children: [
    const SizedBox(height: 90),
    Icon(icon, size: 54, color: kc.adapt(const Color(0xFFC4C7CC))),
    const SizedBox(height: 14),
    Text(title,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: SettingsStyle.ink)),
    const SizedBox(height: 6),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: SettingsStyle.subtle)),
    ),
  ],
);

const Widget _spinner =
Center(child: CircularProgressIndicator(color: Color(0xFFB0B5BC)));

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(text), duration: const Duration(seconds: 2)));

/// Each tab loads once, keeps its place when you swipe away, and pulls to
/// refresh.
abstract class _TabState<W extends StatefulWidget> extends State<W>
    with AutomaticKeepAliveClientMixin {
  bool loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> load();

  Future<void> refresh() async {
    try {
      await load();
    } catch (e) {
      print('YourActivity: $e');
    }
    if (mounted) setState(() => loading = false);
  }
}

// ─── Likes ────────────────────────────────────────────────────────────────────

class _LikesTab extends StatefulWidget {
  const _LikesTab();
  @override
  State<_LikesTab> createState() => _LikesTabState();
}

class _LikesTabState extends _TabState<_LikesTab> {
  List<ClipData> _clips = [];

  @override
  Future<void> load() async {
    final me = _me;
    if (me == null) return;
    final res = await Future.wait([
      _db
          .collection('users')
          .doc(me)
          .collection('liked_clips')
          .orderBy('likedAt', descending: true)
          .limit(150)
          .get(),
      // Likes from before this list existed.
      _db.collection('clip_likes').where('uid', isEqualTo: me).limit(200).get(),
    ]);
    final when = <String, DateTime>{};
    for (final snap in res) {
      for (final d in snap.docs) {
        final id = d.data()['clipId'] as String?;
        if (id == null) continue;
        final t = (d.data()['likedAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (when[id] == null || t.isAfter(when[id]!)) when[id] = t;
      }
    }
    final ids = when.keys.toList()..sort((a, b) => when[b]!.compareTo(when[a]!));
    final clips = await _clipsByIds(ids.take(150).toList());
    if (mounted) setState(() => _clips = clips);
  }

  Future<void> _hold(ClipData clip) async {
    final c = await showSavedMenu(context, [
      (Icons.heart_broken_outlined, 'Unlike', 'unlike', true),
    ]);
    if (c != 'unlike' || _me == null) return;
    setState(() => _clips.removeWhere((x) => x.id == clip.id));
    try {
      final ref = _db.collection('clips').doc(clip.id);
      await ref.collection('likes').doc(_me).delete();
      await ref.update({'likeCount': FieldValue.increment(-1)});
    } catch (e) {
      print('YourActivity: unlike $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (loading) return _spinner;
    if (_clips.isEmpty) {
      return RefreshIndicator(
        color: kc.adapt(const Color(0xFF8A8F98)),
        onRefresh: refresh,
        child: _empty(Icons.favorite_border_rounded, 'No likes yet',
            'Clips you like show up here.'),
      );
    }
    return Column(
      children: [
        _caption('Clips you liked, newest first'),
        Expanded(
          child: RefreshIndicator(
            color: kc.adapt(const Color(0xFF8A8F98)),
            onRefresh: refresh,
            child: ClipGrid(
                clips: _clips, onLongPress: _hold, poolPrefix: 'liked:'),
          ),
        ),
      ],
    );
  }
}

// ─── Reactions ────────────────────────────────────────────────────────────────

class _Reacted {
  final String dailyId;
  final String messageId;
  final String emoji;
  final DateTime at;
  final DailyMessage message;
  final String title;
  final Color color;
  _Reacted(this.dailyId, this.messageId, this.emoji, this.at, this.message,
      this.title, this.color);
}

class _ReactionsTab extends StatefulWidget {
  const _ReactionsTab();
  @override
  State<_ReactionsTab> createState() => _ReactionsTabState();
}

class _ReactionsTabState extends _TabState<_ReactionsTab> {
  List<_Reacted> _items = [];

  @override
  Future<void> load() async {
    final me = _me;
    if (me == null) return;
    final snap = await _db
        .collection('users')
        .doc(me)
        .collection('reacted_posts')
        .orderBy('at', descending: true)
        .limit(60)
        .get();
    final found = await Future.wait(snap.docs.map((d) async {
      final m = d.data();
      final dailyId = m['dailyId'] as String?;
      final messageId = m['messageId'] as String?;
      if (dailyId == null || messageId == null) return null;
      try {
        final post = await _db
            .collection('dailies')
            .doc(dailyId)
            .collection('daily_messages')
            .doc(messageId)
            .get();
        final data = post.data();
        if (data == null || data['hidden'] == true) return null;
        final msg = DailyMessage.fromJson(data);
        if (!msg.hasContent) return null;
        final info = await SavedContent.dailyInfo(dailyId);
        return _Reacted(
          dailyId,
          messageId,
          m['emoji'] as String? ?? '',
          (m['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
          msg,
          info.$1,
          info.$2,
        );
      } catch (_) {
        return null;
      }
    }));
    if (mounted) setState(() => _items = found.whereType<_Reacted>().toList());
  }

  Future<void> _hold(_Reacted r) async {
    final c = await showSavedMenu(context, [
      (Icons.wb_sunny_outlined, 'Visit Daily', 'visit', false),
      (Icons.remove_circle_outline_rounded, 'Remove reaction', 'remove', true),
    ]);
    if (!mounted) return;
    if (c == 'visit') DailyShareLink.open(context, r.dailyId);
    if (c == 'remove' && _me != null) {
      setState(() => _items.remove(r));
      await MessageStorage.removeReaction(
          dailyId: r.dailyId, messageId: r.messageId, userId: _me!);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (loading) return _spinner;
    if (_items.isEmpty) {
      return RefreshIndicator(
        color: kc.adapt(const Color(0xFF8A8F98)),
        onRefresh: refresh,
        child: _empty(Icons.add_reaction_outlined, 'No reactions yet',
            'Daily posts you react to show up here.'),
      );
    }
    final messages = _items.map((r) => r.message).toList();
    return RefreshIndicator(
      color: kc.adapt(const Color(0xFF8A8F98)),
      onRefresh: refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: EdgeInsets.fromLTRB(2, 6, 2, 10),
              child: Text('Daily posts you reacted to, newest first',
                  style: TextStyle(fontSize: 13, color: SettingsStyle.subtle)),
            );
          }
          final r = _items[i - 1];
          warmDailyPosts(messages, i - 1);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text('You reacted ${r.emoji}  ·  ${_ago(r.at)}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: SettingsStyle.subtle)),
                ),
                DailyPostCard(
                  key: ValueKey('${r.dailyId}_${r.messageId}'),
                  message: r.message,
                  dailyId: r.dailyId,
                  dailyTitle: r.title,
                  color: r.color,
                  onLongPress: () => _hold(r),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Comments ─────────────────────────────────────────────────────────────────

class _Comment {
  final DocumentReference ref;
  final String text;
  final DateTime at;
  final String? clipId;
  final String? dailyId;
  ClipData? clip;
  String? dailyTitle;
  _Comment(this.ref, this.text, this.at, {this.clipId, this.dailyId});
}

class _CommentsTab extends StatefulWidget {
  const _CommentsTab();
  @override
  State<_CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends _TabState<_CommentsTab> {
  List<_Comment> _items = [];

  @override
  Future<void> load() async {
    final me = _me;
    if (me == null) return;
    // Clip comments and Daily comments are both called "comments".
    final snap = await _db
        .collectionGroup('comments')
        .where('authorUid', isEqualTo: me)
        .limit(300)
        .get();
    final items = <_Comment>[];
    for (final d in snap.docs) {
      final m = d.data();
      if (m['hidden'] == true) continue;
      final text = (m['text'] as String? ?? '').trim();
      if (text.isEmpty) continue;
      final at = (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final parts = d.reference.path.split('/');
      if (parts.length == 4 && parts[0] == 'clips') {
        items.add(_Comment(d.reference, text, at, clipId: parts[1]));
      } else if (parts.length == 6 && parts[0] == 'dailies') {
        items.add(_Comment(d.reference, text, at, dailyId: parts[1]));
      }
    }
    items.sort((a, b) => b.at.compareTo(a.at));
    final list = items.take(120).toList();

    // What each one was on: the clip (for its picture) or the Daily's name.
    final clipIds = list.map((c) => c.clipId).whereType<String>().toSet();
    final clips = {
      for (final c in await _clipsByIds(clipIds.take(60).toList())) c.id: c,
    };
    final dailyIds = list.map((c) => c.dailyId).whereType<String>().toSet();
    final titles = {
      for (final id in dailyIds) id: (await SavedContent.dailyInfo(id)).$1,
    };
    for (final c in list) {
      if (c.clipId != null) c.clip = clips[c.clipId];
      if (c.dailyId != null) c.dailyTitle = titles[c.dailyId];
    }
    if (mounted) setState(() => _items = list);
  }

  void _open(_Comment c) {
    if (c.clip != null) {
      ClipGrid.openViewer(context, [c.clip!], 0, poolPrefix: 'activity:');
    } else if (c.dailyId != null) {
      DailyShareLink.open(context, c.dailyId!);
    } else {
      _toast(context, 'That clip is no longer up');
    }
  }

  Future<void> _hold(_Comment c) async {
    final choice = await showSavedMenu(context, [
      (Icons.delete_outline_rounded, 'Delete comment', 'delete', true),
    ]);
    if (choice != 'delete' || !mounted) return;
    final ok = await settingsConfirm(context,
        title: 'Delete comment?',
        message: '"${c.text.length > 80 ? '${c.text.substring(0, 80)}…' : c.text}"',
        confirmLabel: 'Delete',
        danger: true);
    if (!ok) return;
    setState(() => _items.remove(c));
    try {
      await c.ref.delete();
    } catch (e) {
      print('YourActivity: delete comment $e');
    }
  }

  Widget _row(_Comment c) {
    final thumb = c.clip?.thumbnailUrl;
    final leading = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: c.clipId != null ? 60 : 44,
        color: SettingsStyle.page,
        child: c.clipId != null
            ? (thumb != null && thumb.isNotEmpty
            ? Image(image: ClipThumb.provider(thumb), fit: BoxFit.cover)
            : Icon(Icons.play_arrow_rounded,
            color: kc.adapt(const Color(0xFF8A8F98))))
            : Icon(Icons.wb_sunny_outlined,
            size: 22, color: kc.adapt(const Color(0xFF55595F))),
      ),
    );
    final where = c.clipId != null
        ? (c.clip != null
        ? "On ${c.clip!.creatorUsername.isEmpty ? 'a' : "${c.clip!.creatorUsername}'s"} clip"
        : 'On a clip that was removed')
        : 'In ${c.dailyTitle ?? 'a Daily'}';
    return InkWell(
      onTap: () => _open(c),
      onLongPress: () => _hold(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(where,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: SettingsStyle.subtle)),
                      ),
                      Text(_ago(c.at),
                          style: TextStyle(
                              fontSize: 12, color: kc.adapt(const Color(0xFFA5AAB2)))),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(c.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15, height: 1.3, color: SettingsStyle.ink)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (loading) return _spinner;
    if (_items.isEmpty) {
      return RefreshIndicator(
        color: kc.adapt(const Color(0xFF8A8F98)),
        onRefresh: refresh,
        child: _empty(Icons.mode_comment_outlined, 'No comments yet',
            'Comments you leave on clips and Daily posts show up here.'),
      );
    }
    final children = <Widget>[];
    String? last;
    for (final c in _items) {
      final b = _bucket(c.at);
      if (b != last) {
        children.add(_header(b));
        last = b;
      }
      children.add(_row(c));
    }
    return RefreshIndicator(
      color: kc.adapt(const Color(0xFF8A8F98)),
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: children,
      ),
    );
  }
}

// ─── Watched ──────────────────────────────────────────────────────────────────

class _WatchedTab extends StatefulWidget {
  const _WatchedTab();
  @override
  State<_WatchedTab> createState() => _WatchedTabState();
}

class _WatchedTabState extends _TabState<_WatchedTab> {
  List<ClipData> _clips = [];

  CollectionReference<Map<String, dynamic>>? get _views => _me == null
      ? null
      : _db.collection('users').doc(_me).collection('clip_views');

  @override
  Future<void> load() async {
    final views = _views;
    if (views == null) return;
    final snap = await views.orderBy('at', descending: true).limit(90).get();
    final clips = await _clipsByIds(snap.docs.map((d) => d.id).toList());
    if (mounted) setState(() => _clips = clips);
  }

  Future<void> _clearAll() async {
    final ok = await settingsConfirm(
      context,
      title: 'Clear watch history?',
      message: "Clips you've already watched may show up in your feed again.",
      confirmLabel: 'Clear',
      danger: true,
    );
    final views = _views;
    if (!ok || views == null) return;
    setState(() => _clips = []);
    try {
      while (true) {
        final snap = await views.limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        if (snap.docs.length < 400) break;
      }
      if (mounted) _toast(context, 'Watch history cleared');
    } catch (e) {
      print('YourActivity: clear history $e');
    }
  }

  Future<void> _hold(ClipData clip) async {
    final c = await showSavedMenu(context, [
      (Icons.remove_circle_outline_rounded, 'Remove from history', 'remove',
      true),
    ]);
    if (c != 'remove') return;
    HapticFeedback.lightImpact();
    setState(() => _clips.removeWhere((x) => x.id == clip.id));
    await _views?.doc(clip.id).delete().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (loading) return _spinner;
    if (_clips.isEmpty) {
      return RefreshIndicator(
        color: kc.adapt(const Color(0xFF8A8F98)),
        onRefresh: refresh,
        child: _empty(Icons.history_rounded, 'Nothing watched yet',
            'Clips you watch show up here, so you can find them again.'),
      );
    }
    return Column(
      children: [
        _caption(
          'Clips you watched recently',
          action: TextButton(
            onPressed: _clearAll,
            style: TextButton.styleFrom(foregroundColor: SettingsStyle.ink),
            child: const Text('Clear all',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: kc.adapt(const Color(0xFF8A8F98)),
            onRefresh: refresh,
            child: ClipGrid(
                clips: _clips, onLongPress: _hold, poolPrefix: 'watched:'),
          ),
        ),
      ],
    );
  }
}