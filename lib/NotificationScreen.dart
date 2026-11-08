import 'dart:async';
import 'package:flutter/material.dart';
import 'friend_request_service.dart';
import 'daily_invitation_service.dart';
import 'daily_join_request_service.dart';
import 'LinkedFriends.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'daily_service.dart';
import 'KaidoseBrand.dart';
import 'UserProfileScreen.dart';

/// One screen for everything. At the top, "Requests": things waiting on an
/// answer from you (friend requests, Daily invitations, requests to join your
/// Dailies), newest first, with Accept / Decline. Below, "Activity": things
/// that already happened (people accepting your invites).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Requests shown before "Show more".
  static const int _collapsedCount = 4;

  final FriendRequestService _friendRequestService = FriendRequestService();
  final DailyInvitationService _invitationService = DailyInvitationService();
  final DailyJoinRequestService _joinRequestService =
  DailyJoinRequestService();

  final List<StreamSubscription> _subs = [];

  List<FriendRequest> _friendRequests = [];
  List<DailyInvitation> _invitations = [];
  List<DailyJoinRequest> _joinRequests = [];
  List<DailyInvitation> _accepted = [];

  // Which of the four lists have answered (with data or an error) at least
  // once, and which failed.
  final Set<String> _loaded = {};
  final Set<String> _failed = {};

  bool _showAllRequests = false;

  /// Ids of requests being answered right now, so a double tap can't answer
  /// the same one twice.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _listen<FriendRequest>('friends',
        _friendRequestService.getIncomingRequests(), (v) => _friendRequests = v);
    _listen<DailyInvitation>('invites',
        _invitationService.getPendingInvitations(), (v) => _invitations = v);
    _listen<DailyJoinRequest>('joins',
        _joinRequestService.getPendingJoinRequests(), (v) => _joinRequests = v);
    _listen<DailyInvitation>('accepted',
        _invitationService.getAcceptedInvitations(), (v) => _accepted = v);
  }

  void _listen<T>(String key, Stream<List<T>> stream, void Function(List<T>) set) {
    _subs.add(stream.listen(
          (items) {
        if (!mounted) return;
        setState(() {
          set(items);
          _loaded.add(key);
          _failed.remove(key);
        });
      },
      onError: (e) {
        print('NotificationsScreen: "$key" stream error: $e');
        if (!mounted) return;
        setState(() {
          _loaded.add(key);
          _failed.add(key);
        });
      },
    ));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // ─── Screen ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 26),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Notifications', style: KaidoseBrand.wordmark(26)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loaded.length < 4) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }
    if (_failed.length == 4) {
      return _emptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Couldn\'t load notifications',
        subtitle: 'Check your connection and try again in a moment.',
      );
    }

    // Everything waiting on me, newest first.
    final requests = <_Request>[
      for (final r in _friendRequests)
        _Request(r.createdAt, () => _buildIncomingRequestCard(r)),
      for (final r in _invitations)
        _Request(r.timestamp, () => _buildDailyInvitationCard(r)),
      for (final r in _joinRequests)
        _Request(r.timestamp, () => _buildJoinRequestCard(r)),
    ]..sort((a, b) => b.time.compareTo(a.time));

    if (requests.isEmpty && _accepted.isEmpty) {
      return _emptyState(
        icon: Icons.notifications_none_rounded,
        title: 'You\'re all caught up',
        subtitle:
        'Friend requests, Daily invites and updates will show up here.',
      );
    }

    final hidden = requests.length - _collapsedCount;
    final visible = (_showAllRequests || hidden <= 0)
        ? requests
        : requests.take(_collapsedCount).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (requests.isNotEmpty) ...[
          _sectionHeader('Requests', count: requests.length),
          ...visible.map((r) => r.build()),
          if (hidden > 0)
            Center(
              child: TextButton(
                onPressed: () =>
                    setState(() => _showAllRequests = !_showAllRequests),
                child: Text(
                  _showAllRequests ? 'Show less' : 'Show $hidden more',
                  style: const TextStyle(
                      color: Colors.cyan, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (_accepted.isNotEmpty) ...[
          _sectionHeader('Activity'),
          ..._accepted.map(_buildAcceptedDailyInvitationCard),
        ],
      ],
    );
  }

  Widget _sectionHeader(String text, {int? count}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 12),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.grey[900],
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.cyan[800],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: Colors.grey[400]),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Cards ──────────────────────────────────────────────────────────────────

  String _timeAgo(DateTime time) {
    final d = DateTime.now().difference(time);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }

  /// Every notification looks the same: a leading icon, one sentence with the
  /// person and Daily in bold, how long ago, and (for things you can answer)
  /// Accept / Decline buttons.
  Widget _card({
    required Widget leading,
    String? profileUserId,
    required String name,
    required String action,
    String? bold,
    required DateTime time,
    String? busyId,
    String? acceptLabel,
    VoidCallback? onAccept,
    String? declineLabel,
    VoidCallback? onDecline,
    bool highlighted = false,
  }) {
    final busy = busyId != null && _busy.contains(busyId);
    final hasActions = onAccept != null && onDecline != null;
    // Tapping the avatar opens that person's profile.
    if (profileUserId != null && profileUserId.isNotEmpty) {
      final original = leading;
      leading = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            UserProfileScreen.open(context, profileUserId, username: name),
        child: original,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? Colors.cyan.withOpacity(0.4) : Colors.grey[300]!,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontSize: 15, color: Colors.black87, height: 1.3),
                        children: [
                          TextSpan(
                            text: name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' $action'),
                          if (bold != null)
                            TextSpan(
                              text: ' "$bold"',
                              style:
                              const TextStyle(fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _timeAgo(time),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasActions) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton(
                      onPressed: busy ? null : onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.cyan.withOpacity(0.5),
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: busy
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                          : Text(acceptLabel ?? 'Accept',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton(
                      onPressed: busy ? null : onDecline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[800],
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(declineLabel ?? 'Decline',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconBubble(IconData icon) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.cyan[700], size: 24),
    );
  }

  Widget _buildIncomingRequestCard(FriendRequest request) {
    return _card(
      leading: _avatarBubble(),
      profileUserId: request.fromUserId,
      name: request.fromUsername,
      action: 'wants to link with you',
      time: request.createdAt,
      highlighted: true,
      busyId: request.id,
      onAccept: () => _acceptFriendRequest(request),
      onDecline: () => _rejectFriendRequest(request),
    );
  }

  Widget _buildDailyInvitationCard(DailyInvitation invitation) {
    return _card(
      leading: _iconBubble(Icons.event_outlined),
      profileUserId: invitation.fromUserId,
      name: invitation.fromUsername,
      action: 'invited you to',
      bold: invitation.dailyTitle,
      time: invitation.timestamp,
      highlighted: true,
      busyId: invitation.id,
      onAccept: () => _acceptDailyInvitation(invitation),
      onDecline: () => _rejectDailyInvitation(invitation),
    );
  }

  Widget _buildJoinRequestCard(DailyJoinRequest request) {
    return _card(
      leading: _iconBubble(Icons.lock_person_outlined),
      profileUserId: request.fromUserId,
      name: request.fromUsername,
      action: 'requested to join',
      bold: request.dailyTitle,
      time: request.timestamp,
      highlighted: true,
      busyId: request.id,
      onAccept: () => _acceptJoinRequest(request),
      declineLabel: 'Deny',
      onDecline: () => _rejectJoinRequest(request),
    );
  }

  Widget _buildAcceptedDailyInvitationCard(DailyInvitation invitation) {
    return _card(
      leading: _iconBubble(Icons.check_rounded),
      profileUserId: invitation.toUserId,
      name: invitation.toUsername,
      action: 'accepted your invite to',
      bold: invitation.dailyTitle,
      time: invitation.timestamp,
    );
  }

  /// Person-shaped placeholder avatar, in the same style as Chat and Search.
  Widget _avatarBubble() {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 11,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.cyan[700]),
              ),
            ),
            Positioned(
              bottom: -6,
              child: Container(
                width: 40,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.cyan[700],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
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

  void _toast(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Runs [action] with the buttons on card [id] disabled until it finishes.
  Future<void> _guard(String id, Future<void> Function() action) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _acceptFriendRequest(FriendRequest request) => _guard(
    request.id,
        () async {
      final result =
      await _friendRequestService.acceptFriendRequest(request.id);

      if (result['success']) {
        await LinkedFriends.linkFriend(
          request.fromUsername,
          userId: request.fromUserId,
        );
        await LinkedFriends.acceptLinkRequest(request.fromUsername);
        _toast('You are now friends with ${request.fromUsername}!',
            color: Colors.green);
      } else {
        _toast('Something went wrong: ${result['error']}',
            color: Colors.red);
      }
    },
  );

  Future<void> _rejectFriendRequest(FriendRequest request) => _guard(
    request.id,
        () async {
      final result =
      await _friendRequestService.rejectFriendRequest(request.id);
      if (result['success']) {
        _toast('Request from ${request.fromUsername} declined');
      } else {
        _toast('Something went wrong: ${result['error']}',
            color: Colors.red);
      }
    },
  );

  Future<void> _acceptDailyInvitation(DailyInvitation invitation) => _guard(
    invitation.id,
        () async {
      final result =
      await _invitationService.acceptDailyInvitation(invitation.id);

      if (result['success']) {
        try {
          final dailyService = DailyService();

          final ownerDaily = await dailyService.getDailyFromUser(
            userId: invitation.fromUserId,
            dailyId: invitation.dailyId,
          );

          if (ownerDaily != null) {
            await DailyList.addDaily(ownerDaily);
            _toast('Joined "${invitation.dailyTitle}"!',
                color: Colors.green);
          } else {
            final newDaily = DailyData(
              id: invitation.dailyId,
              title: invitation.dailyTitle,
              description:
              'Daily shared with you by ${invitation.fromUsername}',
              privacy: 'friends',
              keywords: [],
              managementTiers: [],
              icon: Icons.event,
              invitedFriendIds: [],
              createdAt: DateTime.now(),
              dailyEntryPrompt: '',
            );

            await DailyList.addDaily(newDaily);
            _toast('Joined "${invitation.dailyTitle}" (limited sync)',
                color: Colors.orange);
          }
        } catch (e) {
          print('ERROR in _acceptDailyInvitation: $e');
          _toast('Couldn\'t sync that Daily: $e', color: Colors.red);
        }
      } else {
        _toast('Something went wrong: ${result['error']}',
            color: Colors.red);
      }
    },
  );

  Future<void> _rejectDailyInvitation(DailyInvitation invitation) => _guard(
    invitation.id,
        () async {
      final result =
      await _invitationService.rejectDailyInvitation(invitation.id);
      if (result['success']) {
        _toast('Declined invitation to "${invitation.dailyTitle}"');
      } else {
        _toast('Something went wrong: ${result['error']}',
            color: Colors.red);
      }
    },
  );

  /// Accept a request to join one of MY private Dailies.
  /// Copies my Daily into the requester's account, same pattern as
  /// daily_invitation_service.acceptDailyInvitation.
  Future<void> _acceptJoinRequest(DailyJoinRequest request) => _guard(
    request.id,
        () async {
      final result =
      await _joinRequestService.acceptJoinRequest(request.id);

      if (result['success']) {
        try {
          final dailyService = DailyService();

          // toUserId on the request is ME (the owner) since I'm the one
          // viewing this in my notifications
          final myDaily = await dailyService.getDailyById(request.dailyId);

          if (myDaily != null) {
            await _copyDailyToUser(myDaily, request.fromUserId);
            _toast(
                '${request.fromUsername} can now access "${request.dailyTitle}"!',
                color: Colors.green);
          }
        } catch (e) {
          print('ERROR in _acceptJoinRequest: $e');
          _toast('Couldn\'t grant access: $e', color: Colors.red);
        }
      } else {
        _toast('Something went wrong: ${result['error']}',
            color: Colors.red);
      }
    },
  );

  /// Helper: copies a Daily I own into another user's `dailies`
  /// subcollection, marking it correctly with my UID as creator.
  Future<void> _copyDailyToUser(DailyData daily, String targetUid) async {
    await DailyService.copyDailyToUser(
      daily: daily,
      targetUid: targetUid,
    );
  }

  Future<void> _rejectJoinRequest(DailyJoinRequest request) => _guard(
    request.id,
        () async {
      final result =
      await _joinRequestService.rejectJoinRequest(request.id);
      if (result['success']) {
        _toast(
            'Denied ${request.fromUsername}\'s request to join "${request.dailyTitle}"');
      } else {
        _toast('Something went wrong: ${result['error']}',
            color: Colors.red);
      }
    },
  );
}

/// A pending request plus the time it came in, so friend requests, invites and
/// join requests can be mixed into one newest-first list.
class _Request {
  final DateTime time;
  final Widget Function() build;
  _Request(this.time, this.build);
}