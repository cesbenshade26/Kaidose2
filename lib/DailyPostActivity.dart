import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'AppColors.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show DefaultCacheManager;
import 'package:flutter/services.dart';
import 'DailyShare.dart';
import 'MessageStorage.dart';
import 'NetworkVideoPlayer.dart';
import 'MediaAspect.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:io';
import 'PinnedPosts.dart';
import 'SendDailyMessage.dart';
import 'DataSaver.dart';
import 'GroupAvatar.dart';

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

  /// Gets the videos (and card shapes) of the next few posts ready, so
  /// they're already playing when they scroll in.
  void _warmAhead(int index) {
    for (var j = index; j <= index + 3 && j < _posts.length; j++) {
      for (final item in _posts[j].message.media.take(2)) {
        if (!item.path.startsWith('http')) continue;
        MediaAspect.of(item.path, isVideo: item.isVideo, thumb: item.thumb);
        if (item.isVideo) DailyPostVideoCache.warm(item.path);
      }
    }
  }

  /// Your own top post's video stays ready for the next time Profile opens.
  void _keepTopReady() {
    if (!_isOwn) return;
    DailyPostVideoCache.keepTop(_topVideoUrl(_posts));
  }

  static String? _topVideoUrl(List<_Post> posts) {
    if (posts.isEmpty) return null;
    final media = posts.first.message.media;
    if (media.isEmpty || !media.first.isVideo) return null;
    final url = media.first.path;
    return url.startsWith('http') ? url : null;
  }

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
    _keepTopReady();
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
          // Removed by moderation: not shown on profiles either.
          if (doc.data()['hidden'] == true) continue;
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
        leading: Icon(icon, color: color ?? kc.text),
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
      backgroundColor: kc.surface,
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
                color: kc.grey(300),
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
      return Center(child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))));
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        color: kc.adapt(const Color(0xFF8A8F98)),
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 70),
            Icon(
              _failed ? Icons.error_outline : Icons.wb_sunny_outlined,
              size: 64,
              color: kc.grey(400),
            ),
            const SizedBox(height: 14),
            Text(
              _failed ? 'Couldn\'t load posts' : 'No posts yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: kc.grey(700),
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
                style: TextStyle(fontSize: 14, color: kc.grey(500)),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: kc.adapt(const Color(0xFF8A8F98)),
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
                    ? Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kc.adapt(const Color(0xFFB0B5BC))),
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
          _warmAhead(i);
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

/// The same card, for posts shown somewhere else (saved posts in Archives
/// and a Daily's Saved). Shows who posted it, since it's not your profile.
class DailyPostCard extends StatelessWidget {
  final DailyMessage message;
  final String dailyId;
  final String dailyTitle;
  final Color color;

  /// Show the Daily's name (off inside that Daily's own Saved).
  final bool showDaily;
  final VoidCallback? onLongPress;

  const DailyPostCard({
    Key? key,
    required this.message,
    required this.dailyId,
    required this.dailyTitle,
    this.color = Colors.cyan,
    this.showDaily = true,
    this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _PostCard(
      post: _Post(message, dailyId, _PublicDaily(dailyTitle, color)),
      onLongPress: onLongPress ?? () {},
      showAuthor: true,
      showDaily: showDaily,
    );
  }
}

/// Starts the next few posts' videos loading (for lists of
/// [DailyPostCard]s).
void warmDailyPosts(List<DailyMessage> posts, int index) {
  for (var j = index; j <= index + 3 && j < posts.length; j++) {
    for (final item in posts[j].media.take(2)) {
      if (!item.path.startsWith('http')) continue;
      MediaAspect.of(item.path, isVideo: item.isVideo, thumb: item.thumb);
      if (item.isVideo) DailyPostVideoCache.warm(item.path);
    }
  }
}

class _PostCard extends StatelessWidget {
  final _Post post;
  final VoidCallback onLongPress;
  final bool showAuthor;
  final bool showDaily;

  const _PostCard({
    Key? key,
    required this.post,
    required this.onLongPress,
    this.showAuthor = false,
    this.showDaily = true,
  }) : super(key: key);

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
          color: kc.grey(50),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.withOpacity(0.18)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAuthor) ...[
              Row(
                children: [
                  MemberAvatar(
                    userId: m.userId,
                    size: 28,
                    openProfileOnTap: true,
                    username: m.username,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      m.username ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kc.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                if (!showDaily) const Spacer(),
                if (showDaily)
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
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: kc.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded,
                                size: 16, color: kc.grey(500)),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                if (post.pinned) ...[
                  Icon(Icons.push_pin, size: 14, color: kc.grey(600)),
                  const SizedBox(width: 5),
                ],
                Text(
                  _when(m.timestamp),
                  style: TextStyle(fontSize: 11.5, color: kc.grey(500)),
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
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: kc.text,
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

  Widget _tile(DailyMediaItem item, {bool active = true}) {
    final remote = _isRemote(item.path);
    Widget child;
    if (!remote) {
      child = _placeholder(Icons.image_not_supported_outlined);
    } else if (item.isVideo) {
      // Plays right here in the list (no extra screen).
      return InlineVideo(
        key: ValueKey(item.path),
        url: item.path,
        thumb: item.thumb,
        active: active,
      );
    } else {
      child = Image(
        image: CachedNetworkImageProvider(item.path),
        fit: BoxFit.cover,
        width: double.infinity,
        loadingBuilder: (_, w, progress) =>
        progress == null ? w : Container(color: kc.grey(200)),
        errorBuilder: (_, __, ___) => _placeholder(Icons.broken_image_outlined),
      );
    }

    return GestureDetector(
      onTap: remote ? () => _open(item) : null,
      child: child,
    );
  }

  Widget _placeholder(IconData icon) => Container(
    color: kc.grey(200),
    child: Center(child: Icon(icon, color: kc.grey(400), size: 34)),
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
    if (items.length == 1) return _single(items.first);
    return _strip(items);
  }

  /// One photo/video: shown in its own shape. Tall ones get narrower (and
  /// sit on the left) instead of being cropped to a wide box.
  Widget _single(DailyMediaItem item) {
    final maxH = MediaQuery.of(context).size.height * 0.5;
    return LayoutBuilder(builder: (context, box) {
      return MediaAspectBuilder(
        path: item.path,
        isVideo: item.isVideo,
        thumb: item.thumb,
        builder: (context, aspect) {
          final size = MediaAspect.box(aspect,
              maxW: box.maxWidth, maxH: maxH, minW: box.maxWidth * 0.5);
          return Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: _tile(item),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _strip(List<DailyMediaItem> items) {
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
              itemBuilder: (_, i) => _tile(items[i], active: i == _page),
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
          child: Image(
            image: CachedNetworkImageProvider(item.path),
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

/// A video that plays inline in a list (profile posts, Daily messages):
/// starts (muted) when it's mostly on screen, pauses when it scrolls away
/// or another screen covers it. Tap for sound; the speaker in the corner
/// shows which. Always fills its box edge to edge (cropping a hair if the
/// box's shape is slightly off), so there are never black bars.
/// [url] can be a download URL or a local file path (a video still
/// uploading).
class InlineVideo extends StatefulWidget {
  final String url;
  final String? thumb;
  final bool active; // false for a page of a strip that isn't showing

  const InlineVideo({Key? key, required this.url, this.thumb, this.active = true})
      : super(key: key);

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> with WidgetsBindingObserver {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _muted = true;
  bool _visible = false;
  ScrollPosition? _position;
  // Read during build (where these lookups belong), used by _checkVisible.
  Size _screen = Size.zero;
  bool _onTop = true;
  bool _ticking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  bool get _local => !widget.url.startsWith('http');

  Future<void> _init() async {
    if (_local) {
      final c = VideoPlayerController.file(File(widget.url));
      try {
        await c.initialize().timeout(const Duration(seconds: 12));
        await c.setLooping(true);
        await c.setVolume(0);
      } catch (e) {
        debugPrint('InlineVideo: local video failed ${widget.url} -> $e');
        try {
          c.dispose();
        } catch (_) {}
        if (mounted) setState(() => _failed = true);
        return;
      }
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _c = c);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisible());
      return;
    }
    // Usually already loaded by the preloader, so it starts instantly.
    final c = await DailyPostVideoCache.take(widget.url);
    if (!mounted) {
      if (c != null) DailyPostVideoCache.giveBack(widget.url, c);
      return;
    }
    if (c == null) {
      setState(() => _failed = true);
      return;
    }
    await c.setVolume(_muted ? 0 : 1);
    setState(() => _c = c);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisible());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != _position) {
      _position?.removeListener(_checkVisible);
      _position = pos;
      _position?.addListener(_checkVisible);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisible());
  }

  @override
  void didUpdateWidget(InlineVideo old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _checkVisible();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _c?.pause();
    } else {
      _checkVisible();
    }
  }

  /// Plays when at least 60% of it is on screen, this page is the one
  /// showing, and nothing is pushed on top (e.g. a profile opened).
  void _checkVisible() {
    if (!mounted) return;
    final c = _c;
    final box = context.findRenderObject() as RenderBox?;
    if (c == null || box == null || !box.attached || !box.hasSize) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    final shown = rect.intersect(Offset.zero & _screen);
    final fraction = (shown.width <= 0 || shown.height <= 0)
        ? 0.0
        : (shown.width * shown.height) / (rect.width * rect.height);
    final visible = fraction >= 0.6 && widget.active && _onTop && _ticking;
    if (visible == _visible && visible == c.value.isPlaying) return;
    _visible = visible;
    try {
      visible ? c.play() : c.pause();
    } catch (_) {}
  }

  void _toggleSound() {
    // Couldn't load: tap tries again.
    if (_failed) {
      setState(() => _failed = false);
      _init();
      return;
    }
    final c = _c;
    if (c == null) return;
    setState(() => _muted = !_muted);
    c.setVolume(_muted ? 0 : 1);
    if (!c.value.isPlaying) c.play();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _position?.removeListener(_checkVisible);
    final c = _c;
    _c = null;
    // After this frame (the player may still be painting this one), hand
    // it back so scrolling back up doesn't load it again.
    final url = widget.url;
    final local = _local;
    Future.microtask(() {
      if (c == null) return;
      local ? c.dispose() : DailyPostVideoCache.giveBack(url, c);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _screen = MediaQuery.of(context).size;
    _onTop = ModalRoute.of(context)?.isCurrent ?? true;
    _ticking = TickerMode.of(context);
    // Re-check after any rebuild (e.g. coming back from another screen).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisible());
    final c = _c;
    final thumb = widget.thumb;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleSound,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFF14181C)),
          if (c == null && thumb != null && thumb.isNotEmpty)
            Image(
                image: CachedNetworkImageProvider(thumb),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          if (c != null)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            ),
          if (c == null && !_failed)
            const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white70),
              ),
            ),
          if (_failed)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white70, size: 34),
                  SizedBox(height: 6),
                  Text("Couldn't load video. Tap to retry.",
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          if (c != null)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ready-to-play videos for Daily posts on profiles, the same idea as the
/// Clips preloader: the next few posts' videos load while you scroll, the
/// ones you scroll past stay ready for a bit, and your own top post's video
/// is kept ready at all times (warmed at sign-in) so it plays the moment
/// you open Profile.
class DailyPostVideoCache {
  DailyPostVideoCache._();

  static const int _max = 4; // besides the top post's video

  // url -> ready controller (oldest first). Not in here = in use or unloaded.
  static final Map<String, VideoPlayerController> _ready = {};
  static final Map<String, Future<VideoPlayerController?>> _loading = {};

  // Controllers handed out right now (never disposed by the cache), and how
  // many players are using or waiting on each url.
  static final Set<VideoPlayerController> _out = {};
  static final Map<String, int> _users = {};
  static String? _top;

  static bool _inUse(String url) => (_users[url] ?? 0) > 0;

  static void _release(String url) {
    final n = (_users[url] ?? 1) - 1;
    if (n <= 0) {
      _users.remove(url);
    } else {
      _users[url] = n;
    }
  }

  /// How long streaming gets to start before we fall back to downloading
  /// the whole video and playing it from the phone.
  static const Duration _streamLimit = Duration(seconds: 8);

  /// Videos that wouldn't stream this session: go straight to downloading.
  static final Set<String> _streamFails = {};

  static Future<VideoPlayerController?> _create(String url) async {
    // 1. Already downloaded once (kept across launches): play that file.
    try {
      final cached = await DefaultCacheManager()
          .getFileFromCache(url)
          .timeout(const Duration(seconds: 3));
      if (cached != null && await cached.file.exists()) {
        final c = await _openFile(cached.file, url);
        if (c != null) return c;
      }
    } catch (_) {}

    // 2. Stream it.
    if (!_streamFails.contains(url)) {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await c.initialize().timeout(_streamLimit);
        await c.setLooping(true);
        await c.setVolume(0);
        return c;
      } catch (e) {
        debugPrint('DailyPostVideoCache: streaming failed, downloading '
            'instead. $url -> $e');
        _streamFails.add(url);
        _disposeQuietly(c);
      }
    }

    // 3. Some uploads won't stream on iPhone (e.g. an iPhone .MOV that was
    // labelled as .mp4 when uploaded). Download it and play the file,
    // which always works; it stays cached for next time.
    try {
      final file = await DefaultCacheManager()
          .getSingleFile(url)
          .timeout(const Duration(seconds: 90));
      return await _openFile(file, url);
    } catch (e) {
      debugPrint('DailyPostVideoCache: download failed $url -> $e');
      return null;
    }
  }

  static Future<VideoPlayerController?> _openFile(File file, String url) async {
    final c = VideoPlayerController.file(file);
    try {
      await c.initialize().timeout(const Duration(seconds: 12));
      await c.setLooping(true);
      await c.setVolume(0);
      return c;
    } catch (e) {
      debugPrint('DailyPostVideoCache: file play failed $url -> $e');
      _disposeQuietly(c);
      return null;
    }
  }

  static void _disposeQuietly(VideoPlayerController c) {
    Future(() async {
      try {
        await c.dispose();
      } catch (_) {}
    });
  }

  /// One load per url at a time; whoever asks while it's loading gets it.
  static Future<VideoPlayerController?> _load(String url) {
    // The block body matters: `() => _loading.remove(url)` would return
    // this very future, and whenComplete would wait on itself forever
    // (the video then never finished loading).
    return _loading[url] ??= _create(url).whenComplete(() {
      _loading.remove(url);
    });
  }

  /// Start loading [url] if it isn't ready or playing already.
  static void warm(String url) {
    // Data saver on cellular: load when it's actually played, not ahead.
    if (DataSaver.active) return;
    if (_ready.containsKey(url) || _inUse(url) || _loading.containsKey(url)) {
      return;
    }
    _load(url).then((c) {
      if (c == null) return;
      // A player asked for it while it loaded: it's theirs now. (This used
      // to dispose it out from under them: "used after being disposed".)
      if (_out.contains(c) || _inUse(url)) return;
      if (_ready.containsKey(url)) {
        c.dispose(); // another copy is already parked
        return;
      }
      _ready[url] = c;
      _trim();
    });
  }

  /// A ready controller for [url] (loaded now if needed), only for you.
  /// Hand it back with [giveBack] when done.
  static Future<VideoPlayerController?> take(String url) async {
    _users[url] = (_users[url] ?? 0) + 1;
    var c = _ready.remove(url);
    if (c == null) {
      c = await _load(url);
      // The same video on screen twice: the other player got that one, so
      // this one gets its own.
      if (c != null && _out.contains(c)) c = await _create(url);
    }
    if (c == null) {
      _release(url);
      return null;
    }
    _out.add(c);
    return c;
  }

  static void giveBack(String url, VideoPlayerController c) {
    _out.remove(c);
    _release(url);
    try {
      c.pause();
      c.setVolume(0);
      c.seekTo(Duration.zero);
    } catch (_) {
      return;
    }
    final old = _ready.remove(url);
    if (old != null && old != c) old.dispose();
    _ready[url] = c; // newest
    _trim();
  }

  /// The video at the top of YOUR posts: always kept ready.
  static void keepTop(String? url) {
    _top = url;
    if (url != null) warm(url);
    _trim();
  }

  static void _trim() {
    while (_ready.keys.where((k) => k != _top).length > _max) {
      final oldest = _ready.keys.firstWhere((k) => k != _top);
      _ready.remove(oldest)?.dispose();
    }
  }

  /// Sign-out: drop everything.
  static void clear() {
    for (final c in _ready.values) {
      c.dispose();
    }
    _ready.clear();
    _top = null;
  }

  static StreamSubscription<User?>? _auth;

  /// Call once at launch: whenever someone signs in, finds the top post on
  /// their profile and, if it's a video, gets it ready in the background.
  static void startWarmingTopPost() {
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      clear();
      if (user != null) _warmTopFor(user.uid);
    });
  }

  static Future<void> _warmTopFor(String uid) async {
    try {
      final db = FirebaseFirestore.instance;
      Future<bool> isPublic(String dailyId) async {
        final d = await db.collection('public_dailies').doc(dailyId).get();
        return d.exists && (d.data()?['privacy'] ?? 'Public') == 'Public';
      }

      // Pinned posts come first on the profile...
      for (final pin in await PinnedPosts.load(uid)) {
        final doc = await db
            .collection('dailies')
            .doc(pin.dailyId)
            .collection('daily_messages')
            .doc(pin.messageId)
            .get();
        final data = doc.data();
        if (data == null || data['user_id'] != uid) continue;
        if (!await isPublic(pin.dailyId)) continue;
        keepTop(_firstVideo(DailyMessage.fromJson(data)));
        return;
      }
      // ...then the newest post in a public Daily.
      final snap = await db
          .collectionGroup('daily_messages')
          .where('user_id', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();
      for (final doc in snap.docs) {
        final dailyId = doc.reference.parent.parent?.id;
        if (dailyId == null || doc.data()['hidden'] == true) continue;
        final m = DailyMessage.fromJson(doc.data());
        if (!m.hasContent || !await isPublic(dailyId)) continue;
        keepTop(_firstVideo(m));
        return;
      }
    } catch (e) {
      print('DailyPostVideoCache: top post warm-up skipped: $e');
    }
  }

  static String? _firstVideo(DailyMessage m) {
    if (m.media.isEmpty || !m.media.first.isVideo) return null;
    final url = m.media.first.path;
    return url.startsWith('http') ? url : null;
  }
}