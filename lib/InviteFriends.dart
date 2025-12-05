import 'package:flutter/material.dart';
import 'LinkedFriends.dart';

class InviteFriends extends StatefulWidget {
  final Function(Set<String>) onInvitedFriendsChanged;

  const InviteFriends({
    Key? key,
    required this.onInvitedFriendsChanged,
  }) : super(key: key);

  @override
  State<InviteFriends> createState() => _InviteFriendsState();
}

class _InviteFriendsState extends State<InviteFriends> {
  List<LinkedFriend> _linkedFriends = [];
  List<LinkedFriend> _filteredFriends = [];
  Set<String> _invitedFriendNames = {};
  final TextEditingController _searchController = TextEditingController();
  VoidCallback? _linkedFriendsListener;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLinkedFriends();

    _linkedFriendsListener = () {
      if (mounted) {
        setState(() {
          _linkedFriends = LinkedFriends.acceptedFriends;
          _filterFriends();
        });
      }
    };

    LinkedFriends.addListener(_linkedFriendsListener!);
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
    setState(() {
      _isLoading = true;
    });

    await LinkedFriends.loadFromStorage();

    if (mounted) {
      setState(() {
        _linkedFriends = LinkedFriends.acceptedFriends;
        _filteredFriends = _linkedFriends;
        _isLoading = false;
      });
    }
  }

  void _filterFriends() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredFriends = _linkedFriends;
      } else {
        _filteredFriends = _linkedFriends.where((friend) {
          return friend.name.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _toggleInvite(String friendName) {
    setState(() {
      if (_invitedFriendNames.contains(friendName)) {
        _invitedFriendNames.remove(friendName);
      } else {
        _invitedFriendNames.add(friendName);
      }
    });
    widget.onInvitedFriendsChanged(_invitedFriendNames);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: Colors.white,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search friends...',
              hintStyle: TextStyle(
                color: Colors.grey[400],
                fontSize: 16,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: Colors.grey[600],
                size: 22,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                icon: Icon(
                  Icons.clear,
                  color: Colors.grey[600],
                  size: 20,
                ),
                onPressed: () {
                  _searchController.clear();
                },
              )
                  : null,
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Colors.cyan,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ),

        // Friends list
        Expanded(
          child: _isLoading
              ? const Center(
            child: CircularProgressIndicator(
              color: Colors.cyan,
            ),
          )
              : _filteredFriends.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _searchController.text.isNotEmpty
                      ? Icons.search_off
                      : Icons.people_outline,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  _searchController.text.isNotEmpty
                      ? 'No Results Found'
                      : 'No Linked Friends Yet',
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
                    _searchController.text.isNotEmpty
                        ? 'Try searching for a different name'
                        : 'Link friends from Search to invite them to your daily',
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            itemCount: _filteredFriends.length,
            itemBuilder: (context, index) {
              final friend = _filteredFriends[index];
              final isInvited = _invitedFriendNames.contains(friend.name);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isInvited ? Colors.cyan.withOpacity(0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isInvited ? Colors.cyan : Colors.grey[300]!,
                    width: isInvited ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Profile picture
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
                    const SizedBox(width: 12),
                    // Friend name
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            friend.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Linked ${_formatDate(friend.linkedDate)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Invite/Pending button
                    GestureDetector(
                      onTap: () => _toggleInvite(friend.name),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isInvited ? Colors.orange : Colors.cyan,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isInvited ? Icons.schedule : Icons.person_add,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isInvited ? 'Pending' : 'Invite',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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