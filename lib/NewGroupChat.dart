import 'package:flutter/material.dart';
import 'friend_request_service.dart';
import 'user_service.dart';
import 'GroupChatService.dart';
import 'GroupChatScreen.dart';

/// Pick friends, then create the group.
class NewGroupChatScreen extends StatefulWidget {
  const NewGroupChatScreen({Key? key}) : super(key: key);

  @override
  State<NewGroupChatScreen> createState() => _NewGroupChatScreenState();
}

class _NewGroupChatScreenState extends State<NewGroupChatScreen> {
  final FriendRequestService _friendService = FriendRequestService();
  final GroupChatService _groupService = GroupChatService();
  final UserService _userService = UserService();
  final TextEditingController _search = TextEditingController();

  /// uid -> username, in the order they were checked.
  final Map<String, String> _selected = {};
  bool _creating = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_selected.length < 2 || _creating) return;
    setState(() => _creating = true);
    try {
      final myId = _groupService.currentUserId ?? '';
      final me = await _userService.getUserById(myId);
      final groupId = await _groupService.createGroup(
        others: Map<String, String>.from(_selected),
        myUsername: me?.username ?? 'You',
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(groupId: groupId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create group: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = _selected.values.toList();
    final ready = names.length >= 2;
    final myId = _friendService.currentUserId;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('New group',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search friends',
                prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<FriendRequest>>(
              stream: _friendService.getAcceptedFriends(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.cyan));
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final query = _search.text.trim().toLowerCase();
                final friends = <MapEntry<String, String>>[]; // uid, username
                for (final f in snapshot.data ?? <FriendRequest>[]) {
                  final mine = f.fromUserId == myId;
                  final uid = mine ? f.toUserId : f.fromUserId;
                  final name = mine ? f.toUsername : f.fromUsername;
                  if (query.isEmpty || name.toLowerCase().contains(query)) {
                    friends.add(MapEntry(uid, name));
                  }
                }
                friends.sort((a, b) =>
                    a.value.toLowerCase().compareTo(b.value.toLowerCase()));

                if (friends.isEmpty) {
                  return Center(
                    child: Text(
                      query.isEmpty ? 'No friends yet' : 'No friends found',
                      style: TextStyle(color: Colors.grey[600], fontSize: 15),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: friends.length,
                  itemBuilder: (context, i) {
                    final uid = friends[i].key;
                    final name = friends[i].value;
                    final checked = _selected.containsKey(uid);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.cyan.withOpacity(0.2),
                        child: Icon(Icons.person, color: Colors.cyan[700]),
                      ),
                      title: Text(name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      trailing: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: checked ? Colors.cyan : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: checked ? Colors.cyan : Colors.grey[400]!,
                            width: 2,
                          ),
                        ),
                        child: checked
                            ? const Icon(Icons.check,
                            size: 16, color: Colors.white)
                            : null,
                      ),
                      onTap: () => setState(() {
                        if (checked) {
                          _selected.remove(uid);
                        } else {
                          _selected[uid] = name;
                        }
                      }),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: ready && !_creating ? _create : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    disabledBackgroundColor: Colors.grey[300],
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.grey[600],
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: _creating
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                      : Text(
                    names.isEmpty
                        ? 'Select at least 2 friends'
                        : ready
                        ? 'Create group: ${names.join(', ')}'
                        : 'Select 1 more friend (${names.join(', ')})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}