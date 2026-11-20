import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:geolocator/geolocator.dart';
import 'FeedService.dart';
import 'GroupAvatar.dart';
import 'LikePrefs.dart';
import 'Legal.dart';
import 'Nearby.dart';
import 'SafetyService.dart';
import 'SafetySheets.dart' show BlockedAccountsScreen;
import 'SettingsWidgets.dart';
import 'user_service.dart';

/// Settings → Privacy.
///
///   Discovery     Near you (show me to people nearby, and them to me)
///   Your story    who can't see it
///   Likes         like counts on your clips / others' clips, and whether
///                 friends see what you like
///   Group chats   whether friends can add you to group chats
///                 (users/{uid}.groupAddsOff)
///   AI covers     whether your posts can be picked for a Daily's cover
///                 and read by the AI that writes its line
///                 (users/{uid}.aiCovers, on unless switched off)
///   People        blocked and muted accounts
///   Phone access  what Kaidose can use on your phone and why (camera,
///                 photos, microphone, contacts, location, notifications),
///                 with a button to the phone's Settings, which shows and
///                 changes whether each is allowed
///   Your data     the Privacy Policy
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({Key? key}) : super(key: key);

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool? _nearby; // null while loading
  bool _nearbyBusy = false;

  final SafetyService _safety = SafetyService.instance;

  // Switches saved on your profile doc.
  bool _groupAddsOff = false;
  bool _aiCovers = true;
  StreamSubscription? _meSub;

  DocumentReference<Map<String, dynamic>>? get _meRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _safety.changes.addListener(_refresh);
    _load();
    _meSub = _meRef?.snapshots().listen((s) {
      final d = s.data() ?? {};
      if (!mounted) return;
      setState(() {
        _groupAddsOff = d['groupAddsOff'] == true;
        _aiCovers = d['aiCovers'] != false;
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _safety.changes.removeListener(_refresh);
    _meSub?.cancel();
    super.dispose();
  }

  Future<void> _setField(String key, bool value) async {
    try {
      await _meRef?.set({key: value}, SetOptions(merge: true));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save that. Try again.")));
    }
  }

  Widget _switch(bool value, ValueChanged<bool> onChanged) => Switch(
    value: value,
    onChanged: onChanged,
    activeColor: Colors.white,
    activeTrackColor: Colors.cyan,
  );

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final on = await NearbyService.isOn();
    if (mounted) setState(() => _nearby = on);
  }

  Future<void> _setNearby(bool on) async {
    if (_nearbyBusy) return;
    setState(() => _nearbyBusy = true);
    if (on) {
      final problem = await NearbyService.turnOn();
      if (!mounted) return;
      setState(() {
        _nearbyBusy = false;
        _nearby = problem == null;
      });
      if (problem != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(problem)));
      }
    } else {
      await NearbyService.turnOff();
      if (!mounted) return;
      setState(() {
        _nearbyBusy = false;
        _nearby = false;
      });
    }
  }

  Future<void> _openPhoneSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Open your phone's Settings, then find Kaidose"),
      ));
    }
  }

  /// What Kaidose can use on the phone, and why. Each opens Kaidose's page
  /// in the phone's Settings, where it's switched on or off.
  static const _access = [
    (Icons.photo_camera_outlined, 'Camera',
    'Taking photos and videos for posts, clips and stories'),
    (Icons.photo_library_outlined, 'Photos',
    'Choosing pictures and videos to post or send'),
    (Icons.mic_none_rounded, 'Microphone', 'Sound in the videos you record'),
    (Icons.contacts_outlined, 'Contacts',
    'Finding friends who are already on Kaidose'),
    (Icons.location_on_outlined, 'Location',
    'Near you, and suggestions from around you'),
    (Icons.notifications_none_rounded, 'Notifications',
    'Messages, friend requests and Dailies'),
  ];

  Widget _count(int n) => Text(n == 0 ? 'None' : '$n',
      style: TextStyle(fontSize: 14.5, color: SettingsStyle.subtle));

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final nearby = _nearby;
    return SettingsPage(
      title: 'Privacy',
      children: [
        SettingsGroup(
          title: 'Discovery',
          footer: 'When this is on, people near you who also turned it on can '
              'find you in Search, and you can find them. Only a rough area '
              '(about city-sized) is saved, never your exact location.',
          children: [
            SettingsTile(
              icon: Icons.near_me_outlined,
              title: 'Near you',
              trailing: nearby == null || _nearbyBusy
                  ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: kc.adapt(const Color(0xFFB0B5BC))),
              )
                  : Switch(
                value: nearby,
                onChanged: _setNearby,
                activeColor: Colors.white,
                activeTrackColor: Colors.cyan,
              ),
              onTap: nearby == null ? null : () => _setNearby(!nearby),
            ),
          ],
        ),

        SettingsGroup(
          title: 'Your story',
          children: [
            SettingsTile(
              icon: Icons.visibility_off_outlined,
              title: 'Hide story from',
              trailing: _count(_safety.storyHiddenFrom.length),
              onTap: () => _open(const HideStoryFromScreen()),
            ),
          ],
        ),

        ValueListenableBuilder<Map<String, bool>>(
          valueListenable: LikePrefs.values,
          builder: (context, _, __) {
            Widget sw(IconData icon, String title, String subtitle,
                String key, bool value) =>
                SettingsTile(
                  icon: icon,
                  title: title,
                  subtitle: subtitle,
                  trailing: Switch(
                    value: value,
                    onChanged: (v) => LikePrefs.set(key, v),
                    activeColor: Colors.white,
                    activeTrackColor: Colors.cyan,
                  ),
                  onTap: () => LikePrefs.set(key, !value),
                );
            return SettingsGroup(
              title: 'Likes',
              children: [
                sw(Icons.favorite_border_rounded, 'Hide like counts on my clips',
                    'Only you see how many likes they get', 'hideMine',
                    LikePrefs.hideMine),
                sw(Icons.visibility_off_outlined, 'Hide like counts while watching',
                    "You won't see counts on other people's clips",
                    'hideOthers', LikePrefs.hideOthers),
                sw(Icons.group_outlined, 'Show friends what I like',
                    'Clips you like can show up for friends in Clips',
                    'shareLikes', LikePrefs.shareLikes),
              ],
            );
          },
        ),

        SettingsGroup(
          title: 'Group chats',
          footer: 'Only friends can add you to a group chat. Turn this off and '
              "nobody can add you; they'll see you can't be added.",
          children: [
            SettingsTile(
              icon: Icons.group_add_outlined,
              title: 'Let friends add me to group chats',
              trailing: _switch(!_groupAddsOff, (v) {
                setState(() => _groupAddsOff = !v);
                _setField('groupAddsOff', !v);
              }),
              onTap: () {
                setState(() => _groupAddsOff = !_groupAddsOff);
                _setField('groupAddsOff', _groupAddsOff);
              },
            ),
          ],
        ),

        SettingsGroup(
          title: 'People',
          children: [
            SettingsTile(
              icon: Icons.block_rounded,
              title: 'Blocked accounts',
              trailing: _count(_safety.blocked.length),
              onTap: () => _open(const BlockedAccountsScreen()),
            ),
            SettingsTile(
              icon: Icons.volume_off_outlined,
              title: 'Muted accounts',
              subtitle: "Their stories and clips don't show for you",
              trailing: _count(_safety.muted.length),
              onTap: () => _open(const MutedAccountsScreen()),
            ),
          ],
        ),

        SettingsGroup(
          title: 'Phone access',
          footer: 'Kaidose only asks for these when you first use the feature '
              "that needs them. Tap one to turn it on or off in your phone's "
              'Settings.',
          children: [
            for (final a in _access)
              SettingsTile(
                icon: a.$1,
                title: a.$2,
                subtitle: a.$3,
                trailing: Icon(Icons.open_in_new_rounded,
                    size: 18, color: kc.adapt(const Color(0xFFB0B4BA))),
                onTap: _openPhoneSettings,
              ),
          ],
        ),

        SettingsGroup(
          title: 'Your data',
          footer: 'A Daily\'s cover shows one of its best recent posts with a '
              'short line written by AI from what people posted. Turn this '
              'off and your posts are never picked or read for covers. '
              'Safety checks on posts still apply.',
          children: [
            SettingsTile(
              icon: Icons.auto_awesome_outlined,
              title: 'Use my posts for AI covers',
              trailing: _switch(_aiCovers, (v) {
                setState(() => _aiCovers = v);
                _setField('aiCovers', v);
              }),
              onTap: () {
                setState(() => _aiCovers = !_aiCovers);
                _setField('aiCovers', _aiCovers);
              },
            ),
            SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'How Kaidose uses your data',
              subtitle: 'Privacy Policy',
              onTap: Legal.openPrivacy,
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Hide story from ──────────────────────────────────────────────────────────

/// Your friends, with a check next to anyone your story is hidden from.
/// Tap to hide or show it. (Also set from someone's profile ⋯ menu.)
class HideStoryFromScreen extends StatefulWidget {
  const HideStoryFromScreen({Key? key}) : super(key: key);

  @override
  State<HideStoryFromScreen> createState() => _HideStoryFromScreenState();
}

class _HideStoryFromScreenState extends State<HideStoryFromScreen> {
  final SafetyService _safety = SafetyService.instance;
  List<String>? _people;

  @override
  void initState() {
    super.initState();
    _safety.changes.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _safety.changes.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final friends = (await FeedService.getFriendUids()).toList();
    // Anyone already hidden stays listed, even if no longer a friend.
    final all = {..._safety.storyHiddenFrom, ...friends}.toList();
    if (mounted) setState(() => _people = all);
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    return SettingsPage(
      title: 'Hide story from',
      children: [
        if (people == null)
          Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC)))),
          )
        else if (people.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(
              child: Text('Add friends to choose who sees your story',
                  style: TextStyle(fontSize: 15, color: SettingsStyle.subtle)),
            ),
          )
        else
          SettingsGroup(
            footer: "People you hide your story from aren't told.",
            children: [
              for (final uid in people)
                _PersonRow(
                  uid: uid,
                  trailing: Checkbox(
                    value: _safety.isStoryHiddenFrom(uid),
                    activeColor: Colors.cyan,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5)),
                    onChanged: (v) => _safety.setStoryHidden(uid, v == true),
                  ),
                  onTap: () => _safety.setStoryHidden(
                      uid, !_safety.isStoryHiddenFrom(uid)),
                ),
            ],
          ),
      ],
    );
  }
}

// ─── Muted accounts ───────────────────────────────────────────────────────────

/// People you muted (their stories and clips don't show for you), with
/// Unmute. They aren't told either way.
class MutedAccountsScreen extends StatefulWidget {
  const MutedAccountsScreen({Key? key}) : super(key: key);

  @override
  State<MutedAccountsScreen> createState() => _MutedAccountsScreenState();
}

class _MutedAccountsScreenState extends State<MutedAccountsScreen> {
  final SafetyService _safety = SafetyService.instance;

  @override
  void initState() {
    super.initState();
    _safety.changes.addListener(_refresh);
  }

  @override
  void dispose() {
    _safety.changes.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final muted = _safety.muted.toList();
    return SettingsPage(
      title: 'Muted accounts',
      children: [
        if (muted.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(
              child: Text("You haven't muted anyone",
                  style: TextStyle(fontSize: 15, color: SettingsStyle.subtle)),
            ),
          )
        else
          SettingsGroup(
            footer: "People you mute aren't told.",
            children: [
              for (final uid in muted)
                _PersonRow(
                  uid: uid,
                  trailing: TextButton(
                    onPressed: () => _safety.setMuted(uid, false),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.cyan[700],
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('Unmute',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// Usernames looked up once per screen visit, not on every tap.
final Map<String, Future<dynamic>> _names = {};

/// Picture + username, and something on the right.
class _PersonRow extends StatelessWidget {
  final String uid;
  final Widget trailing;
  final VoidCallback? onTap;

  const _PersonRow({required this.uid, required this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            MemberAvatar(userId: uid, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: FutureBuilder<dynamic>(
                future: _names[uid] ??= UserService().getUserById(uid),
                builder: (context, snap) => Text(
                  snap.data?.username ?? ' ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: SettingsStyle.ink),
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}