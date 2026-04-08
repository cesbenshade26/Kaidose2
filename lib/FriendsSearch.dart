import 'package:flutter/material.dart';
import 'AccessContacts.dart';
import 'LinkedFriends.dart';
import 'user_service.dart';
import 'friend_request_service.dart';

class FriendsSearchWidget extends StatefulWidget {
  const FriendsSearchWidget({Key? key}) : super(key: key);

  @override
  State<FriendsSearchWidget> createState() => _FriendsSearchWidgetState();
}

class _FriendsSearchWidgetState extends State<FriendsSearchWidget> {
  List<ContactData> _contacts = [];
  List<KaidoseUser> _kaidoseUsers = [];
  List<KaidoseUser> _filteredKaidoseUsers = [];
  bool _isLoadingContacts = false;
  bool _isLoadingUsers = false;
  bool _hasContactsPermission = false;

  final UserService _userService = UserService();
  final FriendRequestService _friendRequestService = FriendRequestService();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadKaidoseUsers();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoadingContacts = true;
    });

    try {
      final contacts = await AccessContacts.loadContacts(context);

      if (mounted) {
        setState(() {
          _contacts = _sortContactsByFrequency(contacts);
          _hasContactsPermission = contacts.isNotEmpty;
          _isLoadingContacts = false;
        });
      }
    } catch (e) {
      print('Error loading contacts: $e');
      if (mounted) {
        setState(() {
          _hasContactsPermission = false;
          _isLoadingContacts = false;
        });
      }
    }
  }

  Future<void> _loadKaidoseUsers() async {
    setState(() {
      _isLoadingUsers = true;
    });

    try {
      final users = await _userService.getAllUsers();

      // Filter out users who are already friends
      final filteredUsers = <KaidoseUser>[];
      for (var user in users) {
        final isFriend = await _friendRequestService.areFriends(
          _friendRequestService.currentUserId ?? '',
          user.uid,
        );
        if (!isFriend) {
          filteredUsers.add(user);
        }
      }

      if (mounted) {
        setState(() {
          _kaidoseUsers = users;
          _filteredKaidoseUsers = filteredUsers;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      print('Error loading Kaidose users: $e');
      if (mounted) {
        setState(() {
          _isLoadingUsers = false;
        });
      }
    }
  }

  List<ContactData> _sortContactsByFrequency(List<ContactData> contacts) {
    final sortedContacts = List<ContactData>.from(contacts);
    sortedContacts.sort((a, b) {
      final nameA = a.displayName?.toLowerCase() ?? '';
      final nameB = b.displayName?.toLowerCase() ?? '';
      return nameA.compareTo(nameB);
    });
    return sortedContacts;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingContacts || _isLoadingUsers) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.cyan,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Kaidose Users Section
        if (_filteredKaidoseUsers.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Row(
              children: [
                Icon(Icons.people, color: Colors.cyan, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Kaidose Users',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
          ..._filteredKaidoseUsers.map((user) => _buildKaidoseUserCard(user)).toList(),
          const SizedBox(height: 24),
        ],

        // Contacts Section
        if (_contacts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Row(
              children: [
                Icon(Icons.contacts, color: Colors.grey[600], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Phone Contacts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
          ..._contacts.map((contact) => _buildContactCard(contact)).toList(),
        ],

        // Empty state
        if (_filteredKaidoseUsers.isEmpty && _contacts.isEmpty)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 80),
                Icon(
                  Icons.people_outline,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No Users Found',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'All users are already your friends!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildKaidoseUserCard(KaidoseUser user) {
    final isLinked = LinkedFriends.isLinkedByUserId(user.uid);
    final isPending = LinkedFriends.isPendingByUserId(user.uid);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(
              userId: user.uid,
              username: user.username,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.cyan.withOpacity(0.3),
            width: 1.5,
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
            // Username
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Kaidose User',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.cyan[700],
                    ),
                  ),
                ],
              ),
            ),
            // Link button or status
            if (isPending)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Pending',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else
              GestureDetector(
                onTap: () async {
                  // Get current user's username
                  final currentUser = await _userService.getUserById(
                      _friendRequestService.currentUserId ?? ''
                  );

                  if (currentUser == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Error: Could not get your username'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }

                  // Send friend request via Firebase
                  final result = await _friendRequestService.sendFriendRequest(
                    toUserId: user.uid,
                    toUsername: user.username,
                    fromUsername: currentUser.username,
                  );

                  if (context.mounted) {
                    if (result['success']) {
                      // Also update local LinkedFriends for immediate UI update
                      await LinkedFriends.linkFriend(
                        user.username,
                        userId: user.uid,
                      );

                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Friend request sent to ${user.username}!'),
                          duration: const Duration(seconds: 2),
                          backgroundColor: Colors.cyan,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result['error'] ?? 'Failed to send request'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.cyan,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Link',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(ContactData contact) {
    final isLinked = LinkedFriends.isLinked(contact.displayName ?? '');
    final isPending = LinkedFriends.isPending(contact.displayName ?? '');

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ContactProfileScreen(
              contactName: contact.displayName ?? 'Unknown',
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
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
            Expanded(
              child: Text(
                contact.displayName ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            if (isLinked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('Linked', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            else if (isPending)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('Pending', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            else
              GestureDetector(
                onTap: () async {
                  await LinkedFriends.linkFriend(
                    contact.displayName ?? 'Unknown',
                    phoneNumber: contact.phoneNumber,
                  );
                  if (context.mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Link request sent to ${contact.displayName}!'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.cyan,
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.cyan,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('Link', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// User Profile Screen (for Kaidose users)
class UserProfileScreen extends StatelessWidget {
  final String userId;
  final String username;

  const UserProfileScreen({
    Key? key,
    required this.userId,
    required this.username,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Text(
          "$username's profile",
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

// Contact Profile Screen (for phone contacts)
class ContactProfileScreen extends StatelessWidget {
  final String contactName;

  const ContactProfileScreen({Key? key, required this.contactName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Text(
          "$contactName's database",
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}