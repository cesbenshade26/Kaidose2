import 'package:flutter/material.dart';
import 'daily_invitation_service.dart';
import 'user_service.dart';
import 'friend_request_service.dart';

class InviteFriends extends StatefulWidget {
  final String dailyId;
  final String dailyTitle;
  final Function(Set<String>) onInvitedFriendsChanged;

  const InviteFriends({
    Key? key,
    required this.dailyId,
    required this.dailyTitle,
    required this.onInvitedFriendsChanged,
  }) : super(key: key);

  @override
  State<InviteFriends> createState() => _InviteFriendsState();
}

class _InviteFriendsState extends State<InviteFriends> {
  final DailyInvitationService _invitationService = DailyInvitationService();
  final UserService _userService = UserService();
  final FriendRequestService _friendRequestService = FriendRequestService();
  final TextEditingController _searchController = TextEditingController();

  Set<String> _invitedFriendIds = {};
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _searchController.addListener(() {
      setState(() {}); // Just trigger rebuild when search text changes
    });
  }

  Future<void> _loadCurrentUser() async {
    final user = await _userService.getUserById(_invitationService.currentUserId ?? '');
    if (mounted) {
      setState(() {
        _currentUsername = user?.username ?? 'Someone';
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FriendRequest> _filterFriends(List<FriendRequest> friends) {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      return friends;
    }
    return friends.where((friendRequest) {
      final friendName = friendRequest.fromUserId == _friendRequestService.currentUserId
          ? friendRequest.toUsername
          : friendRequest.fromUsername;
      return friendName.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _toggleInvite(FriendRequest friendRequest) async {
    if (_currentUsername == null) return;

    final isCurrentUserSender = friendRequest.fromUserId == _friendRequestService.currentUserId;
    final friendUserId = isCurrentUserSender ? friendRequest.toUserId : friendRequest.fromUserId;
    final friendUsername = isCurrentUserSender ? friendRequest.toUsername : friendRequest.fromUsername;

    if (_invitedFriendIds.contains(friendUserId)) {
      // Remove invitation
      setState(() {
        _invitedFriendIds.remove(friendUserId);
      });
    } else {
      // Send invitation
      final result = await _invitationService.sendDailyInvitation(
        dailyId: widget.dailyId,
        dailyTitle: widget.dailyTitle,
        toUserId: friendUserId,
        toUsername: friendUsername,
        fromUsername: _currentUsername!,
      );

      if (mounted) {
        if (result['success']) {
          setState(() {
            _invitedFriendIds.add(friendUserId);
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Failed to send invitation'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    widget.onInvitedFriendsChanged(_invitedFriendIds);
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
          child: StreamBuilder<List<FriendRequest>>(
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

              final acceptedFriends = snapshot.data ?? [];
              final filteredFriends = _filterFriends(acceptedFriends);

              if (filteredFriends.isEmpty) {
                return Center(
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
                            : 'No Friends Yet',
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
                              : 'Add friends from Search to invite them to your daily',
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: filteredFriends.length,
                itemBuilder: (context, index) {
                  final friendRequest = filteredFriends[index];
                  final isCurrentUserSender = friendRequest.fromUserId == _friendRequestService.currentUserId;
                  final friendUserId = isCurrentUserSender ? friendRequest.toUserId : friendRequest.fromUserId;
                  final friendUsername = isCurrentUserSender ? friendRequest.toUsername : friendRequest.fromUsername;
                  final isInvited = _invitedFriendIds.contains(friendUserId);

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
                        const SizedBox(width: 12),
                        // Friend name
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                friendUsername,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Friends on Kaidose',
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
                          onTap: () => _toggleInvite(friendRequest),
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
              );
            },
          ),
        ),
      ],
    );
  }
}