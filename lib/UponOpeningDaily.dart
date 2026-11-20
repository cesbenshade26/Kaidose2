import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'InsideDaily.dart';
import 'DailyTransitions.dart';
import 'DailyList.dart';
import 'UnifiedMediaPicker.dart';

/// Opening a Daily whose entry prompt you haven't answered (or skipped)
/// today: the Daily loads underneath and the prompt pops over it.
///
///  - Send: the answer is posted to the Daily and you're in.
///  - Skip: uses one of the week's skips and you're in, nothing posted.
///  - X / back: leaves, and the prompt shows again next time.
class UponOpeningDaily extends StatefulWidget {
  final DailyData daily;

  /// Today's scheduled entry prompt (see DailyCoverService.todayPrompt).
  final String prompt;

  const UponOpeningDaily({
    Key? key,
    required this.daily,
    required this.prompt,
  }) : super(key: key);

  @override
  State<UponOpeningDaily> createState() => _UponOpeningDailyState();
}

class _UponOpeningDailyState extends State<UponOpeningDaily> {
  final TextEditingController _entryController = TextEditingController();
  final GlobalKey<InsideDailyState> _insideDailyKey =
  GlobalKey<InsideDailyState>();
  bool _showOverlay = true;

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  /// Answered: let them in, then post the answer into the Daily.
  Future<void> _handleSend(List<PickedMedia> media) async {
    final text = _entryController.text.trim();
    await DailyList.markAsViewed(widget.daily.id);
    if (!mounted) return;
    setState(() => _showOverlay = false);

    if (text.isEmpty && media.isEmpty) return;
    _postWhenReady(text, media);
  }

  /// The Daily underneath is built from the start, so it's normally ready
  /// right away; if not, try again on the next frames for a moment.
  void _postWhenReady(String text, List<PickedMedia> media, [int tries = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inside = _insideDailyKey.currentState;
      if (inside != null) {
        inside.addPromptEntry(text, media);
      } else if (tries < 30) {
        _postWhenReady(text, media, tries + 1);
      }
    });
  }

  /// Skip used: let them in without posting anything (even if they had
  /// started typing).
  Future<void> _handleSkip() async {
    await DailyList.markAsViewed(widget.daily.id);
    if (!mounted) return;
    setState(() => _showOverlay = false);
  }

  /// Backed out of the prompt: they'll have to see it again.
  Future<void> _handleBack() async {
    await DailyList.unmarkAsViewed(widget.daily.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Only while the prompt is up. Once they've answered or skipped,
      // leaving the Daily is a normal back (and on iPhone the swipe-back
      // gesture works again).
      onWillPop: _showOverlay
          ? () async {
        await DailyList.unmarkAsViewed(widget.daily.id);
        return true;
      }
          : null,
      child: Stack(
        children: [
          InsideDaily(
            key: _insideDailyKey,
            daily: widget.daily,
          ),
          if (_showOverlay)
            DailyPromptOverlay(
              dailyTitle: widget.daily.title,
              dailyEntryPrompt: widget.prompt,
              entryController: _entryController,
              onSend: _handleSend,
              onSkip: _handleSkip,
              onBack: _handleBack,
            ),
        ],
      ),
    );
  }
}