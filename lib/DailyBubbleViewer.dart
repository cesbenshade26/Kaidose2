import 'package:flutter/material.dart';
import 'FriendStoryBar.dart';
import 'StoryMediaItem.dart';

/// Views every Your Daily posted to a single Daily Bubble, oldest first —
/// photos and video clips both — same progress-bar, tap-to-advance
/// experience as a friend's story (FriendStoryViewer in
/// FriendStoryBar.dart), just headed by the bubble's name instead of a
/// username.
class DailyBubbleViewer extends StatefulWidget {
  final List<StoryMediaItem> items;
  final String bubbleName;

  const DailyBubbleViewer({
    Key? key,
    required this.items,
    required this.bubbleName,
  }) : super(key: key);

  @override
  State<DailyBubbleViewer> createState() => _DailyBubbleViewerState();
}

class _DailyBubbleViewerState extends State<DailyBubbleViewer>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _progressController;
  static const Duration _photoDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(vsync: this, duration: _photoDuration);
    _startProgress();
  }

  void _startProgress() {
    _progressController.reset();
    _progressController.forward().then((_) {
      if (mounted) _nextItem();
    });
  }

  void _nextItem() {
    if (_currentIndex < widget.items.length - 1) {
      setState(() => _currentIndex++);
      _startProgress();
    } else {
      Navigator.pop(context);
    }
  }

  void _prevItem() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _startProgress();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          final x = details.globalPosition.dx;
          final width = MediaQuery.of(context).size.width;
          if (x < width / 3) {
            _prevItem();
          } else {
            _nextItem();
          }
        },
        child: Stack(
          children: [
            // Blurred background + rounded photo, or fullscreen video —
            // shared with the story bars (StoryMediaView already branches
            // on isVideo).
            Positioned.fill(
              child: StoryMediaView(media: widget.items[_currentIndex]),
            ),

            // Progress bars
            Positioned(
              top: 60,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(widget.items.length, (i) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: i == _currentIndex
                            ? AnimatedBuilder(
                          animation: _progressController,
                          builder: (_, __) => LinearProgressIndicator(
                            value: _progressController.value,
                            valueColor:
                            const AlwaysStoppedAnimation(Colors.white),
                            backgroundColor: Colors.white.withOpacity(0.4),
                            minHeight: 3,
                          ),
                        )
                            : LinearProgressIndicator(
                          value: i < _currentIndex ? 1.0 : 0.0,
                          valueColor:
                          const AlwaysStoppedAnimation(Colors.white),
                          backgroundColor: Colors.white.withOpacity(0.4),
                          minHeight: 3,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Bubble name
            Positioned(
              top: 74,
              left: 16,
              child: Text(
                widget.bubbleName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),

            // Close button
            Positioned(
              top: 60,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),

            // Counter
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '${_currentIndex + 1} of ${widget.items.length}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}