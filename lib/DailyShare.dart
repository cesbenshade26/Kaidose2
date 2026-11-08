import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'DailyData.dart';
import 'GroupAvatar.dart';
import 'GroupChatService.dart';
import 'InsideDaily.dart';
import 'MessageStorage.dart';
import 'SearchService.dart';
import 'message_service.dart';
import 'user_service.dart';

/// One photo or video being shared out of a Daily (always a remote URL).
class SharedMediaItem {
  final String url;
  final bool isVideo;
  const SharedMediaItem({required this.url, required this.isVideo});
}

/// What is being sent from a Daily into chats.
class SharedDailyContent {
  final String dailyId;
  final String dailyTitle;
  final bool isPrivate;
  final String text;
  final List<SharedMediaItem> media;

  const SharedDailyContent({
    required this.dailyId,
    required this.dailyTitle,
    required this.isPrivate,
    required this.text,
    required this.media,
  });

  /// The "source" tag stored on the chat message. A private Daily's title is
  /// left out so it isn't revealed to people outside it.
  Map<String, dynamic> get sourceTag => {
    'dailyId': dailyId,
    'dailyTitle': isPrivate ? '' : dailyTitle,
    'private': isPrivate,
  };
}

/// Shared helpers for the "Sent from ___ Daily" tag on chat messages.
class DailyShareLink {
  /// "Robotics Daily", or "a private Daily" (shown after "SENT FROM").
  static String? labelFor(Map? source) {
    if (source == null) return null;
    final title = (source['dailyTitle'] as String?)?.trim() ?? '';
    final isPrivate = source['private'] == true || title.isEmpty;
    return isPrivate ? 'a private Daily' : '$title Daily';
  }

  // Daily lookups that were started ahead of time (see [prepare]).
  static final Map<String, _Lookup> _lookups = {};
  static const Duration _lookupTtl = Duration(seconds: 90);

  /// Starts looking a Daily up in the background so [open] can go straight
  /// to it. Call it as soon as the person is likely to open the Daily (for
  /// example when they hold a post). Also warms that Daily's messages.
  static void prepare(String dailyId) {
    _resolve(dailyId);
    MessageStorage.prefetch(dailyId);
  }

  static Future<_Resolved> _resolve(String dailyId) {
    final cached = _lookups[dailyId];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _lookupTtl) {
      return cached.future;
    }
    final future = _lookup(dailyId);
    _lookups[dailyId] = _Lookup(future, DateTime.now());
    // Don't keep "not found" answers around.
    future.then((r) {
      if (r.daily == null) _lookups.remove(dailyId);
    });
    return future;
  }

  static Future<_Resolved> _lookup(String dailyId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final db = FirebaseFirestore.instance;
    DailyData? daily;
    bool mine = false;
    try {
      // Check both places at the same time.
      final results = await Future.wait([
        uid == null
            ? Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null)
            : db
            .collection('users')
            .doc(uid)
            .collection('dailies')
            .doc(dailyId)
            .get(),
        db.collection('public_dailies').doc(dailyId).get(),
      ]);
      final mineDoc = results[0];
      final publicDoc = results[1];
      if (mineDoc != null && mineDoc.exists) {
        daily = DailyData.fromFirestore(mineDoc);
        mine = true;
      } else if (publicDoc != null && publicDoc.exists) {
        daily = DailyData.fromFirestore(publicDoc);
      }
    } catch (e) {
      print('DailyShareLink: open error: $e');
    }
    return _Resolved(daily, mine);
  }

  /// Opens the Daily a chat message came from, if the viewer is allowed in.
  static Future<void> open(BuildContext context, String dailyId) async {
    final resolved = await _resolve(dailyId);
    final daily = resolved.daily;
    final mine = resolved.mine;
    if (!context.mounted) return;

    if (daily == null || (!mine && daily.privacy != 'Public')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This Daily is private or no longer available'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InsideDaily(daily: daily)),
    );
  }
}

class _Resolved {
  final DailyData? daily;
  final bool mine;
  const _Resolved(this.daily, this.mine);
}

class _Lookup {
  final Future<_Resolved> future;
  final DateTime at;
  const _Lookup(this.future, this.at);
}

/// Bottom sheet for picking which chats to send a Daily message to.
class ShareToChatSheet extends StatefulWidget {
  final SharedDailyContent content;

  const ShareToChatSheet({Key? key, required this.content}) : super(key: key);

  static Future<void> show(BuildContext context, SharedDailyContent content) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareToChatSheet(content: content),
    );
  }

  @override
  State<ShareToChatSheet> createState() => _ShareToChatSheetState();
}

class _ShareToChatSheetState extends State<ShareToChatSheet> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _note = TextEditingController();

  List<PersonResult> _friends = [];
  List<GroupChat> _groups = [];
  String _myName = 'Someone';
  bool _loading = true;
  bool _sending = false;

  /// 'u:<uid>' for a friend, 'g:<groupId>' for a group chat.
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = FirebaseAuth.instance.currentUser?.uid ?? '';
      final results = await Future.wait([
        SearchService.myFriends(),
        GroupChatService().getMyGroups().first,
        UserService().getUserById(me),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = results[0] as List<PersonResult>;
        _groups = results[1] as List<GroupChat>;
        final name = (results[2] as KaidoseUser?)?.username;
        if (name != null && name.isNotEmpty) _myName = name;
        _loading = false;
      });
    } catch (e) {
      print('ShareToChatSheet: load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  // ---------------------------------------------------------------- send

  Future<bool> _sendToFriend(String uid) async {
    final c = widget.content;
    final svc = MessageService();
    var ok = true;

    if (c.media.isEmpty) {
      ok = await svc.sendChatMessage(
        recipientUserId: uid,
        text: c.text,
        senderUsername: _myName,
        metadata: {'source': c.sourceTag},
      );
    } else {
      for (var i = 0; i < c.media.length; i++) {
        final m = c.media[i];
        final sent = await svc.sendChatMessage(
          recipientUserId: uid,
          text: i == 0 ? c.text : '',
          senderUsername: _myName,
          metadata: {
            'type': m.isVideo ? 'clip' : 'image',
            m.isVideo ? 'videoUrl' : 'imageUrl': m.url,
            'source': c.sourceTag,
          },
        );
        ok = ok && sent;
      }
    }

    final note = _note.text.trim();
    if (note.isNotEmpty) {
      await svc.sendChatMessage(
        recipientUserId: uid,
        text: note,
        senderUsername: _myName,
      );
    }
    return ok;
  }

  Future<bool> _sendToGroup(String groupId) async {
    final c = widget.content;
    final svc = GroupChatService();
    try {
      if (c.media.isEmpty) {
        await svc.sendSharedFromDaily(
          groupId: groupId,
          senderUsername: _myName,
          text: c.text,
          source: c.sourceTag,
        );
      } else {
        for (var i = 0; i < c.media.length; i++) {
          final m = c.media[i];
          await svc.sendSharedFromDaily(
            groupId: groupId,
            senderUsername: _myName,
            text: i == 0 ? c.text : '',
            imageUrl: m.isVideo ? null : m.url,
            videoUrl: m.isVideo ? m.url : null,
            source: c.sourceTag,
          );
        }
      }
      final note = _note.text.trim();
      if (note.isNotEmpty) {
        await svc.sendMessage(
          groupId: groupId,
          text: note,
          senderUsername: _myName,
        );
      }
      return true;
    } catch (e) {
      print('ShareToChatSheet: group send error: $e');
      return false;
    }
  }

  Future<void> _send() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    var failed = 0;
    for (final key in _selected.toList()) {
      final id = key.substring(2);
      final ok = key.startsWith('u:') ? await _sendToFriend(id) : await _sendToGroup(id);
      if (!ok) failed++;
    }

    navigator.pop();
    final total = _selected.length;
    messenger.showSnackBar(SnackBar(
      content: Text(failed == 0
          ? (total == 1 ? 'Sent' : 'Sent to $total chats')
          : 'Couldn\'t send to $failed of $total chats'),
      duration: const Duration(seconds: 2),
    ));
  }

  // ------------------------------------------------------------------ UI

  Widget _preview() {
    final c = widget.content;
    final first = c.media.isEmpty ? null : c.media.first;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (first != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 52,
                height: 52,
                child: first.isVideo
                    ? Container(
                  color: Colors.black87,
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 30),
                )
                    : Image.network(first.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.grey[300])),
              ),
            )
          else
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.chat_bubble_outline,
                  color: Colors.cyan[700], size: 24),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.isPrivate ? 'From a private Daily' : 'From ${c.dailyTitle} Daily',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.cyan[800]),
                ),
                if (c.text.isNotEmpty || c.media.length > 1) ...[
                  const SizedBox(height: 2),
                  Text(
                    c.text.isNotEmpty
                        ? c.text
                        : '${c.media.length} photos & videos',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkCircle(bool on) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? Colors.cyan : Colors.transparent,
        border: Border.all(
            color: on ? Colors.cyan : Colors.grey[400]!, width: 1.6),
      ),
      child: on
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }

  Widget _row({
    required String key,
    required Widget avatar,
    required String title,
    String? subtitle,
  }) {
    final on = _selected.contains(key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                        TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                ],
              ),
            ),
            _checkCircle(on),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 14, bottom: 4),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Colors.grey[500])),
    );
  }

  Widget _list() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }
    final q = _search.text.trim().toLowerCase();
    final me = FirebaseAuth.instance.currentUser?.uid;

    final groups = _groups
        .where((g) => q.isEmpty || g.displayName(me).toLowerCase().contains(q))
        .toList();
    final friends = _friends
        .where((p) => q.isEmpty || p.user.username.toLowerCase().contains(q))
        .toList();

    if (groups.isEmpty && friends.isEmpty) {
      return Center(
        child: Text(
          _friends.isEmpty && _groups.isEmpty
              ? 'Add friends to start sharing'
              : 'No matches',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        if (groups.isNotEmpty) _sectionLabel('Groups'),
        for (final g in groups)
          _row(
            key: 'g:${g.id}',
            avatar: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.groups_rounded, color: Colors.cyan[700]),
            ),
            title: g.displayName(me),
            subtitle: '${g.memberIds.length} members',
          ),
        if (friends.isNotEmpty) _sectionLabel('Friends'),
        for (final p in friends)
          _row(
            key: 'u:${p.user.uid}',
            avatar: MemberAvatar(userId: p.user.uid, size: 44),
            title: p.user.username,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: SizedBox(
          height: (height * 0.82).clamp(0.0, height - keyboard - 60),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Send to',
                      style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  _preview(),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  Expanded(child: _list()),
                  if (_selected.isNotEmpty) ...[
                    TextField(
                      controller: _note,
                      maxLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Add a message (optional)',
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _selected.isEmpty || _sending ? null : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        disabledBackgroundColor: Colors.grey[300],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25)),
                      ),
                      child: _sending
                          ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                          : Text(
                        _selected.isEmpty
                            ? 'Choose who to send to'
                            : (_selected.length == 1
                            ? 'Send'
                            : 'Send to ${_selected.length} chats'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}