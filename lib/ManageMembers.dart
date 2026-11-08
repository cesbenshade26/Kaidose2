import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'DailyData.dart';
import 'user_service.dart';
import 'UserProfileScreen.dart';

/// One resolved person for display — owner, active member, or pending
/// invite, depending on which list they end up in.
class _MemberEntry {
  final String uid;
  final String username;
  final bool isOwner;

  _MemberEntry({required this.uid, required this.username, this.isOwner = false});
}

/// Members tab for Manage Daily — three sections: active Members (owner
/// always first), pending Invited Friends, and Bans. Replaces the old
/// management-tier drag-and-drop system, which stays shelved for a later,
/// simpler pass rather than being part of this restructure.
class ManageMembers extends StatefulWidget {
  final DailyData daily;

  const ManageMembers({Key? key, required this.daily}) : super(key: key);

  @override
  State<ManageMembers> createState() => _ManageMembersState();
}

class _ManageMembersState extends State<ManageMembers> {
  final UserService _userService = UserService();
  final ScrollController _scrollController = ScrollController();

  // Jump-scroll anchors — Scrollable.ensureVisible on these is more
  // robust than calculating pixel offsets by hand, since it keeps
  // working correctly no matter how tall any section's content is.
  final GlobalKey _topKey = GlobalKey();
  final GlobalKey _invitedKey = GlobalKey();
  final GlobalKey _bansKey = GlobalKey();

  Color get _dailyColor => Color(widget.daily.iconColor ?? 0xFF00BCD4);

  bool _isLoading = true;
  List<_MemberEntry> _members = [];
  List<_MemberEntry> _pendingInvites = [];

  // Bans has nothing behind it yet — kept as an empty list on purpose,
  // per "just make the category with nothing in it for now."
  final List<_MemberEntry> _bannedMembers = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);

    final members = <_MemberEntry>[];
    final pending = <_MemberEntry>[];

    // Owner always goes first, regardless of the invitation system below.
    final ownerUid = widget.daily.creatorUid;
    final seenUids = <String>{};
    if (ownerUid != null) {
      final ownerUser = await _userService.getUserById(ownerUid);
      members.add(_MemberEntry(
        uid: ownerUid,
        username: ownerUser?.username ?? 'Unknown',
        isOwner: true,
      ));
      seenUids.add(ownerUid);
    }

    // Everyone else is driven by this Daily's actual invitation records:
    // 'accepted' -> real member, 'pending' -> still waiting on a
    // response, 'rejected' -> that person said no and shouldn't show up
    // anywhere here. The old version showed every invited friend as
    // "Pending" unconditionally, never actually checking status at all.
    try {
      final invites = await FirebaseFirestore.instance
          .collection('daily_invitations')
          .where('dailyId', isEqualTo: widget.daily.id)
          .get();

      for (final doc in invites.docs) {
        final data = doc.data();
        final uid = data['toUserId'] as String?;
        final status = data['status'] as String?;

        if (uid == null || status == 'rejected') continue;
        // Guards against duplicate invitation docs for the same person
        // (e.g. a rejected one and a newer pending one both existing).
        if (seenUids.contains(uid)) continue;
        seenUids.add(uid);

        // Read straight off the invitation doc — it already stores the
        // username from when the invite was sent, so there's no need
        // for a separate UserService lookup per member here. Only
        // downside: it won't reflect a username changed since then,
        // unlike the owner's lookup below which is always current.
        final username = data['toUsername'] as String? ?? 'Unknown';
        final entry = _MemberEntry(uid: uid, username: username);

        if (status == 'accepted') {
          members.add(entry);
        } else if (status == 'pending') {
          pending.add(entry);
        }
      }
    } catch (e) {
      print('ManageMembers: error loading invitations: $e');
    }

    if (mounted) {
      setState(() {
        _members = members;
        _pendingInvites = pending;
        _isLoading = false;
      });
    }
  }

  bool _isRefreshingNames = false;

  /// toUsername on an invitation doc is a snapshot from invite time, so it
  /// can go stale if someone renames themselves afterward. Re-fetching
  /// current usernames costs one Firestore read per person every single
  /// time, so that cost is made opt-in here (only on this explicit tap)
  /// rather than paid automatically on every normal load above.
  Future<void> _refreshUsernames() async {
    if (_isRefreshingNames) return;
    setState(() => _isRefreshingNames = true);

    try {
      final updatedMembers = <_MemberEntry>[];
      for (final m in _members) {
        final user = await _userService.getUserById(m.uid);
        updatedMembers.add(_MemberEntry(
          uid: m.uid,
          username: user?.username ?? m.username,
          isOwner: m.isOwner,
        ));
      }

      final updatedPending = <_MemberEntry>[];
      for (final m in _pendingInvites) {
        final user = await _userService.getUserById(m.uid);
        updatedPending.add(_MemberEntry(uid: m.uid, username: user?.username ?? m.username));
      }

      if (mounted) {
        setState(() {
          _members = updatedMembers;
          _pendingInvites = updatedPending;
        });
      }
    } catch (e) {
      print('ManageMembers: error refreshing usernames: $e');
    } finally {
      if (mounted) setState(() => _isRefreshingNames = false);
    }
  }

  void _scrollTo(GlobalKey key) {
    final sectionContext = key.currentContext;
    if (sectionContext != null) {
      Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick-jump row — skips a long Members list straight to
          // whichever section you actually want.
          Row(
            key: _topKey,
            children: [
              Expanded(
                child: _quickNavChip(
                  'Invited Friends',
                  Icons.arrow_downward,
                      () => _scrollTo(_invitedKey),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _quickNavChip(
                  'Bans',
                  Icons.arrow_downward,
                      () => _scrollTo(_bansKey),
                ),
              ),
              const SizedBox(width: 8),
              // Names below are a snapshot from invite time and can go
              // stale if someone renames themselves — this is the only
              // place that pays for a current-username lookup, and only
              // when actually tapped.
              GestureDetector(
                onTap: _isRefreshingNames ? null : _refreshUsernames,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: _isRefreshingNames
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Icon(Icons.refresh, size: 18, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          _sectionHeader(Icons.people, 'Members', _members.length),
          const SizedBox(height: 12),
          _members.isEmpty
              ? _emptyState(Icons.people_outline, 'No members yet')
              : Column(children: _members.map((m) => _memberCard(m)).toList()),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),

          Row(
            key: _invitedKey,
            children: [
              Expanded(
                child: _sectionHeader(
                    Icons.schedule, 'Invited Friends', _pendingInvites.length),
              ),
              _backToTopButton(),
            ],
          ),
          const SizedBox(height: 12),
          _pendingInvites.isEmpty
              ? _emptyState(Icons.person_add_outlined, 'No pending invites')
              : Column(
            children:
            _pendingInvites.map((m) => _memberCard(m, pending: true)).toList(),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),

          Row(
            key: _bansKey,
            children: [
              Expanded(child: _sectionHeader(Icons.block, 'Bans', _bannedMembers.length)),
              _backToTopButton(),
            ],
          ),
          const SizedBox(height: 12),
          _bannedMembers.isEmpty
              ? _emptyState(Icons.block_flipped, 'No banned members')
              : Column(children: _bannedMembers.map((m) => _memberCard(m)).toList()),
        ],
      ),
    );
  }

  Widget _quickNavChip(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: _dailyColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _dailyColor.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: _dailyColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _dailyColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _backToTopButton() {
    return GestureDetector(
      onTap: () => _scrollTo(_topKey),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.arrow_upward, size: 18, color: Colors.grey[700]),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title, int count) {
    return Row(
      children: [
        Icon(icon, color: _dailyColor, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 8),
        Text('($count)', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      ],
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberCard(_MemberEntry member, {bool pending = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => UserProfileScreen.open(context, member.uid,
          username: member.username),
      child: _memberCardBody(member, pending: pending),
    );
  }

  Widget _memberCardBody(_MemberEntry member, {bool pending = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: member.isOwner ? _dailyColor.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: member.isOwner ? _dailyColor.withOpacity(0.4) : Colors.grey[300]!,
          width: member.isOwner ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: Colors.grey[300], shape: BoxShape.circle),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.username,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                if (member.isOwner)
                  _badge('Owner', _dailyColor)
                else if (pending)
                  _badge('Pending', Colors.orange[700]!),
              ],
            ),
          ),
          if (!member.isOwner)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                if (value == 'ban') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Banning isn\'t set up yet'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'ban',
                  child: Row(
                    children: [
                      Icon(Icons.block, size: 20, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Ban', style: TextStyle(fontSize: 16, color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}