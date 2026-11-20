import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'friend_request_service.dart';
import 'message_service.dart';
import 'user_service.dart';
import 'SendToDailySelector.dart';
import 'NativeShareBar.dart';
import 'GroupAvatar.dart';
import 'GroupChatService.dart';
import 'GroupIcon.dart';
import 'DailyShare.dart';
import 'AddToMyDaily.dart';

/// Opens the Share sheet (rounded white card sliding up from the bottom,
/// drag to dismiss). One row holds the quick actions, then your group
/// chats, then your friends, each with their picture; tap one to send.
///
///  * [clipId]: sharing a clip. Actions: Add to My Daily, Send to Daily.
///  * [daily]: sharing a Daily message. Action: Add to My Daily.
///    [onAddToMyDaily] does the adding (the message knows its own media).
///  * Neither: a plain friend picker; pass [onFriendSelected].
Future<void> showShareSheet(
    BuildContext context, {
      void Function(String friendUserId, String friendUsername)? onFriendSelected,
      String? clipId,
      SharedDailyContent? daily,
      VoidCallback? onAddToMyDaily,
    }) {
  // Runs after the sheet closes, on the screen underneath.
  final VoidCallback? addToMyDaily = onAddToMyDaily ??
      (clipId != null ? () => AddToMyDaily.fromClip(context, clipId) : null);

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => ShareSheet(
      onClose: () => Navigator.pop(sheetContext),
      onFriendSelected: onFriendSelected,
      clipId: clipId,
      daily: daily,
      onAddToMyDaily: addToMyDaily,
    ),
  );
}

/// Generic share bottom sheet content. See [showShareSheet].
class ShareSheet extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(String friendUserId, String friendUsername)? onFriendSelected;
  final String? clipId;
  final SharedDailyContent? daily;
  final VoidCallback? onAddToMyDaily;

  const ShareSheet({
    Key? key,
    required this.onClose,
    this.onFriendSelected,
    this.clipId,
    this.daily,
    this.onAddToMyDaily,
  }) : super(key: key);

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final MessageService _messageService = MessageService();
  final UserService _userService = UserService();
  bool _isSending = false;
  String? _myName;

  Future<String> _myUsername() async {
    if (_myName != null) return _myName!;
    var name = 'You';
    final uid = _messageService.currentUserId;
    if (uid != null) {
      final user = await _userService.getUserById(uid);
      if (user?.username != null && user!.username.isNotEmpty) {
        name = user.username;
      }
    }
    _myName = name;
    return name;
  }

  Future<Map<String, dynamic>> _clipData() async {
    final clipDoc = await FirebaseFirestore.instance
        .collection('clips')
        .doc(widget.clipId)
        .get();
    if (!clipDoc.exists) throw Exception('Clip not found');
    final data = clipDoc.data()!;
    final videoUrl = data['videoUrl'] as String? ?? '';
    if (videoUrl.isEmpty) throw Exception('Clip has no video');
    return data;
  }

  /// Sends to one person or group, then closes with a short confirmation.
  Future<void> _send(String name, Future<bool> Function() send) async {
    if (_isSending) return;
    setState(() => _isSending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await send();
      if (!mounted) return;
      widget.onClose();
      messenger.showSnackBar(SnackBar(
        content: Text(ok ? 'Sent to $name' : "Couldn't send to $name"),
        backgroundColor: ok ? Colors.black87 : Colors.red,
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      print('ShareSheet: send error: $e');
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text("Couldn't send: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _handleFriendTap(String friendUserId, String friendUsername) {
    // Caller wants custom behavior instead of the default send — defer to it.
    if (widget.onFriendSelected != null) {
      widget.onFriendSelected!(friendUserId, friendUsername);
      return;
    }
    final daily = widget.daily;
    if (daily != null) {
      _send(friendUsername, () async {
        return DailyShareSender.toFriend(
            daily, friendUserId, await _myUsername());
      });
      return;
    }
    if (widget.clipId == null) return;
    _send(friendUsername, () async {
      final data = await _clipData();
      final caption = data['caption'] as String? ?? '';
      return _messageService.sendChatMessage(
        recipientUserId: friendUserId,
        text: caption.isNotEmpty ? caption : 'Sent a clip',
        senderUsername: await _myUsername(),
        metadata: {
          'type': 'clip',
          'clipId': widget.clipId,
          'videoUrl': data['videoUrl'],
        },
      );
    });
  }

  void _handleGroupTap(GroupChat group, String title) {
    final daily = widget.daily;
    if (daily != null) {
      _send(title, () async {
        return DailyShareSender.toGroup(daily, group.id, await _myUsername());
      });
      return;
    }
    if (widget.clipId == null) return;
    _send(title, () async {
      final data = await _clipData();
      await GroupChatService().sendSharedClip(
        groupId: group.id,
        senderUsername: await _myUsername(),
        clipId: widget.clipId!,
        videoUrl: data['videoUrl'] as String,
        caption: data['caption'] as String? ?? '',
        thumbUrl: data['thumbnailUrl'] as String?,
      );
      return true;
    });
  }

  void _addToMyDaily() {
    final add = widget.onAddToMyDaily;
    widget.onClose();
    add?.call();
  }

  @override
  Widget build(BuildContext context) {
    final picker = widget.onFriendSelected != null;
    final actions = <ShareAction>[
      if (!picker && widget.onAddToMyDaily != null)
        ShareAction(
          label: 'Add to My Daily',
          icon: Icons.add_circle_outline_rounded,
          onTap: _addToMyDaily,
        ),
      if (!picker && widget.clipId != null)
        ShareAction(
          label: 'Send to Daily',
          icon: Icons.wb_sunny_outlined,
          onTap: () => showSendToDailySheet(context, clipId: widget.clipId),
        ),
    ];
    final shareText = widget.daily?.text ?? '';

    return Container(
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
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

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Share',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kc.text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onClose,
                    child: Icon(Icons.close, color: kc.grey(600), size: 22),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: kc.adapt(const Color(0xFFEEEEEE))),

            const SizedBox(height: 16),

            FriendSelectorBar(
              actions: actions,
              onFriendTap: _handleFriendTap,
              onGroupTap: picker ? null : _handleGroupTap,
            ),

            if (_isSending) ...[
              const SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: LinearProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))),
              ),
            ],

            if (widget.clipId != null || shareText.isNotEmpty) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Share via',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kc.grey(600),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              NativeShareBar(
                clipId: widget.clipId,
                fallbackShareText: shareText.isEmpty ? null : shareText,
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// A round action bubble at the start of the share row.
class ShareAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const ShareAction(
      {required this.label, required this.icon, required this.onTap});
}

/// Reusable horizontally-scrollable row: optional action bubbles first,
/// then your group chats (when [onGroupTap] is set), then your friends,
/// each with their picture and name. Usable anywhere a quick picker is
/// needed.
///
/// The single [leadingLabel]/[leadingIcon]/[onLeadingTap] action still
/// works (it's added after [actions]).
class FriendSelectorBar extends StatefulWidget {
  final void Function(String friendUserId, String friendUsername)? onFriendTap;
  final void Function(GroupChat group, String title)? onGroupTap;
  final List<ShareAction> actions;
  final String? leadingLabel;
  final IconData? leadingIcon;
  final VoidCallback? onLeadingTap;

  const FriendSelectorBar({
    Key? key,
    this.onFriendTap,
    this.onGroupTap,
    this.actions = const [],
    this.leadingLabel,
    this.leadingIcon,
    this.onLeadingTap,
  }) : super(key: key);

  @override
  State<FriendSelectorBar> createState() => _FriendSelectorBarState();
}

class _FriendSelectorBarState extends State<FriendSelectorBar> {
  final FriendRequestService _friendRequestService = FriendRequestService();
  late final Stream<List<FriendRequest>> _friends =
  _friendRequestService.getAcceptedFriends();
  late final Stream<List<GroupChat>> _groups = GroupChatService().getMyGroups();

  List<ShareAction> get _actions => [
    ...widget.actions,
    if (widget.leadingLabel != null &&
        widget.leadingIcon != null &&
        widget.onLeadingTap != null)
      ShareAction(
        label: widget.leadingLabel!,
        icon: widget.leadingIcon!,
        onTap: widget.onLeadingTap!,
      ),
  ];

  Widget _bubble({
    required Widget avatar,
    required String label,
    VoidCallback? onTap,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 56, height: 56, child: avatar),
            const SizedBox(height: 6),
            SizedBox(
              width: 64,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: bold ? 11 : 12,
                  color: kc.text,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                maxLines: bold ? 2 : 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBubble(ShareAction a) {
    return _bubble(
      label: a.label,
      bold: true,
      onTap: a.onTap,
      avatar: Container(
        decoration: BoxDecoration(
          color: kc.adapt(const Color(0xFFF1F3F5)),
          shape: BoxShape.circle,
        ),
        child: Icon(a.icon, color: kc.adapt(const Color(0xFF2E2E2E)), size: 26),
      ),
    );
  }

  Widget _groupBubble(GroupChat g, String? myUid) {
    final title = g.displayName(myUid);
    return _bubble(
      label: title,
      onTap: widget.onGroupTap == null ? null : () => widget.onGroupTap!(g, title),
      avatar: GroupIcon(iconUrl: g.iconUrl, name: title, size: 56),
    );
  }

  Widget _friendBubble(FriendRequest f, String? currentUid) {
    final isCurrentUserSender = f.fromUserId == currentUid;
    final friendName = isCurrentUserSender ? f.toUsername : f.fromUsername;
    final friendUserId = isCurrentUserSender ? f.toUserId : f.fromUserId;
    return _bubble(
      label: friendName,
      onTap: widget.onFriendTap == null
          ? null
          : () => widget.onFriendTap!(friendUserId, friendName),
      avatar: MemberAvatar(userId: friendUserId, size: 56),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions;
    final showGroups = widget.onGroupTap != null;

    return SizedBox(
      height: 96,
      child: StreamBuilder<List<GroupChat>>(
        stream: showGroups ? _groups : const Stream<List<GroupChat>>.empty(),
        builder: (context, groupSnap) {
          final groups = showGroups ? (groupSnap.data ?? const <GroupChat>[]) : const <GroupChat>[];
          return StreamBuilder<List<FriendRequest>>(
            stream: _friends,
            builder: (context, snapshot) {
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting;
              final friends = snapshot.data ?? [];
              final currentUid = _friendRequestService.currentUserId;

              if (actions.isEmpty &&
                  groups.isEmpty &&
                  !isLoading &&
                  friends.isEmpty) {
                return Center(
                  child: Text(
                    'No friends yet',
                    style: TextStyle(color: kc.grey(500), fontSize: 14),
                  ),
                );
              }

              final children = <Widget>[
                for (final a in actions) _actionBubble(a),
                for (final g in groups) _groupBubble(g, currentUid),
                if (isLoading)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))),
                    ),
                  )
                else
                  for (final f in friends) _friendBubble(f, currentUid),
              ];

              return ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: children,
              );
            },
          );
        },
      ),
    );
  }
}