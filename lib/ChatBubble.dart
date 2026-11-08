import 'package:flutter/material.dart';
import 'NetworkVideoPlayer.dart';

/// Where a message sits inside a run of messages from the same person.
class BubbleRun {
  final bool first; // top of the run (shows the sender's name in groups)
  final bool last; // bottom of the run (gets the tail corner)
  final String? timeLabel; // "Today 2:14 PM" shown above, when there is a gap

  const BubbleRun({this.first = true, this.last = true, this.timeLabel});
}

/// Works out the run info for message [index] of a newest-first list.
/// Messages from the same sender within [runGap] belong to one run; a gap of
/// more than [labelGap] gets a time label above it.
class BubbleGrouping {
  static const Duration runGap = Duration(minutes: 5);
  static const Duration labelGap = Duration(minutes: 30);

  static BubbleRun compute({
    required String senderId,
    required DateTime? time,
    required String? olderSender,
    required DateTime? olderTime,
    required bool olderBreaks,
    required String? newerSender,
    required DateTime? newerTime,
    required bool newerBreaks,
  }) {
    bool sameRun(String? otherSender, DateTime? otherTime, bool breaks) {
      if (breaks || otherSender == null || otherSender != senderId) return false;
      if (time != null && otherTime != null) {
        return time.difference(otherTime).abs() <= runGap;
      }
      return true;
    }

    final first = !sameRun(olderSender, olderTime, olderBreaks);
    final last = !sameRun(newerSender, newerTime, newerBreaks);

    String? label;
    if (time != null) {
      if (olderTime == null && olderSender == null) {
        label = formatLabel(time);
      } else if (olderTime != null &&
          time.difference(olderTime) > labelGap) {
        label = formatLabel(time);
      }
    }
    return BubbleRun(first: first, last: last, timeLabel: label);
  }

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String formatLabel(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final clock = '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return 'Today $clock';
    if (diff == 1) return 'Yesterday $clock';
    if (diff < 7) return '${_weekdays[t.weekday - 1]} $clock';
    final year = t.year == now.year ? '' : ', ${t.year}';
    return '${_months[t.month - 1]} ${t.day}$year  $clock';
  }
}

/// The small centered time label between bursts of messages.
class BubbleTimeLabel extends StatelessWidget {
  final String text;
  final bool onWallpaper;

  const BubbleTimeLabel(
      {Key? key, required this.text, this.onWallpaper = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: onWallpaper ? Colors.white.withOpacity(0.85) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }
}

/// A filled message bubble: yours in cyan on the right, everyone else's in
/// light grey on the left. Corners on the sender's side tighten inside a run
/// so consecutive messages read as one block.
class ChatBubble extends StatelessWidget {
  final bool isMe;
  final String text;
  final String? parentText;
  final String? senderName; // shown above the first bubble of a run
  final String? imageUrl;
  final String? videoUrl;
  final String? footer; // e.g. the disappearing-message timer
  final BubbleRun run;
  final VoidCallback? onImageTap;

  /// "Sent from ___ Daily" tag shown at the top of the bubble, and what
  /// tapping it does (open that Daily).
  final String? sourceLabel;
  final VoidCallback? onSourceTap;

  const ChatBubble({
    Key? key,
    required this.isMe,
    required this.text,
    required this.run,
    this.parentText,
    this.senderName,
    this.imageUrl,
    this.videoUrl,
    this.footer,
    this.onImageTap,
    this.sourceLabel,
    this.onSourceTap,
  }) : super(key: key);

  static const double _round = 18;
  static const double _joined = 6;
  static const double _tail = 4;

  /// A small grey tab that rises out of the top of the bubble (same look as
  /// the Daily prompt tab), saying which Daily this was sent from.
  Widget _sourceTab() {
    return GestureDetector(
      onTap: onSourceTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SENT FROM',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Colors.cyan,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                sourceLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            if (onSourceTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.north_east, size: 13, color: Colors.cyan),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.75;
    final bg = isMe ? Colors.cyan : Colors.grey[200]!;
    final fg = isMe ? Colors.white : Colors.black87;

    // Sender-side corners tighten inside a run; the last one is the tail.
    final top = run.first ? _round : _joined;
    final bottom = run.last ? _tail : _joined;
    // With a source tab on top, the corner under the tab squares off so the
    // two read as one piece.
    final hasTab = sourceLabel != null;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMe ? _round : (hasTab ? 0 : top)),
      bottomLeft: Radius.circular(isMe ? _round : bottom),
      topRight: Radius.circular(isMe ? (hasTab ? 0 : top) : _round),
      bottomRight: Radius.circular(isMe ? bottom : _round),
    );

    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final hasVideo = videoUrl != null && videoUrl!.isNotEmpty;
    final hasTextPart =
        text.isNotEmpty || parentText != null || (footer != null);

    final bubbleBox = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImage)
            GestureDetector(
              onTap: onImageTap,
              child: Image.network(
                imageUrl!,
                width: maxW,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: maxW,
                    height: 200,
                    color: Colors.grey[300],
                    child: const Center(
                      child:
                      CircularProgressIndicator(color: Colors.cyan),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  width: maxW,
                  height: 140,
                  color: Colors.grey[300],
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image_outlined,
                          size: 36, color: Colors.grey[500]),
                      const SizedBox(height: 6),
                      Text('Image no longer available',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          if (hasVideo)
            SizedBox(
              width: maxW,
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: NetworkVideoPlayer(url: videoUrl!),
              ),
            ),
          if (hasTextPart)
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (parentText != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                              color: fg.withOpacity(0.5), width: 2.5),
                        ),
                      ),
                      child: Text(
                        parentText!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          color: fg.withOpacity(0.8),
                        ),
                      ),
                    ),
                  if (text.isNotEmpty)
                    Text(text,
                        style: TextStyle(
                            fontSize: 15.5, height: 1.25, color: fg)),
                  if (footer != null && footer!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        footer!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: fg.withOpacity(0.7),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: run.first ? 8 : 2),
      child: Column(
        crossAxisAlignment:
        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (senderName != null && run.first && !isMe)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 3),
              child: Text(
                senderName!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[600],
                ),
              ),
            ),
          if (!hasTab)
            bubbleBox
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: _sourceTab(),
                    ),
                    bubbleBox,
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}