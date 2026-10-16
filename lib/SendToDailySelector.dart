import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'MessageStorage.dart';
import 'SendDailyMessage.dart';
import 'user_service.dart';
import 'DailyVideoTracker.dart';
import 'FriendDailyService.dart';
import 'YourDailyBubbles.dart';
import 'BubbleQuickPickSheet.dart';

/// Opens the Daily picker sheet — a pinned "Your Daily" checkbox (always
/// at the top, never scrolls away) plus a checkbox list of every Daily
/// the current user is on (public and private both), styled to match the
/// colored icon-square look used for Daily cards elsewhere
/// (DailyPostActivity). Pass [clipId] so "Send" actually posts that
/// clip's video — into each checked Daily, and/or into Your Daily story
/// if that box is checked; if omitted, Send just closes the sheet (no-op).
Future<void> showSendToDailySheet(BuildContext context, {String? clipId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SendToDailySelectorSheet(clipId: clipId),
  );
}

class SendToDailySelectorSheet extends StatefulWidget {
  final String? clipId;

  const SendToDailySelectorSheet({Key? key, this.clipId}) : super(key: key);

  @override
  State<SendToDailySelectorSheet> createState() =>
      _SendToDailySelectorSheetState();
}

class _SendToDailySelectorSheetState extends State<SendToDailySelectorSheet> {
  final Set<String> _selectedDailyIds = {};
  bool _sendToYourDaily = false;
  String? _selectedBubbleIdForYourDaily;
  final UserService _userService = UserService();
  bool _isSending = false;

  String? get _selectedBubbleName {
    if (_selectedBubbleIdForYourDaily == null) return null;
    final idx = YourDailyBubbleManager.bubbles
        .indexWhere((b) => b.id == _selectedBubbleIdForYourDaily);
    if (idx == -1) return null;
    final name = YourDailyBubbleManager.bubbles[idx].name;
    return name.isNotEmpty ? name : 'New';
  }

  Future<void> _handleYourDailyToggle(bool? val) async {
    final checked = val ?? false;
    setState(() => _sendToYourDaily = checked);

    if (!checked) {
      setState(() => _selectedBubbleIdForYourDaily = null);
      return;
    }

    // Checking the box immediately offers an optional bubble to also add
    // this clip to — stacks on top of this sheet and dims everything
    // below it, closes itself the moment a bubble is tapped.
    final bubbleId = await showBubbleQuickPickSheet(context);
    if (mounted) {
      setState(() => _selectedBubbleIdForYourDaily = bubbleId);
    }
  }

  String _buildConfirmationMessage() {
    final parts = <String>[];
    if (_selectedDailyIds.isNotEmpty) {
      parts.add(
        '${_selectedDailyIds.length} ${_selectedDailyIds.length == 1 ? 'Daily' : 'Dailies'}',
      );
    }
    if (_sendToYourDaily) {
      parts.add('Your Daily');
      if (_selectedBubbleName != null) {
        parts.add('"$_selectedBubbleName" bubble');
      }
    }
    return 'Sent to ${parts.join(' and ')}!';
  }

  Future<void> _send() async {
    if (_isSending) return;

    // No clip attached (sheet opened generically) — nothing to send yet.
    if (widget.clipId == null) {
      Navigator.pop(context);
      return;
    }

    if (_selectedDailyIds.isEmpty && !_sendToYourDaily) return;

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

      // ── Send to selected Dailies ──────────────────────────────────────
      if (_selectedDailyIds.isNotEmpty) {
        final currentUid =
            FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
        String username = 'You';
        final user = await _userService.getUserById(currentUid);
        if (user?.username != null && user!.username.isNotEmpty) {
          username = user.username;
        }

        for (final dailyId in _selectedDailyIds) {
          // Load the FULL message list for this Daily — every user's
          // posts — and append to it, so nobody else's messages are lost.
          final existingMessages = await MessageStorage.loadMessages(dailyId);

          final message = DailyMessage(
            text: caption.isNotEmpty ? caption : null,
            videoPath: videoUrl,
            timestamp: DateTime.now(),
            dailyId: dailyId,
            userId: currentUid,
            username: username,
          );

          existingMessages.add(message);
          await MessageStorage.saveMessages(dailyId, existingMessages);
        }
      }

      // ── Post to Your Daily story ──────────────────────────────────────
      if (_sendToYourDaily) {
        // FriendDailyService/DailyVideoTracker both need a local File —
        // download the clip's video from Storage first, same approach
        // NativeShareBar uses to get a local copy for the OS share sheet.
        final tempDir = await getTemporaryDirectory();
        final localFile = File(
          '${tempDir.path}/your_daily_clip_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        await FirebaseStorage.instance.refFromURL(videoUrl).writeToFile(localFile);

        await DailyVideoTracker.addVideo(localFile);
        await FriendDailyService.uploadMyDailyVideo(localFile);

        if (_selectedBubbleIdForYourDaily != null) {
          final bubbleIndex = YourDailyBubbleManager.bubbles
              .indexWhere((b) => b.id == _selectedBubbleIdForYourDaily);
          if (bubbleIndex != -1) {
            await YourDailyBubbleManager.addMediaToBubble(
              bubbleIndex,
              localFile,
              isVideo: true,
            );
          }
        }
      }

      if (mounted) {
        final message = _buildConfirmationMessage();
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('SendToDailySelectorSheet: send error: $e');
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
    final bool canSend =
        widget.clipId != null && (_selectedDailyIds.isNotEmpty || _sendToYourDaily);

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

            // Header — back arrow to close, title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _isSending ? null : () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back, size: 22, color: Colors.black87),
                  ),
                  const Expanded(
                    child: Text(
                      'Send to Daily',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 22), // balances the back arrow
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEEEEEE)),

            // "Your Daily" — pinned above the scrollable list, always the
            // first (and never-scrolling) option.
            CheckboxListTile(
              value: _sendToYourDaily,
              onChanged: _isSending ? null : _handleYourDailyToggle,
              title: const Text(
                'Your Daily',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              subtitle: Text(
                _selectedBubbleName != null
                    ? 'Post to your story + "$_selectedBubbleName" bubble'
                    : 'Post to your story so friends can see it',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              secondary: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 22),
              ),
              activeColor: Colors.deepPurple,
              controlAffinity: ListTileControlAffinity.trailing,
            ),

            const Divider(height: 1, color: Color(0xFFEEEEEE)),

            // Daily checkbox list
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: StreamBuilder<List<DailyData>>(
                stream: DailyList.getDailiesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.cyan),
                      ),
                    );
                  }

                  final dailies = snapshot.data ?? [];

                  if (dailies.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No Dailies yet',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: dailies.length,
                    itemBuilder: (context, index) {
                      final daily = dailies[index];
                      final color = Color(daily.iconColor ?? 0xFF9E9E9E);
                      final isSelected = _selectedDailyIds.contains(daily.id);

                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: _isSending
                            ? null
                            : (val) {
                          setState(() {
                            if (val == true) {
                              _selectedDailyIds.add(daily.id);
                            } else {
                              _selectedDailyIds.remove(daily.id);
                            }
                          });
                        },
                        title: Text(
                          daily.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          daily.privacy,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        secondary: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(daily.icon, color: color, size: 22),
                        ),
                        activeColor: Colors.cyan,
                        controlAffinity: ListTileControlAffinity.trailing,
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Send button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (canSend && !_isSending) ? _send : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSending
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                      : const Text(
                    'Send',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),

            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 12),
          ],
        ),
      ),
    );
  }
}