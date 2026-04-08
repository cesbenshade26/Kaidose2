import 'package:flutter/material.dart';
import 'friend_request_service.dart';
import 'user_service.dart';
import 'AddToDaily.dart';
import 'ChatScreen.dart';

class ChatWidget extends StatefulWidget {
  const ChatWidget({Key? key}) : super(key: key);

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> with AutomaticKeepAliveClientMixin {
  List<FriendRequest> _acceptedFriends = [];
  List<FriendRequest> _filteredFriends = [];
  Set<String> _pinnedFriends = {}; // Track pinned friends by userId
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FriendRequestService _friendRequestService = FriendRequestService();

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
    // Sort friends: pinned ones first, then others
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
        // Filter and maintain pin order
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
            : const Text(
          'Chats',
          style: TextStyle(
            fontFamily: 'Slackey',
            fontSize: 32,
            color: Colors.cyan,
            fontWeight: FontWeight.normal,
          ),
        ),
        centerTitle: false,
        actions: [
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
      body: StreamBuilder<List<FriendRequest>>(
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

          if (_filteredFriends.isEmpty) {
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
            padding: const EdgeInsets.all(16),
            itemCount: _filteredFriends.length,
            itemBuilder: (context, index) {
              final friendRequest = _filteredFriends[index];
              final isCurrentUserSender = friendRequest.fromUserId == _friendRequestService.currentUserId;
              final friendName = isCurrentUserSender
                  ? friendRequest.toUsername
                  : friendRequest.fromUsername;
              final friendUserId = isCurrentUserSender
                  ? friendRequest.toUserId
                  : friendRequest.fromUserId;
              final isPinned = _pinnedFriends.contains(friendUserId);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isPinned ? Colors.cyan : Colors.grey[300]!,
                      width: isPinned ? 2 : 1,
                    ),
                  ),
                  leading: Stack(
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
                            builder: (context) => AddToDailyScreen(friendName: friendName),
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
      ),
    );
  }
}