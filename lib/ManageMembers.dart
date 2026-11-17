import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'DailyModeration.dart';
import 'DailyBan.dart';
import 'GroupAvatar.dart';
import 'user_service.dart';
import 'UserProfileScreen.dart';
import 'ManageDaily.dart' show kManageInk;

/// One person in the list.
class _Person {
  final String uid;
  final String username;
  const _Person(this.uid, this.username);
}

/// Members tab of Manage Daily. A small switch at the top picks the list:
///
///   People   the owner and moderators first, then members
///   Invited  invites still waiting on an answer
///   Banned   owner and moderators only: who's banned, by whom, for how long
///
/// Each person's ⋯ menu shows only what you're allowed to do to them
/// (see DailyPermissions). Pull down to refresh (also re-reads usernames,
/// in case anyone renamed themselves).
class ManageMembers extends StatefulWidget {
  final DailyData daily;

  const ManageMembers({Key? key, required this.daily}) : super(key: key);

  @override
  State<ManageMembers> createState() => _ManageMembersState();
}

enum _Tab { people, invited, banned }

class _ManageMembersState extends State<ManageMembers> {
  final UserService _users = UserService();
  String? get _me => FirebaseAuth.instance.currentUser?.uid;

  _Tab _tab = _Tab.people;
  bool _loading = true;

  _Person? _owner;
  List<_Person> _members = []; // accepted (includes moderators)
  List<_Person> _invited = [];
  List<String> _modUids = [];
  List<DailyBan> _bans = [];
  DailyPermissions _perms = DailyPermissions.none;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(DailyModeration.watchPermissions(widget.daily).listen((p) {
      if (mounted) setState(() => _perms = p);
    }));
    _subs.add(DailyModeration.watchModerators(widget.daily.id).listen((m) {
      if (mounted) setState(() => _modUids = m);
    }, onError: (_) {}));
    _subs.add(DailyModeration.watchBans(widget.daily.id).listen((b) {
      if (mounted) setState(() => _bans = b);
    }, onError: (e) => print('ManageMembers: bans error: $e')));
    _load();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // ─── Loading ──────────────────────────────────────────────────────────────

  /// Owner from the Daily, everyone else from its invitations:
  /// accepted = member, pending = invited. [freshNames] re-reads every
  /// username (invitations keep the name from when they were sent).
  Future<void> _load({bool freshNames = false}) async {
    final ownerUid = widget.daily.creatorUid;
    _Person? owner;
    if (ownerUid != null) {
      final u = await _users.getUserById(ownerUid);
      owner = _Person(ownerUid, u?.username ?? 'Unknown');
    }

    final members = <_Person>[];
    final invited = <_Person>[];
    final seen = <String>{if (ownerUid != null) ownerUid};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('daily_invitations')
          .where('dailyId', isEqualTo: widget.daily.id)
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final uid = d['toUserId'] as String?;
        final status = d['status'] as String?;
        if (uid == null || seen.contains(uid)) continue;
        if (status != 'accepted' && status != 'pending') continue;
        seen.add(uid);
        var name = d['toUsername'] as String? ?? 'Unknown';
        if (freshNames) {
          name = (await _users.getUserById(uid))?.username ?? name;
        }
        (status == 'accepted' ? members : invited).add(_Person(uid, name));
      }
    } catch (e) {
      print('ManageMembers: error loading invitations: $e');
    }

    if (!mounted) return;
    setState(() {
      _owner = owner;
      _members = members;
      _invited = invited;
      _loading = false;
    });
  }

  List<_Person> get _mods =>
      _members.where((m) => _modUids.contains(m.uid)).toList();
  List<_Person> get _plainMembers =>
      _members.where((m) => !_modUids.contains(m.uid)).toList();
  List<DailyBan> get _activeBans => _bans.where((b) => b.isActive).toList();

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _setMod(_Person p, bool on) async {
    try {
      await DailyModeration.setModerator(widget.daily, p.uid, on);
      _toast(on
          ? '${p.username} is now a moderator'
          : '${p.username} is no longer a moderator');
    } catch (e) {
      _toast("Couldn't update ${p.username}. Try again.");
    }
  }

  Future<void> _ban(_Person p) async {
    final banned = await DailyBanSheet.show(context,
        dailyId: widget.daily.id,
        dailyTitle: widget.daily.title,
        uid: p.uid,
        username: p.username);
    if (!banned || !mounted) return;
    _toast('${p.username} was banned');
    _load(); // they're no longer a member
  }

  Future<void> _unban(DailyBan b) async {
    try {
      await DailyModeration.unban(widget.daily.id, b.uid);
      _toast('${b.username} was unbanned. They can rejoin.');
    } catch (e) {
      _toast("Couldn't unban ${b.username}. Try again.");
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Members don't see the ban list.
    if (_tab == _Tab.banned && !_perms.canModerate) _tab = _Tab.people;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: _switcher(),
        ),
        Expanded(
          child: _loading
              ? const Center(
              child: CircularProgressIndicator(color: Colors.cyan))
              : RefreshIndicator(
            color: Colors.cyan,
            onRefresh: () => _load(freshNames: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: switch (_tab) {
                _Tab.people => _peopleList(),
                _Tab.invited => _invitedList(),
                _Tab.banned => _bannedList(),
              },
            ),
          ),
        ),
      ],
    );
  }

  /// People | Invited | Banned, with counts. Same pill style as the
  /// For You | My Dailies switch.
  Widget _switcher() {
    final tabs = <(_Tab, String, int)>[
      (_Tab.people, 'People', _members.length + (_owner == null ? 0 : 1)),
      (_Tab.invited, 'Invited', _invited.length),
      if (_perms.canModerate) (_Tab.banned, 'Banned', _activeBans.length),
    ];
    final i = tabs.indexWhere((t) => t.$1 == _tab);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / tabs.length;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              left: w * (i < 0 ? 0 : i),
              top: 0,
              bottom: 0,
              width: w,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (final t in tabs)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _tab = t.$1),
                      child: Center(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: t.$2),
                            if (t.$3 > 0)
                              TextSpan(
                                text: '  ${t.$3}',
                                style: TextStyle(
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w600),
                              ),
                          ]),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _tab == t.$1
                                ? kManageInk
                                : Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }

  // ─── People ───────────────────────────────────────────────────────────────

  List<Widget> _peopleList() {
    final mods = _mods;
    final members = _plainMembers;
    return [
      _sectionTitle('Owner & moderators'),
      if (_owner != null) _personRow(_owner!, role: DailyRole.owner),
      for (final m in mods) _personRow(m, role: DailyRole.moderator),
      if (mods.isEmpty && _perms.canManageModerators) _modHint(),
      const SizedBox(height: 18),
      _sectionTitle('Members'),
      if (members.isEmpty)
        _empty(Icons.people_outline, 'No members yet')
      else
        for (final m in members) _personRow(m, role: DailyRole.member),
    ];
  }

  /// Shown to the owner until they pick a moderator.
  Widget _modHint() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Moderators can ban people and schedule covers and prompts. '
                  'Tap ⋯ next to a member to make them one.',
              style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _personRow(_Person p, {required DailyRole role}) {
    final actions = _actionsFor(p, role);
    return _row(
      uid: p.uid,
      title: p.username,
      tag: switch (role) {
        DailyRole.owner =>
            _tagChip('Owner', Icons.star_rounded, accent: true),
        DailyRole.moderator =>
            _tagChip('Moderator', Icons.shield_rounded, accent: true),
        DailyRole.member => null,
      },
      trailing: actions.isEmpty
          ? null
          : PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz, color: Colors.grey[600]),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        onSelected: (v) {
          if (v == 'mod') _setMod(p, true);
          if (v == 'unmod') _setMod(p, false);
          if (v == 'ban') _ban(p);
        },
        itemBuilder: (_) => actions,
      ),
    );
  }

  /// What the viewer may do to [p]. Owner: make/remove moderators and ban
  /// anyone. Moderator: ban members (not the owner or other moderators).
  List<PopupMenuEntry<String>> _actionsFor(_Person p, DailyRole role) {
    if (p.uid == _me || role == DailyRole.owner) return [];
    final items = <PopupMenuEntry<String>>[];
    if (_perms.canManageModerators) {
      items.add(role == DailyRole.moderator
          ? _menuItem('unmod', Icons.remove_moderator_outlined, 'Remove moderator')
          : _menuItem('mod', Icons.add_moderator_outlined, 'Make moderator'));
    }
    final canBan = _perms.isOwner ||
        (_perms.isModerator && role == DailyRole.member);
    if (canBan) {
      items.add(_menuItem('ban', Icons.block, 'Ban from this Daily',
          danger: true));
    }
    return items;
  }

  // ─── Invited ──────────────────────────────────────────────────────────────

  List<Widget> _invitedList() {
    if (_invited.isEmpty) {
      return [_empty(Icons.mail_outline, 'No pending invites')];
    }
    return [
      _sectionTitle('Waiting for an answer'),
      for (final p in _invited)
        _row(uid: p.uid, title: p.username, tag: _tagChip('Invited', Icons.schedule)),
    ];
  }

  // ─── Banned ───────────────────────────────────────────────────────────────

  List<Widget> _bannedList() {
    final bans = _activeBans;
    if (bans.isEmpty) {
      return [_empty(Icons.verified_user_outlined, 'Nobody is banned')];
    }
    return [
      _sectionTitle('Banned from this Daily'),
      for (final b in bans)
        _row(
          uid: b.uid,
          title: b.username,
          subtitle: [
            b.timeLeft,
            if (b.bannedByName.isNotEmpty) 'by ${b.bannedByName}',
          ].join(' · '),
          detail: b.reason.isEmpty ? null : '"${b.reason}"',
          trailing: TextButton(
            onPressed: () => _unban(b),
            style: TextButton.styleFrom(
              foregroundColor: Colors.cyan[800],
              backgroundColor: Colors.cyan.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('Unban',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        ),
    ];
  }

  // ─── Pieces ───────────────────────────────────────────────────────────────

  Widget _row({
    required String uid,
    required String title,
    Widget? tag,
    String? subtitle,
    String? detail,
    Widget? trailing,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => UserProfileScreen.open(context, uid, username: title),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            MemberAvatar(userId: uid, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (tag != null) ...[const SizedBox(width: 8), tag],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[500])),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  /// Owner / Moderator tags get the cyan accent; others stay grey.
  Widget _tagChip(String label, IconData icon, {bool accent = false}) {
    final color = accent ? Colors.cyan[700]! : Colors.grey[700]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent ? Colors.cyan.withOpacity(0.1) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {bool danger = false}) {
    final color = danger ? Colors.red : kManageInk;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 15, color: color)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  Widget _empty(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey[350]),
          const SizedBox(height: 10),
          Text(text,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500])),
        ],
      ),
    );
  }
}