import 'package:flutter/material.dart';
import 'LinkedFriends.dart';

class ChatWidget extends StatefulWidget {
  const ChatWidget({Key? key}) : super(key: key);

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  List<LinkedFriend> _linkedFriends = [];
  VoidCallback? _linkedFriendsListener;

  @override
  void initState() {
    super.initState();
    _loadLinkedFriends();

    _linkedFriendsListener = () {
      if (mounted) {
        setState(() {
          _linkedFriends = LinkedFriends.linkedFriends;
        });
      }
    };

    LinkedFriends.addListener(_linkedFriendsListener!);
  }

  @override
  void dispose() {
    if (_linkedFriendsListener != null) {
      LinkedFriends.removeListener(_linkedFriendsListener!);
    }
    super.dispose();
  }

  Future<void> _loadLinkedFriends() async {
    await LinkedFriends.loadFromStorage();
    if (mounted) {
      setState(() {
        _linkedFriends = LinkedFriends.linkedFriends;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Chats',
          style: TextStyle(
            fontFamily: 'Slackey',
            fontSize: 32,
            color: Colors.cyan,
            fontWeight: FontWeight.normal,
          ),
        ),
        centerTitle: false,
      ),
      body: _linkedFriends.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Linked Friends Yet',
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
                'Link friends from Search to start chatting',
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
        itemCount: _linkedFriends.length,
        itemBuilder: (context, index) {
          final friend = _linkedFriends[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
              leading: Container(
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