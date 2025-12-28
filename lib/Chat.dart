import 'package:flutter/material.dart';
import 'LinkedFriends.dart';
import 'AddToDaily.dart';

class ChatWidget extends StatefulWidget {
  const ChatWidget({Key? key}) : super(key: key);

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> with AutomaticKeepAliveClientMixin {
  List<LinkedFriend> _linkedFriends = [];
  List<LinkedFriend> _filteredFriends = [];
  Set<String> _pinnedFriends = {}; // Track pinned friends by name
  VoidCallback? _linkedFriendsListener;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadLinkedFriends();

    _linkedFriendsListener = () {
      if (mounted) {
        setState(() {
          // Only show accepted friends in chat
          _linkedFriends = LinkedFriends.acceptedFriends;
          _sortAndFilterFriends();
        });
      }
    };

    LinkedFriends.addListener(_linkedFriendsListener!);

    // Listen to search input
    _searchController.addListener(_filterFriends);
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_linkedFriendsListener != null) {
      LinkedFriends.removeListener(_linkedFriendsListener!);
    }
    super.dispose();
  }

  Future<void> _loadLinkedFriends() async {
    await LinkedFriends.loadFromStorage();

    // Auto-accept all pending friends (temporary fix for existing data)
    // TODO: Remove this once you have proper acceptance flow with database
    final pendingFriends = LinkedFriends.pendingRequests;
    for (var friend in pendingFriends) {
      await LinkedFriends.acceptLinkRequest(friend.name);
    }

    if (mounted) {
      setState(() {
        // Only show accepted friends
        _linkedFriends = LinkedFriends.acceptedFriends;
        _sortAndFilterFriends();
      });
    }
  }

  void _sortAndFilterFriends() {
    // Sort friends: pinned ones first, then others
    final pinnedList = _linkedFriends.where((f) => _pinnedFriends.contains(f.name)).toList();
    final unpinnedList = _linkedFriends.where((f) => !_pinnedFriends.contains(f.name)).toList();

    _filteredFriends = [...pinnedList, ...unpinnedList];
  }

  void _filterFriends() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _sortAndFilterFriends();
      } else {
        // Filter and maintain pin order
        final filtered = _linkedFriends.where((friend) {
          return friend.name.toLowerCase().contains(query);
        }).toList();

        final pinnedFiltered = filtered.where((f) => _pinnedFriends.contains(f.name)).toList();
        final unpinnedFiltered = filtered.where((f) => !_pinnedFriends.contains(f.name)).toList();

        _filteredFriends = [...pinnedFiltered, ...unpinnedFiltered];
      }
    });
  }

  void _togglePin(String friendName) {
    setState(() {
      if (_pinnedFriends.contains(friendName)) {
        _pinnedFriends.remove(friendName);
      } else {
        _pinnedFriends.add(friendName);
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
    super.build(context); // IMPORTANT: Call super.build for AutomaticKeepAliveClientMixin
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
      body: _filteredFriends.isEmpty
          ? Center(
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
              _isSearching ? 'No Results Found' : 'No Linked Friends Yet',
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
                    : 'Link friends from Search to start chatting',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredFriends.length,
        itemBuilder: (context, index) {
          final friend = _filteredFriends[index];
          final isPinned = _pinnedFriends.contains(friend.name);

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
                      color: Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Head circle
                          Positioned(
                            top: 12,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          // Body/shoulders
                          Positioned(
                            bottom: -6,
                            child: Container(
                              width: 44,
                              height: 26,
                              decoration: BoxDecoration(
                                color: Colors.grey[600],
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
                friend.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              subtitle: Text(
                'Linked ${_formatDate(friend.linkedDate)}',
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
                    _togglePin(friend.name);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isPinned
                              ? '${friend.name} unpinned!'
                              : '${friend.name} pinned!',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } else if (value == 'add_to_daily') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AddToDailyScreen(friendName: friend.name),
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
                // TODO: Open chat with this friend
                print('Open chat with ${friend.name}');
              },
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    }
  }
}