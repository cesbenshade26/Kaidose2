import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'DailyShare.dart';
import 'MessageStorage.dart';
import 'NetworkVideoPlayer.dart';
import 'PinnedPosts.dart';
import 'SendDailyMessage.dart';

/// The Dailies tab on a profile: everything a person has posted in Daily
/// chats, newest first, as a feed of soft cards. Text-only posts, photos,
/// videos and several-item posts all show. Up to 3 pinned posts sit at the
/// top, in the order they were pinned.
///
/// Only posts from PUBLIC Dailies are listed, on your own profile too, so
/// your tab shows exactly what other people see. Tap the Daily's name on a
/// card to open that Daily; tap a photo or video to see it full screen.
/// Hold a card for a menu: Visit Daily for everyone, and Pin / Delete on
/// your own posts.
///
/// [userId] null means the signed-in user (your own Profile).
///
/// Needs a collection-group index on daily_messages: user_id (ascending) and
/// timestamp (descending).
class DailyPostActivity extends StatefulWidget {
  final String? userId;

  const DailyPostActivity({Key? key, this.userId}) : super(key: key);

  @override
  State<DailyPostActivity> createState() => _DailyPostActivityState();
}

class _PublicDaily {
  final String title;
  final Color color;
  const _PublicDaily(this.title, this.color);
}

class _Post {
  final DailyMessage message;
  final String dailyId;
  final _PublicDaily daily;
  bool pinned;
  _Post(this.message, this.dailyId, this.daily, {this.pinned = false});

  String get id => message.messageId;
}

class _DailyPostActivityState extends State<DailyPostActivity> {
  static const int _pageSize = 30;

  final List<_Post> _posts = [];

  /// dailyId -> the public Daily, or null if it isn't public (or is gone).
  final Map<String, _PublicDaily?> _dailyCache = {};

  DocumentSnapshot? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _failed = false;

  String? get _uid => widget.userId ?? FirebaseAuth.instance.currentUser?.uid;

  bool get _isOwn {
    final me = FirebaseAuth.instance.currentUser?.uid;
    return me != null && _uid == me;
  }

  int get _pinnedCount => _posts.where((p) => p.pinned).length;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    _posts.clear();
    _cursor = null;
    _hasMore = true;
    _failed = false;
    if (mounted) setState(() => _loading = true);
    await _loadPinned();
    await _loadMore();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fillCache(Set<String> ids) async {
    final missing = ids.where((id) => !_dailyCache.containsKey(id)).toList();
    await Future.wait(missing.map((id) async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('public_dailies')
            .doc(id)
            .get();
        final data = doc.data();
        if (!doc.exists || data == null) {
          _dailyCache[id] = null;
          return;
        }
        final isPublic = (data['privacy'] ?? 'Public') == 'Public';
        if (!isPublic) {
          _dailyCache[id] = null;
          return;
        }
        final title = (data['title'] as String?)?.trim();
        final c = data['iconColor'];
        _dailyCache[id] = _PublicDaily(
          (title == null || title.isEmpty) ? 'Daily' : title,
          Color(c is int ? c : 0xFF00BCD4),
        );
      } catch (_) {
        _dailyCache[id] = null;
      }
    }));
  }

  /// Puts the (up to 3) pinned posts at the top, earliest pin first.
  Future<void> _loadPinned() async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;

    final pins = await PinnedPosts.load(uid);
    if (pins.isEmpty) return;

    final loaded = <_Post>[];
    await _fillCache(pins.map((p) => p.dailyId).toSet());

    for (final pin in pins) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('dailies')
            .doc(pin.dailyId)
            .collection('daily_messages')
            .doc(pin.messageId)
            .get();

        if (!doc.exists) {
          // The post was deleted: free up its pin slot (your own pins only).
          if (_isOwn) PinnedPosts.unpin(pin.messageId);
          continue;
        }

        final data = doc.data();
        if (data == null || data['user_id'] != uid) continue;

        final daily = _dailyCache[pin.dailyId];
        if (daily == null) continue; // private Daily: not shown

        final m = DailyMessage.fromJson(data);
        if (!m.hasContent) continue;
        loaded.add(_Post(m, pin.dailyId, daily, pinned: true));
      } catch (_) {
        // Skip a pin that can't be loaded.
      }
    }
    _posts.addAll(loaded);
  }

  /// Pulls pages until a few visible posts are added (some messages sit in
  /// private Dailies and get filtered out) or there's nothing left.
  Future<void> _loadMore() async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      _hasMore = false;
      return;
    }
    if (_loadingMore) return;
    _loadingMore = true;
    if (mounted) setState(() {});

    try {
      var added = 0;
      var rounds = 0;
      while (_hasMore && added < 8 && rounds < 6) {
        rounds++;
        Query<Map<String, dynamic>> q = FirebaseFirestore.instance
            .collectionGroup('daily_messages')
            .where('user_id', isEqualTo: uid)
            .orderBy('timestamp', descending: true)
            .limit(_pageSize);
        if (_cursor != null) q = q.startAfterDocument(_cursor!);

        final snap = await q.get();
        if (snap.docs.isEmpty) {
          _hasMore = false;
          break;
        }
        _cursor = snap.docs.last;
        if (snap.docs.length < _pageSize) _hasMore = false;

        final entries = <MapEntry<DailyMessage, String>>[];
        for (final doc in snap.docs) {
          final dailyId = doc.reference.parent.parent?.id;
          if (dailyId == null) continue;
          try {
            final m = DailyMessage.fromJson(doc.data());
            if (m.hasContent) entries.add(MapEntry(m, dailyId));
          } catch (_) {
            // A malformed message shouldn't break the whole tab.
          }
        }

        await _fillCache(entries.map((e) => e.value).toSet());
        for (final e in entries) {
          final d = _dailyCache[e.value];
          if (d == null) continue;
          // Already shown (a pinned post, or one just unpinned).
          if (_posts.any((p) => p.id == e.key.messageId)) continue;
          _posts.add(_Post(e.key, e.value, d));
          added++;
        }
      }
    } catch (e) {
      print('DailyPostActivity: load error: $e');
      _failed = true;
      _hasMore = false;
    }

    _loadingMore = false;
    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------------------
  // Hold-a-card menu
  // -------------------------------------------------------------------------

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showPostMenu(_Post post) async {
    HapticFeedback.mediumImpact();
    final own = _isOwn;

    // Get the Daily ready while the menu is open, so "Visit Daily" opens
    // it straight away.
    DailyShareLink.prepare(post.dailyId);

    Widget tile(IconData icon, String label, String value,
        {Color? color}) {
      return ListTile(
        leading: Icon(icon, color: color ?? Colors.black87),
        title: Text(
          label,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w500, color: color),
        ),
        onTap: () => Navigator.pop(context, value),
      );
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            tile(Icons.wb_sunny_outlined, 'Visit Daily', 'visit'),
            if (own)
              tile(
                post.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                post.pinned ? 'Unpin from top' : 'Pin to top',
                'pin',
              ),
            if (own)
              tile(Icons.delete_outline, 'Delete post', 'delete',
                  color: Colors.red),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    switch (choice) {
      case 'visit':
        await DailyShareLink.open(context, post.dailyId);
        break;
      case 'pin':
        await _togglePin(post);
        break;
      case 'delete':
        await _confirmDelete(post);
        break;
    }
  }

  Future<void> _togglePin(_Post post) async {
    if (post.pinned) {
      final ok = await PinnedPosts.unpin(post.id);
      if (!ok) {
        _toast('Couldn\'t update the pin. Try again.');
        return;
      }
      if (!mounted) return;
      setState(() {
        // Back into the feed at its place in the newest-first order.
        _posts.remove(post);
        post.pinned = false;
        var at = _pinnedCount;
        while (at < _posts.length &&
            !_posts[at].message.timestamp.isBefore(post.message.timestamp)) {
          at++;
        }
        _posts.insert(at, post);
      });
      return;
    }

    final result = await PinnedPosts.pin(post.dailyId, post.id);
    if (!mounted) return;
    switch (result) {
      case PinResult.full:
        _toast(
            'You can pin up to ${PinnedPosts.maxPins} posts. Unpin one first.');
        break;
      case PinResult.error:
        _toast('Couldn\'t update the pin. Try again.');
        break;
      case PinResult.pinned:
        setState(() {
          _posts.remove(post);
          post.pinned = true;
          _posts.insert(_pinnedCount, post); // after the earlier pins
        });
        break;
    }
  }

  Future<void> _confirmDelete(_Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this post?'),
        content: Text(
            'It will be removed from ${post.daily.title} too, so nobody in '
                'the Daily can see it anymore. This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await MessageStorage.deleteMessage(post.dailyId, post.id);
    if (!mounted) return;
    if (!ok) {
      _toast('Couldn\'t delete the post. Try again.');
      return;
    }
    if (post.pinned) PinnedPosts.unpin(post.id);
    setState(() => _posts.remove(post));
  }

  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        color: Colors.cyan,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 70),
            Icon(
              _failed ? Icons.error_outline : Icons.wb_sunny_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 14),
            Text(
              _failed ? 'Couldn\'t load posts' : 'No posts yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _failed
                    ? 'Pull down to try again.'
                    : (widget.userId == null
                    ? 'What you post in public Dailies shows up here.'
                    : 'Posts in public Dailies show up here.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: Colors.cyan,
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _posts.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: _loadingMore
                    ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.cyan),
                  ),
                )
                    : TextButton(
                  onPressed: _loadMore,
                  child: const Text('Show more',
                      style: TextStyle(color: Colors.cyan)),
                ),
              ),
            );
          }
          final post = _posts[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PostCard(
              key: ValueKey(post.id),
              post: post,
              onLongPress: () => _showPostMenu(post),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PostCard extends StatelessWidget {
  final _Post post;
  final VoidCallback onLongPress;

  const _PostCard({Key? key, required this.post, required this.onLongPress})
      : super(key: key);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _when(DateTime t) {
    final now = DateTime.now();
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    final ap = t.hour >= 12 ? 'PM' : 'AM';
    final date = '${_months[t.month - 1]} ${t.day}'
        '${t.year != now.year ? ', ${t.year}' : ''}';
    return '$date · $h:$mm $ap';
  }

  @override
  Widget build(BuildContext context) {
    final m = post.message;
    final text = m.text?.trim() ?? '';
    final color = post.daily.color;

    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.withOpacity(0.18)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => DailyShareLink.open(context, post.dailyId),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              post.daily.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.chevron_right_rounded,
                              size: 16, color: Colors.grey[500]),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (post.pinned) ...[
                  Icon(Icons.push_pin, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 5),
                ],
                Text(
                  _when(m.timestamp),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                ),
              ],
            ),
            if (m.isFromPrompt) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Daily prompt',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
            if (text.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: Colors.black87,
                ),
              ),
            ],
            if (m.media.isNotEmpty) ...[
              const SizedBox(height: 10),
              _MediaStrip(items: m.media),
            ],
          ],
        ),
      ),
    );
  }
}

/// One tile for a single item, a swipeable strip with "1/3" for several.
class _MediaStrip extends StatefulWidget {
  final List<DailyMediaItem> items;

  const _MediaStrip({required this.items});

  @override
  State<_MediaStrip> createState() => _MediaStripState();
}

class _MediaStripState extends State<_MediaStrip> {
  int _page = 0;

  bool _isRemote(String p) => p.startsWith('http://') || p.startsWith('https://');

  Widget _tile(DailyMediaItem item) {
    final remote = _isRemote(item.path);
    Widget child;
    if (!remote) {
      child = _placeholder(Icons.image_not_supported_outlined);
    } else if (item.isVideo) {
      child = Container(
        color: const Color(0xFF14181C),
        child: const Center(
          child: Icon(Icons.play_circle_fill_rounded,
              size: 54, color: Colors.white70),
        ),
      );
    } else {
      child = Image.network(
        item.path,
        fit: BoxFit.cover,
        width: double.infinity,
        loadingBuilder: (_, w, progress) =>
        progress == null ? w : Container(color: Colors.grey[200]),
        errorBuilder: (_, __, ___) => _placeholder(Icons.broken_image_outlined),
      );
    }

    return GestureDetector(
      onTap: remote ? () => _open(item) : null,
      child: child,
    );
  }

  Widget _placeholder(IconData icon) => Container(
    color: Colors.grey[200],
    child: Center(child: Icon(icon, color: Colors.grey[400], size: 34)),
  );

  void _open(DailyMediaItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _FullScreenMedia(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final many = items.length > 1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            many
                ? PageView.builder(
              itemCount: items.length,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (_, i) => _tile(items[i]),
            )
                : _tile(items.first),
            if (many)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_page + 1}/${items.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenMedia extends StatelessWidget {
  final DailyMediaItem item;

  const _FullScreenMedia({required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: item.isVideo
            ? NetworkVideoPlayer(url: item.path)
            : InteractiveViewer(
          child: Image.network(
            item.path,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48),
          ),
        ),
      ),
    );
  }
}