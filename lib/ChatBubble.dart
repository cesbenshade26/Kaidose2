import 'package:flutter/material.dart';
import 'AppColors.dart';
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
            color: onWallpaper ? context.colors.background.withOpacity(0.85) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: context.colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// One message: yours on the right, everyone else's on the left.
///
/// Text sits in a filled bubble (cyan for you, light grey for others).
/// A photo or video has no bubble around it: it stands on its own with
/// rounded corners, keeps its own shape, and any caption is its own normal
/// bubble tucked just under it. A message sent in from a Daily gets a small
/// "↗ ___ Daily" pill: over the corner of the photo for media, just above
/// the bubble for text.
///
/// Corners on the sender's side tighten inside a run so consecutive
/// messages read as one block.
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

  /// Which Daily this was sent in from (e.g. "counter test Daily"), and what
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

  /// Text bubbles can use 75% of the screen; photos and videos a bit less,
  /// so they don't swallow the conversation.
  static const double _textWidth = 0.75;
  static const double _mediaWidth = 0.64;
  static const double _mediaMaxHeight = 380;

  bool get _hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get _hasVideo => videoUrl != null && videoUrl!.isNotEmpty;
  bool get _hasMedia => _hasImage || _hasVideo;
  bool get _hasTextPart =>
      text.isNotEmpty ||
          parentText != null ||
          (footer != null && footer!.isNotEmpty && !_hasMedia);

  /// Corners for one piece of the message. [top]/[bottom] say whether this
  /// piece is the top or bottom of the whole run (so it gets the round or
  /// tail corner on the sender's side); otherwise that corner is joined.
  BorderRadius _radius({required bool top, required bool bottom}) {
    final t = top ? _round : _joined;
    final b = bottom ? _tail : _joined;
    return BorderRadius.only(
      topLeft: Radius.circular(isMe ? _round : t),
      bottomLeft: Radius.circular(isMe ? _round : b),
      topRight: Radius.circular(isMe ? t : _round),
      bottomRight: Radius.circular(isMe ? b : _round),
    );
  }

  // ─── "Sent from a Daily" ─────────────────────────────────────────────────

  /// Dark see-through pill laid over the top corner of a photo or video.
  Widget _sourcePillOnMedia() {
    return GestureDetector(
      onTap: onSourceTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.north_east, size: 12, color: Colors.white),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                sourceLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small muted line just above a text bubble. It has a faint backing so
  /// it stays readable over a chat wallpaper.
  Widget _sourceLineAboveText(BuildContext context) {
    final muted = context.colors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
      child: GestureDetector(
        onTap: onSourceTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: context.colors.background.withOpacity(0.8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.north_east, size: 11, color: muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'From $sourceLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Media ───────────────────────────────────────────────────────────────

  Widget _media(BuildContext context, double maxW, BorderRadius radius) {
    final Widget content;
    if (_hasImage) {
      content = GestureDetector(
        onTap: onImageTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxW,
            maxHeight: _mediaMaxHeight,
            minWidth: maxW * 0.55,
            minHeight: 120,
          ),
          // No fixed size: the photo keeps its own shape (tall stays tall,
          // wide stays wide) inside the limits above.
          child: Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                width: maxW,
                height: 260,
                color: context.colors.surfaceMuted,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: context.colors.textFaint),
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              width: maxW,
              height: 140,
              color: context.colors.surfaceMuted,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image_outlined,
                      size: 32, color: context.colors.textFaint),
                  const SizedBox(height: 6),
                  Text('Image no longer available',
                      style: TextStyle(
                          color: context.colors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      // Phone videos are almost always tall; cap the height so one video
      // doesn't fill the whole screen.
      final w = (_mediaMaxHeight * 9 / 16).clamp(0.0, maxW);
      content = SizedBox(
        width: w,
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: NetworkVideoPlayer(url: videoUrl!),
        ),
      );
    }

    // Disappearing timer with no caption to hold it: a chip on the media.
    final timerOnMedia = !_hasTextPart && footer != null && footer!.isNotEmpty;

    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          Container(color: context.colors.surfaceMuted, child: content),
          if (sourceLabel != null)
            Positioned(
              top: 8,
              left: 8,
              child: _sourcePillOnMedia(),
            ),
          if (timerOnMedia)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  footer!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Text ────────────────────────────────────────────────────────────────

  Widget _textBubble(BuildContext context, double maxW, BorderRadius radius) {
    final bg = isMe ? Colors.cyan : context.colors.line;
    final fg = isMe ? Colors.white : context.colors.text;

    return Container(
      constraints: BoxConstraints(maxWidth: maxW),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parentText != null)
            Container(
              margin: EdgeInsets.only(bottom: text.isNotEmpty ? 6 : 0),
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: fg.withOpacity(0.5), width: 2.5),
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
                style: TextStyle(fontSize: 15.5, height: 1.25, color: fg)),
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
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final textW = screenW * _textWidth;
    final mediaW = screenW * _mediaWidth;

    final pieces = <Widget>[];

    if (_hasMedia) {
      // Media on top; the caption (if any) is its own bubble right under it.
      pieces.add(_media(
        context,
        mediaW,
        _radius(top: run.first, bottom: run.last && !_hasTextPart),
      ));
      if (_hasTextPart) {
        pieces.add(const SizedBox(height: 2));
        pieces.add(_textBubble(
          context,
          textW,
          _radius(top: false, bottom: run.last),
        ));
      }
    } else {
      if (sourceLabel != null) pieces.add(_sourceLineAboveText(context));
      pieces.add(_textBubble(
        context,
        textW,
        _radius(top: run.first, bottom: run.last),
      ));
    }

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
                  color: context.colors.textMuted,
                ),
              ),
            ),
          ...pieces,
        ],
      ),
    );
  }
}