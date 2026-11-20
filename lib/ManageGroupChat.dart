import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'UnifiedMediaPicker.dart';
import 'GroupIcon.dart';
import 'DailyFonts.dart';
import 'SettingsWidgets.dart' show showMuteForSheet, untilLabel;
import 'GroupChatService.dart';
import 'GroupAvatar.dart';
import 'GroupMediaScreen.dart';
import 'GroupWallpaperScreen.dart';
import 'ChatTarget.dart';
import 'DisappearingMessagesScreen.dart';
import 'message_service.dart';
import 'user_service.dart';
import 'FeedService.dart';
import 'UserProfileScreen.dart';
import 'friend_request_service.dart';

/// Settings for a chat: name, media, wallpaper, disappearing messages,
/// members. Used for group chats, and for 1:1 chats through
/// [ManageGroupChatScreen.direct] (same screen, one other member).
class ManageGroupChatScreen extends StatefulWidget {
  final String? groupId;
  final String? friendUserId;
  final String? friendUsername;

  const ManageGroupChatScreen({Key? key, required String this.groupId})
      : friendUserId = null,
        friendUsername = null,
        super(key: key);

  const ManageGroupChatScreen.direct({
    Key? key,
    required String this.friendUserId,
    required String this.friendUsername,
  })  : groupId = null,
        super(key: key);

  @override
  State<ManageGroupChatScreen> createState() => _ManageGroupChatScreenState();
}

class _ManageGroupChatScreenState extends State<ManageGroupChatScreen> {
  final GroupChatService _service = GroupChatService();
  bool _leaving = false;

  bool get _isGroup => widget.groupId != null;

  // Muted for a while (1 hour / 24 hours): users/{me}/chat_mutes/{key}
  // with an `until` time; the server skips this chat's pushes until then.
  // Muted until turned back on uses the chat's own mutedBy list instead.
  DateTime? _timedUntil;
  StreamSubscription? _muteSub;
  Timer? _muteTick;

  String get _muteKey => _isGroup
      ? 'group_${widget.groupId}'
      : 'direct_${widget.friendUserId}';

  DocumentReference<Map<String, dynamic>>? get _muteRef {
    final me = _service.currentUserId;
    if (me == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(me)
        .collection('chat_mutes')
        .doc(_muteKey);
  }

  bool get _timedMuteRunning =>
      _timedUntil != null && _timedUntil!.isAfter(DateTime.now());

  late final ChatTarget _target = _isGroup
      ? ChatTarget.group(widget.groupId!)
      : ChatTarget.direct(
      friendUserId: widget.friendUserId!,
      friendUsername: widget.friendUsername!);

  // Made once. They used to be made fresh on every rebuild, so anything that
  // rebuilt this screen (the keyboard sliding up under a pop-up rebuilds it
  // every frame) re-downloaded the group and ALL of its messages each time:
  // that's what made the edit pop-ups slow to appear.
  late final Stream<GroupChat?> _groupStream =
  _service.watchGroup(widget.groupId!);
  late final Stream<List<ChatMediaEntry>> _mediaStream = _target.watchMedia();
  late final Stream<ChatSettings?> _settingsStream = _target.watchSettings();

  String _myNameForDirect = 'You';

  // Friend state for the member list (group chats).
  final FriendRequestService _friendService = FriendRequestService();
  Set<String> _friendIds = {};
  final Set<String> _requested = {}; // requests sent from this screen
  String _myUsernameForRequests = '';

  Future<void> _loadFriends() async {
    final ids = await FeedService.getFriendUids();
    if (mounted) setState(() => _friendIds = ids.toSet());
  }

  Future<void> _sendRequest(String uid, String name) async {
    if (_myUsernameForRequests.isEmpty) return;
    setState(() => _requested.add(uid));
    final result = await _friendService.sendFriendRequest(
      toUserId: uid,
      toUsername: name,
      fromUsername: _myUsernameForRequests,
    );
    if (!mounted) return;
    final ok = result['success'] == true;
    final err = (result['error'] ?? '').toString();
    if (!ok) {
      setState(() {
        if (err == 'Already friends') {
          _requested.remove(uid);
          _friendIds.add(uid);
        } else if (err != 'Request already sent') {
          _requested.remove(uid); // otherwise keep showing "Sent"
        }
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Friend request sent to $name'
          : (result['error'] ?? 'Could not send request').toString()),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  void dispose() {
    _muteSub?.cancel();
    _muteTick?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _muteSub = _muteRef?.snapshots().listen((d) {
      if (!mounted) return;
      setState(() =>
      _timedUntil = (d.data()?['until'] as Timestamp?)?.toDate());
    }, onError: (_) {});
    // A timed mute running out flips the switch back here too.
    _muteTick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _timedUntil != null) setState(() {});
    });
    if (_isGroup) {
      _loadFriends();
      UserService().getUserById(_service.currentUserId ?? '').then((u) {
        if (mounted && u?.username != null) {
          _myUsernameForRequests = u!.username;
        }
      });
    }
    if (!_isGroup) {
      UserService().getUserById(_service.currentUserId ?? '').then((u) {
        if (mounted && u?.username != null) {
          setState(() => _myNameForDirect = u!.username);
        }
      });
    }
  }

  // --------------------------------------------------------------- photo

  bool _iconBusy = false;

  /// Tap the picture at the top: pick the group's photo from your photos
  /// or from pictures already sent in this chat, or remove it. Anyone in
  /// the group can.
  Future<void> _changePhoto(GroupChat group, String myName) async {
    if (_iconBusy) return;
    final hasPhoto = group.iconUrl != null && group.iconUrl!.isNotEmpty;

    Widget option(BuildContext ctx, IconData icon, String label, String value,
        {bool danger = false}) =>
        ListTile(
          leading: Icon(icon, color: danger ? Colors.red : kc.text),
          title: Text(label,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: danger ? Colors.red : kc.text)),
          onTap: () => Navigator.pop(ctx, value),
        );

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: kc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kc.grey(300),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(hasPhoto ? 'Change group photo' : 'Add group photo',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              option(ctx, Icons.photo_library_outlined, 'From your photos',
                  'photos'),
              option(ctx, Icons.perm_media_outlined, "From this chat's media",
                  'media'),
              if (hasPhoto)
                option(ctx, Icons.delete_outline, 'Remove photo', 'remove',
                    danger: true),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    Future<void> Function()? save;
    if (choice == 'photos') {
      final file = await _pickFromPhotos();
      if (file == null) return;
      save = () => _service.setIcon(widget.groupId!, file, byUsername: myName);
    } else if (choice == 'media') {
      final url = await _pickFromChatMedia();
      if (url == null) return;
      save = () =>
          _service.setIconFromUrl(widget.groupId!, url, byUsername: myName);
    } else if (choice == 'remove') {
      save = () => _service.setIcon(widget.groupId!, null, byUsername: myName);
    }
    if (save == null || !mounted) return;

    setState(() => _iconBusy = true);
    try {
      await save();
    } catch (e) {
      print('ManageGroupChat: group photo error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't update the group photo. Try again.")));
      }
    }
    if (mounted) setState(() => _iconBusy = false);
  }

  /// Your photos, in the same picker the rest of the app uses (photos only,
  /// tap one to pick it).
  Future<File?> _pickFromPhotos() {
    return showModalBottomSheet<File>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => UnifiedMediaPickerPanel(
        height: MediaQuery.of(ctx).size.height * 0.7,
        title: 'Choose a photo',
        initialFilter: MediaFilter.photos,
        singleSelect: true,
        showDraw: false,
        onDrawTap: () {},
        onClose: () => Navigator.pop(ctx),
        onMediaSelected: (items) => Navigator.pop(
            ctx, items.isEmpty || items.first.isVideo ? null : items.first.file),
      ),
    );
  }

  /// Photos already sent in this group chat. Returns the picked one's URL.
  Future<String?> _pickFromChatMedia() {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: kc.grey(300),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text("Choose from this chat",
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kc.text)),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Icon(Icons.close, color: kc.grey(600), size: 22),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: kc.adapt(const Color(0xFFEEEEEE))),
            Expanded(
              child: StreamBuilder<List<ChatMediaEntry>>(
                stream: ChatTarget.group(widget.groupId!).watchMedia(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return Center(
                        child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))));
                  }
                  final photos =
                  snap.data!.where((m) => !m.isVideo).toList();
                  if (photos.isEmpty) {
                    return Center(
                      child: Text('No photos sent in this chat yet',
                          style: TextStyle(color: kc.grey(600))),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: photos.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => Navigator.pop(ctx, photos[i].url),
                      child: Image.network(
                        photos[i].previewUrl ?? photos[i].url,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, __, ___) =>
                            Container(color: kc.grey(200)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The group's photo (or its members' pictures), with a small camera
  /// badge so it's clear you can tap it.
  Widget _headerPicture(GroupChat group, String myName) {
    final hasPhoto = group.iconUrl != null && group.iconUrl!.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _changePhoto(group, myName),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          hasPhoto
              ? GroupIcon(
              iconUrl: group.iconUrl,
              name: group.displayName(_service.currentUserId),
              size: 84)
              : _headerAvatars(group),
          if (_iconBusy)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: kc.background.withOpacity(0.6),
                  shape: hasPhoto ? BoxShape.circle : BoxShape.rectangle,
                ),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: kc.adapt(const Color(0xFFB0B5BC))),
                  ),
                ),
              ),
            ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF2E2E2E),
                shape: BoxShape.circle,
                border: Border.all(color: kc.background, width: 2.5),
              ),
              child: const Icon(Icons.photo_camera_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- name

  Future<void> _editName(GroupChat group, String myName) async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RenameSheet(
        initial: group.name ?? '',
        hint: group.namesExcluding(_service.currentUserId),
        font: DailyFonts.normalize(group.font),
      ),
    );
    if (result == null) return;
    final (name, font) = result;
    if (name.trim() != (group.name ?? '').trim()) {
      await _service.renameGroup(widget.groupId!, name, byUsername: myName);
    }
    if (font != DailyFonts.normalize(group.font)) {
      await _service.setFont(widget.groupId!, font, byUsername: myName);
    }
  }

  // ------------------------------------------------------------- members

  Future<void> _memberOptions(
      GroupChat group, String memberId, String memberName, String myName) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Material(
        color: kc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: kc.grey(300),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              MemberAvatar(userId: memberId, size: 56),
              const SizedBox(height: 8),
              Text(memberName,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('View profile'),
                onTap: () => Navigator.pop(context, 'profile'),
              ),
              ListTile(
                leading:
                const Icon(Icons.person_remove_outlined, color: Colors.red),
                title: const Text('Remove from group',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'profile') {
      UserProfileScreen.open(context, memberId, username: memberName);
      return;
    }
    if (choice != 'remove') return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kc.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Remove $memberName?'),
        content: const Text('They will no longer be able to see this chat.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.kickMember(
      groupId: widget.groupId!,
      memberId: memberId,
      memberUsername: memberName,
      byUsername: myName,
    );
  }

  // -------------------------------------------------------------- delete

  Future<void> _delete(String myName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kc.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete chat?'),
        content: const Text(
            'You will leave this group and it will disappear from your chats.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _leaving = true);
    await _service.leaveGroup(widget.groupId!, myUsername: myName);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ------------------------------------------------- shared action tiles

  Widget _mediaTile() {
    return StreamBuilder<List<ChatMediaEntry>>(
      stream: _mediaStream,
      builder: (context, snap) {
        final count = (snap.data ?? []).length;
        return _actionTile(
          icon: Icons.photo_library_outlined,
          title: 'Media',
          trailingText: count == 0 ? null : '$count',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupMediaScreen(target: _target),
            ),
          ),
        );
      },
    );
  }

  Widget _wallpaperTile(String? wallpaperUrl, String myName) {
    return _actionTile(
      icon: Icons.wallpaper_outlined,
      title: 'Wallpaper',
      trailing: wallpaperUrl == null
          ? null
          : Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: NetworkImage(wallpaperUrl),
            fit: BoxFit.cover,
          ),
        ),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupWallpaperScreen(
            target: _target,
            currentUrl: wallpaperUrl,
            myUsername: myName,
          ),
        ),
      ),
    );
  }

  /// 1:1 chats open the disappearing-message options. Groups don't have the
  /// feature yet, so the button just says so for now.
  Widget _disappearingTile() {
    if (_isGroup) {
      return _actionTile(
        icon: Icons.timer_outlined,
        title: 'Disappearing messages',
        trailingText: 'Off',
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Disappearing messages for groups are coming soon'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      );
    }
    return FutureBuilder<String>(
      future: MessageService().getChatSettings(widget.friendUserId!),
      builder: (context, snap) {
        return StatefulBuilder(
          builder: (context, setLocal) => _actionTile(
            icon: Icons.timer_outlined,
            title: 'Disappearing messages',
            trailingText: DisappearingMessagesScreen.labelFor(snap.data ?? 'off'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DisappearingMessagesScreen(
                    friendUserId: widget.friendUserId!,
                    friendUsername: widget.friendUsername!,
                  ),
                ),
              );
              if (mounted) setState(() {}); // refresh the label
            },
          ),
        );
      },
    );
  }

  /// Hide notifications: while it's on, this chat sends you no push
  /// notifications. Turning it on asks for how long: 1 hour, 24 hours (it
  /// turns itself back off after), or until turned back on. Muted chats
  /// are listed in Settings → Notifications → Muted chats.
  Widget _muteTile(ChatSettings? settings) {
    final forever = settings?.isMutedFor(_service.currentUserId) ?? false;
    final timed = _timedMuteRunning;
    final muted = forever || timed;
    return _actionTile(
      icon: muted
          ? Icons.notifications_off_outlined
          : Icons.notifications_none_outlined,
      title: 'Hide notifications',
      subtitle: timed ? 'Muted ${untilLabel(_timedUntil!)}' : null,
      trailing: Switch(
        value: muted,
        activeColor: Colors.cyan,
        onChanged: (v) => _setMuted(v),
      ),
      showChevron: false,
      onTap: () => _setMuted(!muted),
    );
  }

  // The chat's own mute (mutedBy), works whether ChatTarget.setMuted
  // returns a Future or not.
  Future<void> _muteForever(bool on) =>
      Future<void>.sync(() => _target.setMuted(on));

  Future<void> _setMuted(bool on) async {
    final ref = _muteRef;
    try {
      if (!on) {
        // Unmute: clears both kinds.
        setState(() => _timedUntil = null);
        await _muteForever(false);
        await ref?.delete();
        return;
      }
      final choice = await showMuteForSheet(
        context,
        title: _isGroup
            ? 'Hide notifications from this group'
            : 'Hide notifications from ${widget.friendUsername}',
      );
      if (choice == null || !mounted) return; // cancelled
      final until = choice.until;
      if (until == null) {
        await _muteForever(true);
        await ref?.delete();
      } else {
        setState(() => _timedUntil = until);
        await ref?.set({
          'until': Timestamp.fromDate(until),
          'kind': _isGroup ? 'group' : 'direct',
          'targetId': _isGroup ? widget.groupId : widget.friendUserId,
        });
        await _muteForever(false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't change that. Try again.")),
      );
    }
  }

  // -------------------------------------------------------- 1:1 version

  Widget _buildDirect() {
    final friendId = widget.friendUserId!;
    final friendName = widget.friendUsername!;

    return Scaffold(
      backgroundColor: kc.background,
      appBar: AppBar(
        backgroundColor: kc.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: kc.text),
      ),
      body: StreamBuilder<ChatSettings?>(
        stream: _settingsStream,
        builder: (context, snapshot) {
          final settings = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Center(
                  child: MemberAvatar(
                      userId: friendId,
                      size: 88,
                      openProfileOnTap: true,
                      username: friendName)),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  friendName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text('Chat settings',
                    style: TextStyle(fontSize: 14, color: kc.grey(600))),
              ),
              const SizedBox(height: 20),

              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: kc.grey(300)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _mediaTile(),
                    Divider(height: 1, color: kc.grey(200)),
                    _wallpaperTile(settings?.wallpaperUrl, _myNameForDirect),
                    Divider(height: 1, color: kc.grey(200)),
                    _disappearingTile(),
                    Divider(height: 1, color: kc.grey(200)),
                    _muteTile(settings),
                  ],
                ),
              ),

              const SizedBox(height: 26),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Members',
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: kc.grey(300)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _plainMemberRow(_service.currentUserId ?? '', _myNameForDirect,
                        isMe: true),
                    Divider(height: 1, color: kc.grey(200)),
                    _plainMemberRow(friendId, friendName, isMe: false),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _plainMemberRow(String uid, String name, {required bool isMe}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isMe ? null : () => UserProfileScreen.open(context, uid, username: name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            MemberAvatar(userId: uid, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            if (isMe)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('You',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: kc.grey(700))),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ UI

  Widget _headerAvatars(GroupChat group) {
    final ids = group.memberIds.take(3).toList();
    const size = 64.0;
    const overlap = 40.0;
    final width = size + overlap * (ids.length - 1);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < ids.length; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kc.background, width: 3),
                ),
                child: MemberAvatar(userId: ids[i], size: size - 6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    String? trailingText,
    Widget? trailing,
    bool showChevron = true,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kc.adapt(const Color(0xFFF1F3F5)),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: kc.adapt(const Color(0xFF2E2E2E)), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle,
                            style: TextStyle(
                                fontSize: 12.5, color: kc.grey(600))),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
              if (trailingText != null)
                Text(trailingText,
                    style: TextStyle(fontSize: 14, color: kc.grey(600))),
              if (showChevron) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: kc.grey(400)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isGroup) return _buildDirect();
    final myId = _service.currentUserId;

    return StreamBuilder<GroupChat?>(
      stream: _groupStream,
      builder: (context, snapshot) {
        final group = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting &&
            group == null) {
          return Scaffold(
            backgroundColor: kc.background,
            body: Center(child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC)))),
          );
        }

        // Removed from the group (or it no longer exists).
        if (!_leaving && (group == null || !group.memberIds.contains(myId))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          });
          return Scaffold(backgroundColor: kc.background);
        }
        if (group == null) return Scaffold(backgroundColor: kc.background);

        final myName = group.memberUsernames[myId] ?? 'Someone';
        final members = group.memberIds.toList()
          ..sort((a, b) {
            if (a == myId) return -1;
            if (b == myId) return 1;
            return (group.memberUsernames[a] ?? '')
                .toLowerCase()
                .compareTo((group.memberUsernames[b] ?? '').toLowerCase());
          });

        return Scaffold(
          backgroundColor: kc.background,
          appBar: AppBar(
            backgroundColor: kc.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: kc.text),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              // ---- Header: avatars, name (tap to edit), member count
              Center(child: _headerPicture(group, myName)),
              const SizedBox(height: 14),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _editName(group, myName),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        group.displayName(myId),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: DailyFonts.style(group.font,
                            fontWeight: FontWeight.w700)
                            .copyWith(fontSize: 24, color: kc.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.edit_outlined, size: 20, color: kc.grey(600)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  '${group.memberIds.length} members',
                  style: TextStyle(fontSize: 14, color: kc.grey(600)),
                ),
              ),
              if (!group.hasName)
                Center(
                  child: TextButton(
                    onPressed: () => _editName(group, myName),
                    child: const Text('Name this group'),
                  ),
                )
              else
                const SizedBox(height: 12),

              // ---- Actions
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: kc.grey(300)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _mediaTile(),
                    Divider(height: 1, color: kc.grey(200)),
                    _wallpaperTile(group.wallpaperUrl, myName),
                    Divider(height: 1, color: kc.grey(200)),
                    _disappearingTile(),
                    Divider(height: 1, color: kc.grey(200)),
                    _muteTile(ChatSettings(mutedBy: group.mutedBy)),
                  ],
                ),
              ),

              // ---- Members
              const SizedBox(height: 26),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('Members',
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2, bottom: 8),
                child: Text('Tap a member to view their profile. Hold to remove them.',
                    style: TextStyle(fontSize: 13, color: kc.grey(600))),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: kc.grey(300)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < members.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: kc.grey(200)),
                      _memberRow(group, members[i], myId, myName),
                    ],
                  ],
                ),
              ),

              // ---- Delete
              const SizedBox(height: 26),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => _delete(myName),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete chat',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shown next to members you aren't friends with yet.
  Widget _addButton(String uid, String name) {
    final sent = _requested.contains(uid);
    return GestureDetector(
      onTap: sent ? null : () => _sendRequest(uid, name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: sent ? kc.grey(200) : Colors.cyan,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          sent ? 'Sent' : 'Add',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: sent ? kc.grey(600) : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _memberRow(
      GroupChat group, String uid, String? myId, String myName) {
    final name = group.memberUsernames[uid] ?? 'Unknown';
    final isMe = uid == myId;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: isMe ? null : () => _memberOptions(group, uid, name, myName),
        onTap: isMe
            ? null
            : () => UserProfileScreen.open(context, uid, username: name),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              MemberAvatar(userId: uid, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              if (!isMe && !_friendIds.contains(uid))
                _addButton(uid, name),
              if (isMe)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('You',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: kc.grey(700))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The rename sheet owns its text controller so it is only disposed after the
/// sheet has fully closed.
class _RenameSheet extends StatefulWidget {
  final String initial;
  final String hint;
  final String font;

  const _RenameSheet(
      {required this.initial, required this.hint, required this.font});

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

/// Name and font for the group. Pops (name, font).
class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _controller =
  TextEditingController(text: widget.initial);
  final FocusNode _focus = FocusNode();
  late String _font = widget.font;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    // The keyboard comes up once the sheet has slid in, instead of both
    // animating at once (which made opening feel slow).
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, (_controller.text, _font));

  /// One font choice: the group's name written in that font.
  Widget _fontChip(String font) {
    final on = font == _font;
    final sample = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : (widget.hint.trim().isNotEmpty ? widget.hint.trim() : 'Group');
    return GestureDetector(
      onTap: () => setState(() => _font = font),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(maxWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: on ? Colors.cyan.withOpacity(0.08) : kc.grey(100),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: on ? Colors.cyan : Colors.transparent, width: 1.5),
        ),
        child: Text(
          sample,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DailyFonts.style(font, fontWeight: FontWeight.w700)
              .copyWith(fontSize: 16, color: kc.text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Material(
        color: kc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: kc.grey(300),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Group name',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Leave it empty to show the members instead.',
                    style: TextStyle(fontSize: 13, color: kc.grey(600))),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  focusNode: _focus,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    filled: true,
                    fillColor: kc.grey(100),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Font',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: DailyFonts.options.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _fontChip(DailyFonts.options[i]),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('Save',
                        style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}