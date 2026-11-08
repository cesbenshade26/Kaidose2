import 'package:flutter/material.dart';
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

  late final ChatTarget _target = _isGroup
      ? ChatTarget.group(widget.groupId!)
      : ChatTarget.direct(
      friendUserId: widget.friendUserId!,
      friendUsername: widget.friendUsername!);

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
  void initState() {
    super.initState();
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

  // ---------------------------------------------------------------- name

  Future<void> _editName(GroupChat group, String myName) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RenameSheet(
        initial: group.name ?? '',
        hint: group.namesExcluding(_service.currentUserId),
      ),
    );
    if (result == null) return;
    if (result.trim() == (group.name ?? '').trim()) return;
    await _service.renameGroup(widget.groupId!, result, byUsername: myName);
  }

  // ------------------------------------------------------------- members

  Future<void> _memberOptions(
      GroupChat group, String memberId, String memberName, String myName) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Material(
        color: Colors.white,
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
                  color: Colors.grey[300],
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
        backgroundColor: Colors.white,
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
        backgroundColor: Colors.white,
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
      stream: _target.watchMedia(),
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

  /// Per-person mute switch. Stored now; notifications will respect it later.
  Widget _muteTile(ChatSettings? settings) {
    final muted = settings?.isMutedFor(_service.currentUserId) ?? false;
    return _actionTile(
      icon: muted
          ? Icons.notifications_off_outlined
          : Icons.notifications_none_outlined,
      title: 'Hide notifications',
      trailing: Switch(
        value: muted,
        activeColor: Colors.cyan,
        onChanged: (v) => _target.setMuted(v),
      ),
      showChevron: false,
      onTap: () => _target.setMuted(!muted),
    );
  }

  // -------------------------------------------------------- 1:1 version

  Widget _buildDirect() {
    final friendId = widget.friendUserId!;
    final friendName = widget.friendUsername!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<ChatSettings?>(
        stream: _target.watchSettings(),
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
                    style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              ),
              const SizedBox(height: 20),

              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _mediaTile(),
                    Divider(height: 1, color: Colors.grey[200]),
                    _wallpaperTile(settings?.wallpaperUrl, _myNameForDirect),
                    Divider(height: 1, color: Colors.grey[200]),
                    _disappearingTile(),
                    Divider(height: 1, color: Colors.grey[200]),
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
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _plainMemberRow(_service.currentUserId ?? '', _myNameForDirect,
                        isMe: true),
                    Divider(height: 1, color: Colors.grey[200]),
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
                        color: Colors.cyan[800])),
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
                  border: Border.all(color: Colors.white, width: 3),
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
                  color: Colors.cyan.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.cyan[700], size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              if (trailing != null) trailing,
              if (trailingText != null)
                Text(trailingText,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              if (showChevron) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
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
      stream: _service.watchGroup(widget.groupId!),
      builder: (context, snapshot) {
        final group = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting &&
            group == null) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator(color: Colors.cyan)),
          );
        }

        // Removed from the group (or it no longer exists).
        if (!_leaving && (group == null || !group.memberIds.contains(myId))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          });
          return const Scaffold(backgroundColor: Colors.white);
        }
        if (group == null) return const Scaffold(backgroundColor: Colors.white);

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
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.black),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              // ---- Header: avatars, name (tap to edit), member count
              Center(child: _headerAvatars(group)),
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
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.edit_outlined, size: 20, color: Colors.grey[600]),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  '${group.memberIds.length} members',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _mediaTile(),
                    Divider(height: 1, color: Colors.grey[200]),
                    _wallpaperTile(group.wallpaperUrl, myName),
                    Divider(height: 1, color: Colors.grey[200]),
                    _disappearingTile(),
                    Divider(height: 1, color: Colors.grey[200]),
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
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < members.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: Colors.grey[200]),
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
          color: sent ? Colors.grey[200] : Colors.cyan,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          sent ? 'Sent' : 'Add',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: sent ? Colors.grey[600] : Colors.white,
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
                          color: Colors.cyan[800])),
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

  const _RenameSheet({required this.initial, required this.hint});

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _controller =
  TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Material(
        color: Colors.white,
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
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Group name',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Leave it empty to show the members instead.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (v) => Navigator.pop(context, v),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _controller.text),
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