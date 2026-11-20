import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'AccessContacts.dart';
import 'LinkedFriends.dart';
import 'user_service.dart';
import 'friend_request_service.dart';
import 'SearchService.dart';
import 'UserProfileScreen.dart';
import 'GroupAvatar.dart';
import 'Nearby.dart';

/// People in Search.
///
/// Nothing typed: "People you may know" (friends of your friends, with who
/// knows them, and verified accounts), "Near you" (opt-in, rough area
/// only), your friends, then your phone contacts. Typed: matching
/// people ranked so friends, friends-of-friends and verified accounts come
/// before strangers, plus matching phone contacts.
///
/// [embedded] renders a plain Column of at most [limit] people (no contacts)
/// for the All tab, with an optional [onSeeAll].
class FriendsSearchWidget extends StatefulWidget {
  final String searchQuery;
  final bool embedded;
  final int limit;
  final VoidCallback? onSeeAll;

  const FriendsSearchWidget({
    Key? key,
    this.searchQuery = '',
    this.embedded = false,
    this.limit = 3,
    this.onSeeAll,
  }) : super(key: key);

  @override
  State<FriendsSearchWidget> createState() => _FriendsSearchWidgetState();
}

class _FriendsSearchWidgetState extends State<FriendsSearchWidget> {
  List<ContactData> _contacts = [];
  List<PersonResult> _friends = [];
  List<PersonResult> _suggested = [];
  List<PersonResult> _results = [];
  List<PersonResult> _nearby = [];
  bool? _nearbyOn; // null until known
  bool _turningOnNearby = false;
  bool _isLoadingContacts = false;
  bool _isLoadingPeople = true;
  int _requestId = 0;

  final UserService _userService = UserService();
  final FriendRequestService _friendRequestService = FriendRequestService();

  bool get _typed => widget.searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (!widget.embedded) _loadContacts();
    _loadPeople();
  }

  @override
  void didUpdateWidget(FriendsSearchWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) _loadPeople();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoadingContacts = true);
    try {
      final contacts = await AccessContacts.loadContacts(context);
      if (mounted) {
        setState(() {
          _contacts = _sortContacts(contacts);
          _isLoadingContacts = false;
        });
      }
    } catch (e) {
      print('Error loading contacts: $e');
      if (mounted) setState(() => _isLoadingContacts = false);
    }
  }

  Future<void> _loadPeople() async {
    final id = ++_requestId;
    try {
      if (_typed) {
        final results = await SearchService.searchPeople(widget.searchQuery);
        if (!mounted || id != _requestId) return;
        setState(() {
          _results = results;
          _isLoadingPeople = false;
        });
      } else if (widget.embedded) {
        final suggested = await SearchService.suggestedPeople(limit: widget.limit);
        if (!mounted || id != _requestId) return;
        setState(() {
          _suggested = suggested;
          _isLoadingPeople = false;
        });
      } else {
        final results = await Future.wait<Object>([
          SearchService.myFriends(),
          SearchService.suggestedPeople(limit: 15),
          NearbyService.isOn(),
        ]);
        final on = results[2] as bool;
        final nearby = on
            ? await SearchService.nearbyPeople()
            : const <PersonResult>[];
        if (!mounted || id != _requestId) return;
        // Someone who's both nearby and a friend-of-friend shows once, in
        // "People you may know".
        final suggested = results[1] as List<PersonResult>;
        final shown = suggested.map((p) => p.user.uid).toSet();
        setState(() {
          _friends = results[0] as List<PersonResult>;
          _suggested = suggested;
          _nearbyOn = on;
          _nearby = nearby.where((p) => !shown.contains(p.user.uid)).toList();
          _isLoadingPeople = false;
        });
      }
    } catch (e) {
      print('Error loading people: $e');
      if (mounted && id == _requestId) setState(() => _isLoadingPeople = false);
    }
  }

  List<ContactData> _sortContacts(List<ContactData> contacts) {
    final sorted = List<ContactData>.from(contacts);
    sorted.sort((a, b) => (a.displayName?.toLowerCase() ?? '')
        .compareTo(b.displayName?.toLowerCase() ?? ''));
    return sorted;
  }

  String _subtitle(PersonResult p) {
    if (p.isFriend) return 'Friend';
    final known = p.knownByLabel;
    if (known != null) return known;
    if (p.nearby) return 'Near you';
    if (p.isVerified) return 'Verified';
    return 'Kaidose User';
  }

  Future<void> _turnOnNearby() async {
    if (_turningOnNearby) return;
    setState(() => _turningOnNearby = true);
    String? problem;
    try {
      // Belt and braces: never more than this, whatever the phone does.
      problem = await NearbyService.turnOn().timeout(
        const Duration(seconds: 75),
        onTimeout: () =>
        "That took too long. Check that Location is on and try again.",
      );
    } catch (e) {
      problem = "Couldn't turn on Near you. Try again.";
    } finally {
      // Whatever happened, the spinner goes away.
      if (mounted) setState(() => _turningOnNearby = false);
    }
    if (!mounted) return;
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(problem),
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    // On: flip the section right away, then fill in who's nearby.
    setState(() {
      _nearbyOn = true;
      _nearby = [];
    });
    _loadPeople();
  }

  Future<void> _turnOffNearby() async {
    await NearbyService.turnOff();
    if (!mounted) return;
    setState(() {
      _nearbyOn = false;
      _nearby = [];
    });
  }

  /// Off: an invite to turn it on (explains exactly what's shared).
  /// On: a header with a quiet "Turn off".
  Widget _nearbySection() {
    if (_nearbyOn == null) return const SizedBox.shrink();
    if (_nearbyOn == false) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kc.adapt(const Color(0xFFF7F8FA)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kc.adapt(const Color(0xFFE8EAED))),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kc.adapt(const Color(0xFFEDEFF2)),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.near_me_outlined, color: kc.adapt(const Color(0xFF2E2E2E))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Find people near you',
                      style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'Only your general area (about a city) is shared, and only '
                        'with people who turn this on too.',
                    style: TextStyle(fontSize: 12.5, color: kc.grey(700)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _turningOnNearby
                ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: kc.adapt(const Color(0xFFB0B5BC))))
                : TextButton(
              onPressed: _turnOnNearby,
              style: TextButton.styleFrom(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text('Turn on',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: _header(Icons.near_me_outlined, kc.grey(700), 'Near You')),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton(
                onPressed: _turnOffNearby,
                child: Text('Turn off',
                    style: TextStyle(color: kc.grey(600), fontSize: 13)),
              ),
            ),
          ],
        ),
        if (_nearby.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 24),
            child: Text(
              "No one nearby has turned this on yet. Check back later.",
              style: TextStyle(fontSize: 13.5, color: kc.grey(600)),
            ),
          )
        else ...[
          ..._nearby.map(_buildKaidoseUserCard),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _header(IconData icon, Color color, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12, left: 4),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kc.grey(800))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildEmbedded();

    if (_isLoadingPeople && _isLoadingContacts) {
      return Center(child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))));
    }

    final q = widget.searchQuery.trim().toLowerCase();
    final contacts = _typed
        ? _contacts
        .where((c) => (c.displayName ?? '').toLowerCase().contains(q))
        .toList()
        : _contacts;

    final people = _typed ? _results : const <PersonResult>[];
    final nothing = _typed
        ? people.isEmpty && contacts.isEmpty
        : _friends.isEmpty &&
        _suggested.isEmpty &&
        _nearby.isEmpty &&
        _nearbyOn != false &&
        contacts.isEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_typed && people.isNotEmpty) ...[
          _header(Icons.people, kc.grey(700), 'People'),
          ...people.map(_buildKaidoseUserCard),
          const SizedBox(height: 24),
        ],
        if (!_typed && _suggested.isNotEmpty) ...[
          _header(Icons.person_add_alt_1, kc.grey(700), 'People You May Know'),
          ..._suggested.map(_buildKaidoseUserCard),
          const SizedBox(height: 24),
        ],
        if (!_typed) _nearbySection(),
        if (!_typed && _friends.isNotEmpty) ...[
          _header(Icons.people, kc.grey(700), 'Your Friends'),
          ..._friends.map(_buildKaidoseUserCard),
          const SizedBox(height: 24),
        ],
        if (contacts.isNotEmpty) ...[
          _header(Icons.contacts, kc.grey(600), 'Phone Contacts'),
          ...contacts.map(_buildContactCard),
        ],
        if (nothing && !_isLoadingPeople)
          Center(
            child: Column(
              children: [
                const SizedBox(height: 80),
                Icon(Icons.people_outline, size: 80, color: kc.grey(400)),
                const SizedBox(height: 16),
                Text(_typed ? 'No People Found' : 'Find your people',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: kc.grey(700))),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    _typed
                        ? 'Try a different name'
                        : 'Search a username to link up with friends',
                    style: TextStyle(fontSize: 14, color: kc.grey(600)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmbedded() {
    if (_isLoadingPeople) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC)), strokeWidth: 2)),
      );
    }
    final all = _typed ? _results : _suggested;
    if (all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(_typed ? 'No people match' : 'No suggestions yet',
            style: TextStyle(fontSize: 14, color: kc.grey(500))),
      );
    }
    final shown = all.take(widget.limit).toList();
    return Column(
      children: [
        ...shown.map(_buildKaidoseUserCard),
        if (widget.onSeeAll != null && all.length > shown.length)
          TextButton(
            onPressed: widget.onSeeAll,
            child: Text('See all ${all.length} people',
                style: const TextStyle(
                    color: Colors.cyan, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _buildKaidoseUserCard(PersonResult person) {
    final user = person.user;
    final isFriend = person.isFriend || LinkedFriends.isLinkedByUserId(user.uid);
    final isPending = !isFriend && LinkedFriends.isPendingByUserId(user.uid);

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
          color: kc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.cyan.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Profile picture
            MemberAvatar(userId: user.uid, size: 50),
            const SizedBox(width: 12),
            // Username
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.username,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: kc.text,
                          ),
                        ),
                      ),
                      if (person.isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 16, color: Colors.cyan),
                      ],
                    ],
                  ),
                  Text(
                    _subtitle(person),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: kc.grey(600),
                    ),
                  ),
                ],
              ),
            ),
            // Link button or status
            if (isFriend)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kc.grey(200),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Friends',
                    style: TextStyle(
                        color: kc.grey(700),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
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
                      SearchService.invalidate();

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
          color: kc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: kc.grey(300),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: kc.grey(300),
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
                          color: kc.grey(600),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -6,
                      child: Container(
                        width: 44,
                        height: 26,
                        decoration: BoxDecoration(
                          color: kc.grey(600),
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: kc.text,
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

// Contact Profile Screen (for phone contacts)
class ContactProfileScreen extends StatelessWidget {
  final String contactName;

  const ContactProfileScreen({Key? key, required this.contactName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kc.background,
      appBar: AppBar(
        backgroundColor: kc.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: kc.text, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Text(
          "$contactName's database",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: kc.text,
          ),
        ),
      ),
    );
  }
}