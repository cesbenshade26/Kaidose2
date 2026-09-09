import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'friend_request_service.dart';
import 'message_service.dart';
import 'user_service.dart';
import 'SendToDailySelector.dart';
import 'NativeShareBar.dart';

/// Opens the generic Share sheet — a bottom sheet matching the same
/// look/behavior as ClipCommentSheet (rounded white card sliding up from
/// the bottom, drag-to-dismiss) with a horizontally scrollable row of the
/// user's friends near the top. Call this from anywhere a "share" action
/// is needed. Pass [clipId] so tapping a friend actually sends that clip
/// into their chat, and "Send to Daily" actually sends it to whichever
/// Dailies get checked; omit it to fall back to a plain friend picker
/// (pass [onFriendSelected] yourself for custom behavior in that case).
Future<void> showShareSheet(
    BuildContext context, {
      void Function(String friendUserId, String friendUsername)? onFriendSelected,
      String? clipId,
    }) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ShareSheet(
      onClose: () => Navigator.pop(context),
      onFriendSelected: onFriendSelected,
      clipId: clipId,
    ),
  );
}

/// Generic share bottom sheet content. When [clipId] is provided, tapping a
/// friend sends that clip straight into the friend's chat via
/// MessageService — no confirmation step — and "Send to Daily" sends it to
/// whichever Dailies get checked. When [clipId] is omitted, the sheet is
/// purely a friend picker: [onFriendSelected] fires on tap and nothing is
/// sent, so this stays reusable for non-clip sharing later.
class ShareSheet extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(String friendUserId, String friendUsername)? onFriendSelected;
  final String? clipId;

  const ShareSheet({
    Key? key,
    required this.onClose,
    this.onFriendSelected,
    this.clipId,
  }) : super(key: key);

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final MessageService _messageService = MessageService();
  final UserService _userService = UserService();
  bool _isSending = false;

  Future<void> _handleFriendTap(String friendUserId, String friendUsername) async {
    // Caller wants custom behavior instead of the default send — defer to it.
    if (widget.onFriendSelected != null) {
      widget.onFriendSelected!(friendUserId, friendUsername);
      return;
    }

    if (widget.clipId == null || _isSending) return;

    setState(() => _isSending = true);

    try {
      final clipDoc = await FirebaseFirestore.instance
          .collection('clips')
          .doc(widget.clipId)
          .get();

      if (!clipDoc.exists) {
        throw Exception('Clip not found');
      }

      final data = clipDoc.data()!;
      final videoUrl = data['videoUrl'] as String? ?? '';
      final caption = data['caption'] as String? ?? '';

      if (videoUrl.isEmpty) {
        throw Exception('Clip has no video URL');
      }

      String username = 'You';
      final currentUid = _messageService.currentUserId;
      if (currentUid != null) {
        final user = await _userService.getUserById(currentUid);
        if (user?.username != null && user!.username.isNotEmpty) {
          username = user.username;
        }
      }

      final success = await _messageService.sendChatMessage(
        recipientUserId: friendUserId,
        text: caption.isNotEmpty ? caption : 'Sent a clip',
        senderUsername: username,
        metadata: {
          'type': 'clip',
          'clipId': widget.clipId,
          'videoUrl': videoUrl,
        },
      );

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        widget.onClose();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Sent to $friendUsername!' : 'Error sending clip',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('ShareSheet: send to friend error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending clip: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Share',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onClose,
                    child: Icon(Icons.close, color: Colors.grey[600], size: 22),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEEEEEE)),

            const SizedBox(height: 16),

            FriendSelectorBar(
              onFriendTap: _handleFriendTap,
              leadingLabel: 'Send to Daily',
              leadingIcon: Icons.circle_outlined, // filler icon for now
              onLeadingTap: () => showSendToDailySheet(context, clipId: widget.clipId),
            ),

            if (_isSending) ...[
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: LinearProgressIndicator(color: Colors.cyan),
              ),
            ],

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Share via',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),

            NativeShareBar(clipId: widget.clipId),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Reusable horizontally-scrollable row of the current user's friends,
/// each shown as a bubble avatar + name — same visual language as the
/// friend rows in Chat.dart. Not tied to sharing specifically; usable
/// anywhere a quick friend picker is needed.
///
/// Optionally takes a "leading" action bubble ([leadingLabel]/[leadingIcon]/
/// [onLeadingTap]) that renders first, before any friends, in the same
/// scrollable row — it scrolls away with the rest of the row rather than
/// staying pinned. Leave those null for a plain friend list.
class FriendSelectorBar extends StatefulWidget {
  final void Function(String friendUserId, String friendUsername)? onFriendTap;
  final String? leadingLabel;
  final IconData? leadingIcon;
  final VoidCallback? onLeadingTap;

  const FriendSelectorBar({
    Key? key,
    this.onFriendTap,
    this.leadingLabel,
    this.leadingIcon,
    this.onLeadingTap,
  }) : super(key: key);

  @override
  State<FriendSelectorBar> createState() => _FriendSelectorBarState();
}

class _FriendSelectorBarState extends State<FriendSelectorBar> {
  final FriendRequestService _friendRequestService = FriendRequestService();

  bool get _hasLeading =>
      widget.leadingLabel != null &&
          widget.leadingIcon != null &&
          widget.onLeadingTap != null;

  Widget _buildLeadingBubble() {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        onTap: widget.onLeadingTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.cyan, width: 1.5),
              ),
              child: Icon(widget.leadingIcon, color: Colors.cyan[700], size: 26),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 64,
              child: Text(
                widget.leadingLabel!,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendBubble(FriendRequest f, String? currentUid) {
    final isCurrentUserSender = f.fromUserId == currentUid;
    final friendName = isCurrentUserSender ? f.toUsername : f.fromUsername;
    final friendUserId = isCurrentUserSender ? f.toUserId : f.fromUserId;

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        onTap: widget.onFriendTap != null
            ? () => widget.onFriendTap!(friendUserId, friendName)
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 13,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.cyan[700],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -7,
                      child: Container(
                        width: 49,
                        height: 29,
                        decoration: BoxDecoration(
                          color: Colors.cyan[700],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(25),
                            topRight: Radius.circular(25),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 64,
              child: Text(
                friendName,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: StreamBuilder<List<FriendRequest>>(
        stream: _friendRequestService.getAcceptedFriends(),
        builder: (context, snapshot) {
          final bool isLoading =
              snapshot.connectionState == ConnectionState.waiting;
          final friends = snapshot.data ?? [];
          final currentUid = _friendRequestService.currentUserId;
          final hasLeading = _hasLeading;

          if (!hasLeading && !isLoading && friends.isEmpty) {
            return Center(
              child: Text(
                'No friends yet',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
            );
          }

          final itemCount =
              (hasLeading ? 1 : 0) + (isLoading ? 1 : friends.length);

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (hasLeading && index == 0) {
                return _buildLeadingBubble();
              }

              final friendIndex = index - (hasLeading ? 1 : 0);

              if (isLoading) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.cyan),
                  ),
                );
              }

              return _buildFriendBubble(friends[friendIndex], currentUid);
            },
          );
        },
      ),
    );
  }
}