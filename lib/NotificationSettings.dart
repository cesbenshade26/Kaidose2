import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'GroupAvatar.dart';
import 'SettingsWidgets.dart';
import 'user_service.dart';

/// Settings → Notifications.
///
///   Phone        whether this phone lets Kaidose notify at all
///   Push         one switch for everything, then one per kind
///   Muted chats  chats and groups you muted (Hide notifications in a
///                chat's settings), with Unmute
///
/// Saved on users/{uid}:
///   notifPrefs        {all, messages, reactions, friends, dailies}: false
///                     = off until turned back on (missing = on)
///   notifPausedUntil  {all, messages, reactions}: off until that time
///                     (1 hour / 24 hours), then back on by itself
/// The server checks both before every push (index.js: wantsPush). Notices
/// about your own removed posts always go out.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  AuthorizationStatus? _permission;

  // Switches flip instantly (saved in the background).
  Map<String, bool> _prefs = {};
  Map<String, DateTime> _pausedUntil = {};
  StreamSubscription? _sub;
  // Re-checks every so often so a pause that runs out flips back on here.
  Timer? _tick;

  // The noisy kinds ask "for how long?" when switched off.
  static const Set<String> _canPause = {'all', 'messages', 'reactions'};

  static const _kinds = [
    ('messages', Icons.chat_bubble_outline_rounded, 'Messages',
    'Chats and group chats'),
    ('reactions', Icons.add_reaction_outlined, 'Reactions',
    'Likes, comments and reactions on your posts and messages'),
    ('friends', Icons.person_add_alt_1_outlined, 'Friend requests',
    'New requests, and when yours are accepted'),
    ('dailies', Icons.wb_sunny_outlined, 'Dailies',
    'Invites, join requests, and people joining'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _pausedUntil.isNotEmpty) setState(() {});
    });
    final uid = _uid;
    if (uid != null) {
      _sub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen((d) {
        final data = d.data() ?? {};
        final raw = data['notifPrefs'];
        final paused = data['notifPausedUntil'];
        if (!mounted) return;
        setState(() {
          _prefs = raw is Map
              ? raw.map((k, v) => MapEntry('$k', v != false))
              : {};
          _pausedUntil = {
            if (paused is Map)
              for (final e in paused.entries)
                if (e.value is Timestamp)
                  '${e.key}': (e.value as Timestamp).toDate(),
          };
        });
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  // Back from the phone's Settings app: check again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
      if (mounted) setState(() {});
    }
  }

  Future<void> _checkPermission() async {
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      if (mounted) setState(() => _permission = s.authorizationStatus);
    } catch (_) {}
  }

  Future<void> _askPermission() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
    _checkPermission();
  }

  /// A pause that's still running, or null.
  DateTime? _pause(String key) {
    final t = _pausedUntil[key];
    return (t != null && t.isAfter(DateTime.now())) ? t : null;
  }

  bool _on(String key) => _prefs[key] != false && _pause(key) == null;

  Future<void> _save(Map<String, dynamic> data, VoidCallback undo) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      setState(undo);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save that. Try again.")));
    }
  }

  /// Switched on: back on right away (any pause cleared). Switched off: the
  /// noisy kinds ask for how long first.
  Future<void> _toggle(String key, String label) async {
    final prevPrefs = _prefs;
    final prevPaused = _pausedUntil;
    if (!_on(key)) {
      setState(() {
        _prefs = {..._prefs, key: true};
        _pausedUntil = {..._pausedUntil}..remove(key);
      });
      await _save({
        'notifPrefs': {key: true},
        'notifPausedUntil': {key: FieldValue.delete()},
      }, () {
        _prefs = prevPrefs;
        _pausedUntil = prevPaused;
      });
      return;
    }

    // Off until turned back on, unless a time is picked.
    DateTime? until;
    if (_canPause.contains(key)) {
      final choice = await showMuteForSheet(context, title: 'Turn off $label');
      if (choice == null || !mounted) return; // cancelled
      until = choice.until;
    }
    setState(() {
      if (until == null) {
        _prefs = {..._prefs, key: false};
        _pausedUntil = {..._pausedUntil}..remove(key);
      } else {
        _pausedUntil = {..._pausedUntil, key: until};
      }
    });
    await _save(
      until == null
          ? {
        'notifPrefs': {key: false},
        'notifPausedUntil': {key: FieldValue.delete()},
      }
          : {
        'notifPrefs': {key: true},
        'notifPausedUntil': {key: Timestamp.fromDate(until)},
      },
          () {
        _prefs = prevPrefs;
        _pausedUntil = prevPaused;
      },
    );
  }

  /// "Off until 4:12 PM" while paused, otherwise [normal].
  String? _status(String key, String? normal) {
    final p = _pause(key);
    if (p != null) return 'Off ${untilLabel(p)}';
    return normal;
  }

  Widget _switch(bool value, ValueChanged<bool>? onChanged) => Switch(
    value: value,
    onChanged: onChanged,
    activeColor: Colors.white,
    activeTrackColor: Colors.cyan,
  );

  @override
  Widget build(BuildContext context) {
    final all = _on('all');
    final blocked = _permission == AuthorizationStatus.denied;
    final notAsked = _permission == AuthorizationStatus.notDetermined;

    return SettingsPage(
      title: 'Notifications',
      children: [
        // The phone itself has notifications off for Kaidose.
        if (blocked || notAsked)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notifications_off_outlined, color: Colors.orange[800]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        blocked
                            ? 'Notifications are off on this phone'
                            : "Notifications aren't turned on yet",
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: SettingsStyle.ink),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        blocked
                            ? 'Turn them on in your phone\'s Settings → Kaidose → '
                            'Notifications. The switches below only work '
                            'once they\'re on.'
                            : 'Allow them so the switches below can work.',
                        style: const TextStyle(
                            fontSize: 13, height: 1.35, color: Color(0xFF6B5A3A)),
                      ),
                      if (notAsked) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _askPermission,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.orange[700],
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Turn on'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

        SettingsGroup(
          title: 'Push notifications',
          children: [
            SettingsTile(
              icon: all
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_paused_outlined,
              title: 'All notifications',
              subtitle: _status('all', all ? null : 'Off. Nothing will notify you.'),
              trailing: _switch(all, (_) => _toggle('all', 'all notifications')),
              onTap: () => _toggle('all', 'all notifications'),
            ),
          ],
        ),

        SettingsGroup(
          footer: 'Notices about your own posts (like a post being removed) '
              'always come through.',
          children: [
            for (final k in _kinds)
              Opacity(
                opacity: all ? 1 : 0.45,
                child: SettingsTile(
                  icon: k.$2,
                  title: k.$3,
                  subtitle: _status(k.$1, k.$4),
                  trailing: _switch(_on(k.$1),
                      all ? (_) => _toggle(k.$1, k.$3.toLowerCase()) : null),
                  onTap: all ? () => _toggle(k.$1, k.$3.toLowerCase()) : null,
                ),
              ),
          ],
        ),

        SettingsGroup(
          title: 'Chats',
          footer: 'To mute one chat or group, open it, tap its name, and turn '
              'on Hide notifications.',
          children: [
            SettingsTile(
              icon: Icons.notifications_off_outlined,
              title: 'Muted chats',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MutedChatsScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Muted chats ──────────────────────────────────────────────────────────────

/// Every chat and group you've muted, with Unmute. Two kinds:
///   until turned back on  the chat's own mutedBy list
///   for a while           users/{me}/chat_mutes/{direct_<uid> | group_<id>}
///                         with an `until` time (gone from here once it
///                         passes)
class MutedChatsScreen extends StatefulWidget {
  const MutedChatsScreen({Key? key}) : super(key: key);

  @override
  State<MutedChatsScreen> createState() => _MutedChatsScreenState();
}

class _MutedChatsScreenState extends State<MutedChatsScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Timed mutes drop off the list when they run out.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return const SettingsPage(title: 'Muted chats', children: []);
    final db = FirebaseFirestore.instance;
    // Groups can only be listed by membership (security rules), so muted
    // ones are picked out here.
    final groups = db
        .collection('groupChats')
        .where('memberIds', arrayContains: me)
        .snapshots();
    final chats =
    db.collection('chats').where('mutedBy', arrayContains: me).snapshots();
    final timed =
    db.collection('users').doc(me).collection('chat_mutes').snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: groups,
      builder: (context, g) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: chats,
        builder: (context, c) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: timed,
          builder: (context, t) {
            final now = DateTime.now();
            final groupDocs = g.data?.docs ?? [];
            final groupById = {for (final d in groupDocs) d.id: d};

            // Timed mutes still running, by key.
            final running = <String, (DocumentReference, DateTime)>{};
            for (final d in t.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
              final until = (d.data()['until'] as Timestamp?)?.toDate();
              if (until != null && until.isAfter(now)) {
                running[d.id] = (d.reference, until);
              }
            }

            final rowsDirect = <Widget>[
              for (final d in c.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                _DirectRow(
                  friendUid: _otherIn(d.data(), me),
                  until: null,
                  onUnmute: () => d.reference.update({
                    'mutedBy': FieldValue.arrayRemove([me]),
                  }),
                ),
              for (final e in running.entries)
                if (e.key.startsWith('direct_'))
                  _DirectRow(
                    friendUid: e.key.substring('direct_'.length),
                    until: e.value.$2,
                    onUnmute: () => e.value.$1.delete(),
                  ),
            ];
            final rowsGroup = <Widget>[
              for (final d in groupDocs)
                if ((d.data()['mutedBy'] as List? ?? const []).contains(me))
                  _GroupRow(
                    data: d.data(),
                    me: me,
                    until: null,
                    onUnmute: () => d.reference.update({
                      'mutedBy': FieldValue.arrayRemove([me]),
                    }),
                  ),
              for (final e in running.entries)
                if (e.key.startsWith('group_') &&
                    groupById.containsKey(e.key.substring('group_'.length)))
                  _GroupRow(
                    data: groupById[e.key.substring('group_'.length)]!.data(),
                    me: me,
                    until: e.value.$2,
                    onUnmute: () => e.value.$1.delete(),
                  ),
            ];
            final loading = !g.hasData || !c.hasData || !t.hasData;

            return SettingsPage(
              title: 'Muted chats',
              children: [
                if (loading)
                  Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                        child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC)))),
                  )
                else if (rowsDirect.isEmpty && rowsGroup.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(
                      child: Text("You haven't muted any chats",
                          style: TextStyle(
                              fontSize: 15, color: SettingsStyle.subtle)),
                    ),
                  )
                else ...[
                    if (rowsDirect.isNotEmpty)
                      SettingsGroup(title: 'Chats', children: rowsDirect),
                    if (rowsGroup.isNotEmpty)
                      SettingsGroup(title: 'Group chats', children: rowsGroup),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  static String _otherIn(Map<String, dynamic> chat, String me) {
    final people = List<String>.from(chat['participants'] ?? const []);
    return people.firstWhere((p) => p != me, orElse: () => '');
  }
}

Widget _unmuteButton(VoidCallback onTap) => TextButton(
  onPressed: onTap,
  style: TextButton.styleFrom(
    foregroundColor: Colors.cyan[700],
    padding: const EdgeInsets.symmetric(horizontal: 10),
  ),
  child: const Text('Unmute',
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
);

Widget _row(Widget avatar, String name, DateTime? until, Widget action) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: SettingsStyle.ink)),
                const SizedBox(height: 1),
                Text(
                  until == null
                      ? 'Until you turn it back on'
                      : 'Muted ${untilLabel(until)}',
                  style: TextStyle(
                      fontSize: 12.5, color: SettingsStyle.subtle),
                ),
              ],
            ),
          ),
          action,
        ],
      ),
    );

class _DirectRow extends StatelessWidget {
  final String friendUid;
  final DateTime? until;
  final VoidCallback onUnmute;
  const _DirectRow(
      {required this.friendUid, required this.until, required this.onUnmute});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: friendUid.isEmpty ? null : UserService().getUserById(friendUid),
      builder: (context, snap) => _row(
        MemberAvatar(userId: friendUid, size: 40),
        snap.data?.username ?? ' ',
        until,
        _unmuteButton(onUnmute),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final String me;
  final DateTime? until;
  final VoidCallback onUnmute;
  const _GroupRow({
    required this.data,
    required this.me,
    required this.until,
    required this.onUnmute,
  });

  @override
  Widget build(BuildContext context) {
    final names = Map<String, dynamic>.from(data['memberUsernames'] ?? const {});
    final custom = (data['name'] as String?)?.trim() ?? '';
    final name = custom.isNotEmpty
        ? custom
        : names.entries
        .where((e) => e.key != me)
        .map((e) => '${e.value}')
        .take(3)
        .join(', ');
    final firstOther = (List<String>.from(data['memberIds'] ?? const []))
        .firstWhere((id) => id != me, orElse: () => me);
    return _row(
      MemberAvatar(userId: firstOther, size: 40),
      name.isEmpty ? 'Group chat' : name,
      until,
      _unmuteButton(onUnmute),
    );
  }
}