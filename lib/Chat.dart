import 'dart:async';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'friend_request_service.dart';
import 'user_service.dart';
import 'AddToDaily.dart';
import 'ChatScreen.dart';
import 'ManageChat.dart';
import 'AddChatSheet.dart';
import 'NewGroupChat.dart';
import 'GroupChatService.dart';
import 'GroupChatScreen.dart';
import 'ManageGroupChat.dart';
import 'UserProfileScreen.dart';
import 'ChatUnread.dart';
import 'GroupAvatar.dart';
import 'GroupIcon.dart';

class ChatWidget extends StatefulWidget {
  const ChatWidget({Key? key}) : super(key: key);

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> with AutomaticKeepAliveClientMixin {
  List<FriendRequest> _acceptedFriends = [];
  List<FriendRequest> _filteredFriends = [];
  Set<String> _pinnedFriends = {};
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FriendRequestService _friendRequestService = FriendRequestService();
  final GroupChatService _groupService = GroupChatService();

  // Chat activity (what's new in each 1:1 chat) and the friends/groups I've
  // already opened, so brand-new ones can say "New friend" / "New group".
  Map<String, ChatActivity> _activity = {};
  StreamSubscription<Map<String, ChatActivity>>? _activitySub;
  Set<String>? _known;
  bool _knownLoaded = false;
  bool _seedQueued = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterFriends);
    _activitySub = ChatUnreadService.instance.directActivity().listen((m) {
      if (mounted) setState(() => _activity = m);
    }, onError: (_) {});
    ChatUnreadService.instance.loadKnown().then((k) {
      if (!mounted) return;
      setState(() {
        _known = k;
        _knownLoaded = true;
      });
    });
  }

  /// First run on this device: everyone already here counts as met, so only
  /// people who show up later get a "New friend" / "New group" tag.
  void _seedKnown(Iterable<String> ids) {
    if (!_knownLoaded || _known != null || _seedQueued) return;
    _seedQueued = true;
    final seeded = ids.toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _known = seeded);
      ChatUnreadService.instance.saveKnown(seeded);
    });
  }

  bool _isNew(String id) => _known != null && !_known!.contains(id);

  void _markMet(String id) {
    if (_known == null || _known!.contains(id)) return;
    setState(() => _known = {..._known!, id});
    ChatUnreadService.instance.saveKnown(_known!);
  }

  @override
  void dispose() {
    _activitySub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _sortAndFilterFriends() {
    final pinnedList = _acceptedFriends.where((f) {
      final friendUserId = f.fromUserId == _friendRequestService.currentUserId
          ? f.toUserId
          : f.fromUserId;
      return _pinnedFriends.contains(friendUserId);
    }).toList();

    final unpinnedList = _acceptedFriends.where((f) {
      final friendUserId = f.fromUserId == _friendRequestService.currentUserId
          ? f.toUserId
          : f.fromUserId;
      return !_pinnedFriends.contains(friendUserId);
    }).toList();

    _filteredFriends = [...pinnedList, ...unpinnedList];
  }

  void _filterFriends() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _sortAndFilterFriends();
      } else {
        final filtered = _acceptedFriends.where((friend) {
          final friendName = friend.fromUserId == _friendRequestService.currentUserId
              ? friend.toUsername
              : friend.fromUsername;
          return friendName.toLowerCase().contains(query);
        }).toList();

        final pinnedFiltered = filtered.where((f) {
          final friendUserId = f.fromUserId == _friendRequestService.currentUserId
              ? f.toUserId
              : f.fromUserId;
          return _pinnedFriends.contains(friendUserId);
        }).toList();

        final unpinnedFiltered = filtered.where((f) {
          final friendUserId = f.fromUserId == _friendRequestService.currentUserId
              ? f.toUserId
              : f.fromUserId;
          return !_pinnedFriends.contains(friendUserId);
        }).toList();

        _filteredFriends = [...pinnedFiltered, ...unpinnedFiltered];
      }
    });
  }

  void _togglePin(String friendUserId) {
    setState(() {
      if (_pinnedFriends.contains(friendUserId)) {
        _pinnedFriends.remove(friendUserId);
      } else {
        _pinnedFriends.add(friendUserId);
      }
      _sortAndFilterFriends();
    });
  }

  Future<void> _onAddPressed() async {
    final choice = await showAddChatSheet(context);
    if (choice == null || !mounted) return;
    switch (choice) {
      case AddChatOption.groupChat:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NewGroupChatScreen()),
        );
        break;
    }
  }

  /// A chat row with a hairline under it, starting where the text starts.
  Widget _withDivider(Widget tile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        Divider(
          height: 1,
          thickness: 0.6,
          indent: 80,
          color: context.chatColors.line,
        ),
      ],
    );
  }

  /// One entry in a row's "..." menu.
  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {bool destructive = false}) {
    final color = destructive ? context.colors.danger : context.chatColors.ink;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 16, color: color)),
        ],
      ),
    );
  }

  /// The quiet "..." button at the end of each row.
  Widget _menuButton({
    required PopupMenuItemBuilder<String> itemBuilder,
    required PopupMenuItemSelected<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: context.chatColors.sub, size: 22),
      splashRadius: 20,
      color: context.colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onSelected,
      itemBuilder: itemBuilder,
    );
  }

  Widget _previewText(String text) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13.5, color: context.chatColors.sub),
    );
  }

  Future<void> _deleteGroup(GroupChat group) async {
    final myId = _friendRequestService.currentUserId;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
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
              style: TextButton.styleFrom(foregroundColor: context.colors.danger),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await _groupService.leaveGroup(
      group.id,
      myUsername: group.memberUsernames[myId] ?? 'Someone',
    );
  }

  /// Group chat row: same look as a friend row, titled with the group's
  /// name or the members' usernames.
  Widget _buildGroupTile(GroupChat group) {
    final myId = _friendRequestService.currentUserId;
    final title = group.displayName(myId);
    final isPinned = group.isPinnedFor(myId);
    String preview = 'Group chat';
    if (group.lastMessageText != null && group.lastMessageText!.isNotEmpty) {
      final sender = group.lastSenderUsername;
      preview = sender == null
          ? group.lastMessageText!
          : '$sender: ${group.lastMessageText!}';
    }
    final muted = group.isMutedFor(myId);
    final badge = ChatBadge.fromCounts(group.unreadFor(myId));
    final isNewGroup =
        badge == null && group.createdBy != myId && _isNew(group.id);
    final unread = badge != null || isNewGroup;

    final Widget subtitle = badge != null
        ? ChatStatusLine(icon: badge.icon, label: badge.label, muted: muted)
        : isNewGroup
        ? ChatStatusLine(
        icon: Icons.group_add_outlined,
        label: 'New group',
        muted: muted)
        : _previewText(preview);

    return _withDivider(
      ChatRow(
        avatar: GroupIcon(iconUrl: group.iconUrl, name: title),
        title: title,
        subtitle: subtitle,
        time: chatAgo(group.lastMessageAt),
        unread: unread,
        muted: muted,
        pinned: isPinned,
        menu: _menuButton(
          onSelected: (value) {
            if (value == 'pin') {
              _groupService.togglePin(group.id, !isPinned);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isPinned ? 'Unpinned!' : 'Pinned!'),
                  duration: const Duration(seconds: 2),
                ),
              );
            } else if (value == 'manage') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManageGroupChatScreen(groupId: group.id),
                ),
              );
            } else if (value == 'delete') {
              _deleteGroup(group);
            }
          },
          itemBuilder: (context) => [
            _menuItem('pin',
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                isPinned ? 'Unpin' : 'Pin'),
            _menuItem('manage', Icons.settings_outlined, 'Manage Chat'),
            _menuItem('delete', Icons.delete_outline, 'Delete',
                destructive: true),
          ],
        ),
        onTap: () {
          _markMet(group.id);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupChatScreen(groupId: group.id),
            ),
          );
        },
      ),
    );
  }

  /// 1:1 friend chat row.
  Widget _buildFriendTile(FriendRequest friendRequest) {
    final myUid = _friendRequestService.currentUserId;
    final isCurrentUserSender = friendRequest.fromUserId == myUid;
    final friendName = isCurrentUserSender
        ? friendRequest.toUsername
        : friendRequest.fromUsername;
    final friendUserId = isCurrentUserSender
        ? friendRequest.toUserId
        : friendRequest.fromUserId;
    final isPinned = _pinnedFriends.contains(friendUserId);
    final act = _activity[friendUserId];
    final muted = act?.muted ?? false;
    final badge = ChatBadge.fromCounts(act?.counts ?? const {});
    final isNewFriend = badge == null && _isNew(friendUserId);
    final unread = badge != null || isNewFriend;

    String preview = 'Friends on Kaidose';
    if (act?.lastPreview != null && act!.lastPreview!.isNotEmpty) {
      preview = act.lastSender == myUid
          ? 'You: ${act.lastPreview!}'
          : act.lastPreview!;
    }

    final Widget subtitle = badge != null
        ? ChatStatusLine(icon: badge.icon, label: badge.label, muted: muted)
        : isNewFriend
        ? ChatStatusLine(
        icon: Icons.waving_hand_outlined,
        label: 'New friend · say hi',
        muted: muted)
        : _previewText(preview);

    return _withDivider(
      ChatRow(
        avatar: MemberAvatar(userId: friendUserId, size: 50),
        onAvatarTap: () => UserProfileScreen.open(context, friendUserId,
            username: friendName),
        title: friendName,
        subtitle: subtitle,
        time: chatAgo(act?.lastTime),
        unread: unread,
        muted: muted,
        pinned: isPinned,
        menu: _menuButton(
          onSelected: (value) {
            if (value == 'pin') {
              _togglePin(friendUserId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isPinned ? '$friendName unpinned!' : '$friendName pinned!',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            } else if (value == 'add_to_daily') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddToDailyScreen(
                    friendName: friendName,
                    friendUserId: friendUserId,
                  ),
                ),
              );
            } else if (value == 'manage') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ManageChatScreen(
                    friendUserId: friendUserId,
                    friendUsername: friendName,
                  ),
                ),
              );
            }
          },
          itemBuilder: (context) => [
            _menuItem('pin',
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                isPinned ? 'Unpin' : 'Pin'),
            _menuItem('manage', Icons.settings_outlined, 'Manage Chat'),
            _menuItem('add_to_daily', Icons.add_circle_outline, 'Add to Daily'),
          ],
        ),
        onTap: () {
          _markMet(friendUserId);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                friendUserId: friendUserId,
                friendUsername: friendName,
              ),
            ),
          );
        },
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _sortAndFilterFriends();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // The whole page scrolls: the "Chats" header slides away with the list
    // and slides back as soon as you scroll up a little (floating + snap).
    return Scaffold(
      backgroundColor: context.colors.background,
      body: NestedScrollView(
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, innerScrolled) => [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: context.colors.background,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: _isSearching
                ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search chats...',
                hintStyle: TextStyle(
                  color: kc.grey(500),
                  fontSize: 18,
                ),
                border: InputBorder.none,
              ),
              style: TextStyle(
                fontSize: 18,
                color: context.colors.text,
              ),
            )
                : Text(
              'Chats',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: context.colors.text,
              ),
            ),
            centerTitle: false,
            actions: [
              IconButton(
                icon: Icon(Icons.add_circle_outline,
                    color: context.colors.text, size: 28),
                onPressed: _onAddPressed,
              ),
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  color: context.colors.text,
                  size: 28,
                ),
                onPressed: _toggleSearch,
              ),
            ],
          ),
        ],
        body: StreamBuilder<List<GroupChat>>(
          stream: _groupService.getMyGroups(),
          builder: (context, groupSnapshot) {
            final query = _searchController.text.trim().toLowerCase();
            final myId = _friendRequestService.currentUserId;
            final groups = (groupSnapshot.data ?? <GroupChat>[]).where((g) {
              return query.isEmpty ||
                  g.displayName(myId).toLowerCase().contains(query) ||
                  g.namesExcluding(myId).toLowerCase().contains(query);
            }).toList();
            return _buildChatList(groups);
          },
        ),
      ),
    );
  }

  Widget _buildChatList(List<GroupChat> groups) {
    return StreamBuilder<List<FriendRequest>>(
      stream: _friendRequestService.getAcceptedFriends(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        _acceptedFriends = snapshot.data ?? [];
        _sortAndFilterFriends();

        if (_filteredFriends.isEmpty && groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isSearching ? Icons.search_off : Icons.chat_bubble_outline,
                  size: 80,
                  color: context.colors.textFaint,
                ),
                const SizedBox(height: 16),
                Text(
                  _isSearching ? 'No Results Found' : 'No Friends Yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    _isSearching
                        ? 'Try searching for a different name'
                        : 'Add friends from Search to start chatting',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.colors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        _seedKnown([
          ...groups.map((g) => g.id),
          ..._acceptedFriends.map((f) =>
          f.fromUserId == _friendRequestService.currentUserId
              ? f.toUserId
              : f.fromUserId),
        ]);

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: groups.length + _filteredFriends.length,
          itemBuilder: (context, index) {
            if (index < groups.length) return _buildGroupTile(groups[index]);
            return _buildFriendTile(_filteredFriends[index - groups.length]);
          },
        );
      },
    );
  }
}