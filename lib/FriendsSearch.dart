import 'package:flutter/material.dart';
import 'AccessContacts.dart';
import 'LinkedFriends.dart';

class FriendsSearchWidget extends StatefulWidget {
  const FriendsSearchWidget({Key? key}) : super(key: key);

  @override
  State<FriendsSearchWidget> createState() => _FriendsSearchWidgetState();
}

class _FriendsSearchWidgetState extends State<FriendsSearchWidget> {
  List<ContactData> _contacts = [];
  bool _isLoadingContacts = false;
  bool _hasContactsPermission = false;
  bool _hasAttemptedLoad = false;

  @override
  void initState() {
    super.initState();
    // Auto-load contacts when widget is created
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoadingContacts = true;
    });

    try {
      // This will trigger the native iOS/Android permission dialog automatically if needed
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

  // Sort contacts by frequency (most contacted first)
  List<ContactData> _sortContactsByFrequency(List<ContactData> contacts) {
    // Create a mutable copy
    final sortedContacts = List<ContactData>.from(contacts);

    // Sort alphabetically as fallback since we don't have access to
    // message/call frequency data from contacts_service
    // In the future, you could integrate with device logs or your own messaging data
    sortedContacts.sort((a, b) {
      final nameA = a.displayName?.toLowerCase() ?? '';
      final nameB = b.displayName?.toLowerCase() ?? '';
      return nameA.compareTo(nameB);
    });

    return sortedContacts;
  }

  @override
  Widget build(BuildContext context) {
    return _buildContactsList();
  }

  Widget _buildContactsList() {
    if (_isLoadingContacts) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.cyan,
        ),
      );
    }

    if (!_hasContactsPermission && _contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.contacts_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Access to Contacts',
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
                'Grant permission to see your contacts',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadContacts,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Grant Access',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Contacts Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have no contacts on your device',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _contacts.length,
      itemBuilder: (context, index) {
        final contact = _contacts[index];
        final isLinked = LinkedFriends.isLinked(contact.displayName ?? '');
        final isPending = LinkedFriends.isPending(contact.displayName ?? '');

        return GestureDetector(
          onTap: () {
            // Navigate to contact's profile page
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
                // Profile picture - default Instagram-style icon
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
                // Contact name
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
                // Link button or status
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
                        Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Linked',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                        Icon(
                          Icons.schedule,
                          color: Colors.white,
                          size: 16,
                        ),
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
                      print('Link button tapped for ${contact.displayName}');
                      await LinkedFriends.linkFriend(
                        contact.displayName ?? 'Unknown',
                        phoneNumber: contact.phoneNumber,
                        // TODO: Add userId when you have database
                        // userId: contact.userId,
                      );
                      if (context.mounted) {
                        setState(() {}); // Refresh to show pending status
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
                          Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 16,
                          ),
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
      },
    );
  }

  // Helper method to get initials from name
  String _getInitials(String name) {
    if (name.isEmpty) return 'U';

    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      // First and last name initials
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts.first.isNotEmpty) {
      // Just first initial
      return parts.first[0].toUpperCase();
    }
    return 'U';
  }
}

// Contact Profile Screen
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
          onPressed: () {
            Navigator.pop(context);
          },
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
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}