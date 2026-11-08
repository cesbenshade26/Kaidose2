import 'package:flutter/material.dart';
import 'friend_request_service.dart';
import 'user_service.dart';
import 'AddToDaily.dart';
import 'ChatScreen.dart';
import 'ManageChat.dart';
import 'KaidoseBrand.dart';
import 'AddChatSheet.dart';
import 'NewGroupChat.dart';
import 'GroupChatService.dart';
import 'GroupChatScreen.dart';
import 'ManageGroupChat.dart';
import 'UserProfileScreen.dart';

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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterFriends);
  }

  @override
  void dispose() {
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

  /// A chat row followed by a thin line running the full width of the screen.
  Widget _withDivider(Widget tile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        Divider(height: 1, thickness: 0.5, color: Colors.grey[300]),
      ],
    );
  }

  Future<void> _deleteGroup(GroupChat group) async {
    final myId = _friendRequestService.currentUserId;
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
    String subtitle = 'Group chat';
    if (group.lastMessageText != null && group.lastMessageText!.isNotEmpty) {
      final sender = group.lastSenderUsername;
      subtitle = sender == null
          ? group.lastMessageText!
          : '$sender: ${group.lastMessageText!}';
    }

    return _withDivider(
      ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        tileColor: isPinned ? Colors.cyan.withOpacity(0.06) : Colors.white,
        leading: Stack(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.group, color: Colors.cyan[700], size: 26),
            ),
            if (isPinned)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.cyan,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.push_pin,
                      size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 24),
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
          itemBuilder: (BuildContext context) => [
            PopupMenuItem<String>(
              value: 'pin',
              child: Row(
                children: [
                  Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 20, color: Colors.black87),
                  const SizedBox(width: 12),
                  Text(isPinned ? 'Unpin' : 'Pin',
                      style: const TextStyle(
                          fontSize: 16, color: Colors.black87)),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'manage',
              child: Row(
                children: [
                  Icon(Icons.settings_outlined,
                      size: 20, color: Colors.black87),
                  SizedBox(width: 12),
                  Text('Manage Chat',
                      style: TextStyle(fontSize: 16, color: Colors.black87)),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Delete',
                      style: TextStyle(fontSize: 16, color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: () {
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: _isSearching
            ? TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search chats...',
            hintStyle: TextStyle(
              color: Colors.grey,
              fontSize: 18,
            ),
            border: InputBorder.none,
          ),
          style: const TextStyle(
            fontSize: 18,
            color: Colors.black,
          ),
        )
            : Text(
          'Chats',
          style: KaidoseBrand.wordmark(32),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                color: Colors.black, size: 28),
            onPressed: _onAddPressed,
          ),
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: Colors.black,
              size: 28,
            ),
            onPressed: _toggleSearch,
          ),
        ],
      ),
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
    );
  }

  Widget _buildChatList(List<GroupChat> groups) {
    return StreamBuilder<List<FriendRequest>>(
      stream: _friendRequestService.getAcceptedFriends(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
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
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  _isSearching ? 'No Results Found' : 'No Friends Yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
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
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: groups.length + _filteredFriends.length,
          itemBuilder: (context, index) {
            if (index < groups.length) return _buildGroupTile(groups[index]);
            final friendRequest = _filteredFriends[index - groups.length];
            final isCurrentUserSender = friendRequest.fromUserId == _friendRequestService.currentUserId;
            final friendName = isCurrentUserSender
                ? friendRequest.toUsername
                : friendRequest.fromUsername;
            final friendUserId = isCurrentUserSender
                ? friendRequest.toUserId
                : friendRequest.fromUserId;
            final isPinned = _pinnedFriends.contains(friendUserId);

            return _withDivider(
              ListTile(
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                tileColor:
                isPinned ? Colors.cyan.withOpacity(0.06) : Colors.white,
                leading: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => UserProfileScreen.open(context, friendUserId,
                      username: friendName),
                  child: Stack(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.cyan.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                top: 12,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.cyan[700],
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: -6,
                                child: Container(
                                  width: 44,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: Colors.cyan[700],
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(22),
                                      topRight: Radius.circular(22),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isPinned)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.cyan,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.push_pin,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                title: Text(
                  friendName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                subtitle: Text(
                  'Friends on Kaidose',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: Colors.grey[600],
                    size: 24,
                  ),
                  color: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    if (value == 'pin') {
                      _togglePin(friendUserId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isPinned
                                ? '$friendName unpinned!'
                                : '$friendName pinned!',
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
                            friendUserId: friendUserId, // ADDED: Pass friendUserId
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
                  itemBuilder: (BuildContext context) => [
                    PopupMenuItem<String>(
                      value: 'pin',
                      child: Row(
                        children: [
                          Icon(
                            isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            size: 20,
                            color: Colors.black87,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isPinned ? 'Unpin' : 'Pin',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'manage',
                      child: Row(
                        children: [
                          Icon(Icons.settings_outlined, size: 20, color: Colors.black87),
                          SizedBox(width: 12),
                          Text(
                            'Manage Chat',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'add_to_daily',
                      child: Row(
                        children: [
                          Icon(Icons.add_circle_outline, size: 20, color: Colors.black87),
                          SizedBox(width: 12),
                          Text(
                            'Add to Daily',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                onTap: () {
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
          },
        );
      },
    );
  }
}