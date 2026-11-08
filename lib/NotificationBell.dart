import 'dart:async';
import 'package:flutter/material.dart';
import 'friend_request_service.dart';
import 'daily_invitation_service.dart';
import 'daily_join_request_service.dart';
import 'NotificationScreen.dart';

/// The notifications button: a bell that opens the Notifications screen,
/// with a red badge counting everything waiting on you — friend requests,
/// Daily invitations and requests to join your Dailies. Used on the Dailies
/// screen and the Profile screen so both always match.
class NotificationBell extends StatefulWidget {
  final double size;
  final Color color;

  /// Optional hooks so a screen can remember and restore its scroll
  /// position around the Notifications screen.
  final VoidCallback? onBeforeOpen;
  final VoidCallback? onAfterClose;

  const NotificationBell({
    Key? key,
    this.size = 28,
    this.color = Colors.black,
    this.onBeforeOpen,
    this.onAfterClose,
  }) : super(key: key);

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final List<StreamSubscription> _subs = [];
  int _friends = 0, _invites = 0, _joins = 0;

  int get _total => _friends + _invites + _joins;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      FriendRequestService().getIncomingRequestCount().listen(
              (n) => _set(() => _friends = n),
          onError: (_) {}),
      DailyInvitationService().getPendingInvitations().listen(
              (l) => _set(() => _invites = l.length),
          onError: (_) {}),
      DailyJoinRequestService().getPendingJoinRequests().listen(
              (l) => _set(() => _joins = l.length),
          onError: (_) {}),
    ]);
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _total;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(Icons.notifications_none_rounded,
              color: widget.color, size: widget.size),
          onPressed: () async {
            widget.onBeforeOpen?.call();
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
            widget.onAfterClose?.call();
          },
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}