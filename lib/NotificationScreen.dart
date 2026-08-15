import 'package:flutter/material.dart';
import 'friend_request_service.dart';
import 'daily_invitation_service.dart';
import 'daily_join_request_service.dart';
import 'LinkedFriends.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'daily_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FriendRequestService _friendRequestService = FriendRequestService();
  final DailyInvitationService _invitationService = DailyInvitationService();
  final DailyJoinRequestService _joinRequestService =
  DailyJoinRequestService();

  int _selectedTab = 0; // 0 = friends, 1 = dailies, 2 = accepted
  int _dailySubTab = 0; // 0 = invitations, 1 = join requests

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
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontFamily: 'Slackey',
            fontSize: 24,
            color: Colors.cyan,
          ),
        ),
      ),
      body: Column(
        children: [
          // Top-level tab selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _topTab(0, 'Friends'),
                _topTab(1, 'Dailies'),
                _topTab(2, 'Accepted'),
              ],
            ),
          ),

          // Sub-tab selector — only visible on the Dailies tab
          if (_selectedTab == 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _subTabChip(0, 'Invitations'),
                  const SizedBox(width: 8),
                  _subTabChip(1, 'Join Requests'),
                ],
              ),
            ),

          const SizedBox(height: 4),

          Expanded(
            child: _selectedTab == 0
                ? _buildIncomingFriendRequests()
                : _selectedTab == 1
                ? (_dailySubTab == 0
                ? _buildPendingDailyInvitations()
                : _buildPendingJoinRequests())
                : _buildAcceptedRequests(),
          ),
        ],
      ),
    );
  }

  Widget _topTab(int index, String label) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: _selectedTab == index
                    ? Colors.cyan
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _selectedTab == index ? Colors.cyan : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _subTabChip(int index, String label) {
    final active = _dailySubTab == index;
    return GestureDetector(
      onTap: () => setState(() => _dailySubTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.purple.withOpacity(0.12) : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? Colors.purple : Colors.grey[300]!,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.purple : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  // ─── Friend requests ────────────────────────────────────────────────────────

  Widget _buildIncomingFriendRequests() {
    return StreamBuilder<List<FriendRequest>>(
      stream: _friendRequestService.getIncomingRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return _emptyState(
            icon: Icons.notifications_none,
            title: 'No Friend Requests',
            subtitle: 'You are all caught up!',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) =>
              _buildIncomingRequestCard(requests[index]),
        );
      },
    );
  }

  // ─── Daily invitations ──────────────────────────────────────────────────────

  Widget _buildPendingDailyInvitations() {
    return StreamBuilder<List<DailyInvitation>>(
      stream: _invitationService.getPendingInvitations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final invitations = snapshot.data ?? [];

        if (invitations.isEmpty) {
          return _emptyState(
            icon: Icons.event_available,
            title: 'No Daily Invitations',
            subtitle: 'You are all caught up!',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: invitations.length,
          itemBuilder: (context, index) =>
              _buildDailyInvitationCard(invitations[index]),
        );
      },
    );
  }

  // ─── Join requests (private Dailies) ───────────────────────────────────────

  Widget _buildPendingJoinRequests() {
    return StreamBuilder<List<DailyJoinRequest>>(
      stream: _joinRequestService.getPendingJoinRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return _emptyState(
            icon: Icons.lock_person_outlined,
            title: 'No Join Requests',
            subtitle: 'Requests to join your private Dailies show up here',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) =>
              _buildJoinRequestCard(requests[index]),
        );
      },
    );
  }

  // ─── Accepted ───────────────────────────────────────────────────────────────

  Widget _buildAcceptedRequests() {
    return StreamBuilder<List<DailyInvitation>>(
      stream: _invitationService.getAcceptedInvitations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyan),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final invitations = snapshot.data ?? [];

        if (invitations.isEmpty) {
          return _emptyState(
            icon: Icons.check_circle_outline,
            title: 'No Accepted Invitations',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: invitations.length,
          itemBuilder: (context, index) =>
              _buildAcceptedDailyInvitationCard(invitations[index]),
        );
      },
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                subtitle,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Cards ──────────────────────────────────────────────────────────────────

  Widget _buildIncomingRequestCard(FriendRequest request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyan.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatarBubble(Colors.cyan),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.fromUsername,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                    Text(
                      'wants to link with you',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptFriendRequest(request),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Accept',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectFriendRequest(request),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.red),
                    shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Reject',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailyInvitationCard(DailyInvitation invitation) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event, color: Colors.purple, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invitation.fromUsername,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87),
                    ),
                    Text(
                      'invited you to "${invitation.dailyTitle}"',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptDailyInvitation(invitation),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Accept',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectDailyInvitation(invitation),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.red),
                    shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Decline',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJoinRequestCard(DailyJoinRequest request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_person_outlined,
                    color: Colors.orange, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 15, color: Colors.black87, height: 1.3),
                    children: [
                      TextSpan(
                        text: request.fromUsername,
                        style:
                        const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' requested to join '),
                      TextSpan(
                        text: '"${request.dailyTitle}"',
                        style:
                        const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptJoinRequest(request),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Accept',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectJoinRequest(request),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.red),
                    shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Deny',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedDailyInvitationCard(DailyInvitation invitation) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, color: Colors.green, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.toUsername,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
                Text(
                  'accepted your invite to "${invitation.dailyTitle}"!',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarBubble(MaterialColor color) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
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
                decoration:
                BoxDecoration(shape: BoxShape.circle, color: color.shade700),
              ),
            ),
            Positioned(
              bottom: -6,
              child: Container(
                width: 44,
                height: 26,
                decoration: BoxDecoration(
                  color: color.shade700,
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
    );
  }

  // ─── Action handlers ────────────────────────────────────────────────────────

  Future<void> _acceptFriendRequest(FriendRequest request) async {
    final result = await _friendRequestService.acceptFriendRequest(request.id);

    if (result['success']) {
      await LinkedFriends.linkFriend(
        request.fromUsername,
        userId: request.fromUserId,
      );
      await LinkedFriends.acceptLinkRequest(request.fromUsername);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You are now friends with ${request.fromUsername}!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${result['error']}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectFriendRequest(FriendRequest request) async {
    final result = await _friendRequestService.rejectFriendRequest(request.id);

    if (result['success']) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request from ${request.fromUsername} rejected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${result['error']}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _acceptDailyInvitation(DailyInvitation invitation) async {
    final result = await _invitationService.acceptDailyInvitation(invitation.id);

    if (result['success']) {
      try {
        final dailyService = DailyService();

        final ownerDaily = await dailyService.getDailyFromUser(
          userId: invitation.fromUserId,
          dailyId: invitation.dailyId,
        );

        if (ownerDaily != null) {
          await DailyList.addDaily(ownerDaily);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Joined "${invitation.dailyTitle}"!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          final newDaily = DailyData(
            id: invitation.dailyId,
            title: invitation.dailyTitle,
            description: 'Daily shared with you by ${invitation.fromUsername}',
            privacy: 'friends',
            keywords: [],
            managementTiers: [],
            icon: Icons.event,
            invitedFriendIds: [],
            createdAt: DateTime.now(),
            dailyEntryPrompt: '',
          );

          await DailyList.addDaily(newDaily);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Joined "${invitation.dailyTitle}" (limited sync)'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } catch (e) {
        print('ERROR in _acceptDailyInvitation: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error syncing daily data: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${result['error']}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectDailyInvitation(DailyInvitation invitation) async {
    final result = await _invitationService.rejectDailyInvitation(invitation.id);

    if (result['success']) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Declined invitation to "${invitation.dailyTitle}"'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${result['error']}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Accept a request to join one of MY private Dailies.
  /// Copies my Daily into the requester's account, same pattern as
  /// daily_invitation_service.acceptDailyInvitation.
  Future<void> _acceptJoinRequest(DailyJoinRequest request) async {
    final result = await _joinRequestService.acceptJoinRequest(request.id);

    if (result['success']) {
      try {
        final dailyService = DailyService();

        // toUserId on the request is ME (the owner) since I'm the one
        // viewing this in my notifications
        final myDaily = await dailyService.getDailyById(request.dailyId);

        if (myDaily != null) {
          await _copyDailyToUser(myDaily, request.fromUserId);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '${request.fromUsername} can now access "${request.dailyTitle}"!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        print('ERROR in _acceptJoinRequest: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error granting access: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${result['error']}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Helper: copies a Daily I own into another user's `dailies`
  /// subcollection, marking it correctly with my UID as creator.
  Future<void> _copyDailyToUser(DailyData daily, String targetUid) async {
    await DailyService.copyDailyToUser(
      daily: daily,
      targetUid: targetUid,
    );
  }

  Future<void> _rejectJoinRequest(DailyJoinRequest request) async {
    final result = await _joinRequestService.rejectJoinRequest(request.id);

    if (result['success']) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
            Text('Denied ${request.fromUsername}\'s request to join "${request.dailyTitle}"'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${result['error']}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}