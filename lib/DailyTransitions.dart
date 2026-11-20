import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'SkipCount.dart';
import 'DailyList.dart';
import 'DrawPad.dart';
import 'CameraCapture.dart';
import 'UnifiedMediaPicker.dart';

/// The Daily entry prompt: pops over a Daily the first time you open it
/// each day. Answer it (text and/or photos/videos), skip it (a few skips a
/// week, see SkipCount), or back out.
///
/// Media works like everywhere else in the app: the camera button takes a
/// photo or video (CameraCapture), and the media button opens your camera
/// roll (the same picker as the Daily chat) in a sheet from the bottom,
/// with Draw at the top of it.
class DailyPromptOverlay extends StatefulWidget {
  final String dailyTitle;
  final String dailyEntryPrompt;
  final TextEditingController entryController;

  /// Answered: the text is in [entryController], the photos/videos here.
  final void Function(List<PickedMedia> media) onSend;

  /// A skip was used: let them in without posting anything.
  final VoidCallback onSkip;

  /// Closed without answering.
  final VoidCallback onBack;

  const DailyPromptOverlay({
    Key? key,
    required this.dailyTitle,
    required this.dailyEntryPrompt,
    required this.entryController,
    required this.onSend,
    required this.onSkip,
    required this.onBack,
  }) : super(key: key);

  @override
  State<DailyPromptOverlay> createState() => _DailyPromptOverlayState();
}

class _DailyPromptOverlayState extends State<DailyPromptOverlay> {
  int _remainingSkips = 0;
  int _totalSkips = 0;
  bool _isProcessingSkip = false;
  bool _done = false; // sent or skipped (stops double taps)
  List<PickedMedia> _media = [];

  @override
  void initState() {
    super.initState();
    _loadSkipInfo();
  }

  Future<void> _loadSkipInfo() async {
    final numDailies = DailyList.dailies.length;
    final remaining = await SkipCount.getRemainingSkips(numDailies);
    if (!mounted) return;
    setState(() {
      _totalSkips = SkipCount.calculateTotalSkips(numDailies);
      _remainingSkips = remaining;
    });
  }

  // ─── Media ────────────────────────────────────────────────────────────────

  Future<void> _openCamera() async {
    FocusScope.of(context).unfocus();
    final shot = await CameraCapture.capture(context);
    if (shot == null || !mounted) return;
    setState(() => _media = [..._media, shot]);
  }

  /// Camera roll in a sheet from the bottom. Tap to check several, then
  /// Add; or Draw.
  Future<void> _openMediaSheet() async {
    FocusScope.of(context).unfocus();
    final height = MediaQuery.of(context).size.height * 0.62;
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).padding.bottom),
        child: UnifiedMediaPickerPanel(
          height: height,
          onMediaSelected: (items) => Navigator.pop(sheetContext, items),
          onDrawTap: () => Navigator.pop(sheetContext, 'draw'),
          onClose: () => Navigator.pop(sheetContext),
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'draw') {
      await _openDrawPad();
    } else if (result is List<PickedMedia> && result.isNotEmpty) {
      setState(() => _media = [..._media, ...result]);
    }
  }

  Future<void> _openDrawPad() async {
    final File? drawingFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          onDrawingComplete: (file) => Navigator.pop(context, file),
        ),
      ),
    );
    if (drawingFile != null && mounted) {
      setState(() => _media = [
        ..._media,
        PickedMedia(file: drawingFile, isVideo: false),
      ]);
    }
  }

  // ─── Send / skip / back ───────────────────────────────────────────────────

  void _snack(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _handleSend() {
    if (_done) return;
    if (widget.entryController.text.trim().isEmpty && _media.isEmpty) {
      _snack('Add text or attach media!', Colors.orange);
      return;
    }
    _done = true;
    FocusScope.of(context).unfocus();
    widget.onSend(List.of(_media));
  }

  Future<void> _handleSkip() async {
    if (_isProcessingSkip || _done) return;
    setState(() => _isProcessingSkip = true);

    final numDailies = DailyList.dailies.length;
    final success = await SkipCount.useSkip(numDailies);
    if (!mounted) return;

    if (success) {
      _done = true;
      FocusScope.of(context).unfocus();
      widget.onSkip();
      return;
    }

    // Either none left, or the server couldn't be reached.
    final remaining = await SkipCount.getRemainingSkips(numDailies);
    if (!mounted) return;
    setState(() {
      _isProcessingSkip = false;
      _remainingSkips = remaining;
    });
    if (remaining <= 0) {
      _snack('No skips remaining this week!', Colors.red);
    } else {
      _snack("Couldn't skip right now. Check your connection and try again.",
          Colors.red);
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  Widget _buildSkipIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Skips: ',
          style: TextStyle(
            fontSize: 12,
            color: kc.grey(600),
            fontWeight: FontWeight.w500,
          ),
        ),
        for (int i = 0; i < _totalSkips; i++)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _remainingSkips ? Colors.cyan : kc.grey(300),
            ),
          ),
        const SizedBox(width: 4),
        Text(
          '($_remainingSkips/$_totalSkips)',
          style: TextStyle(
            fontSize: 12,
            color: kc.grey(600),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// What's attached, as small tiles with an X to remove each.
  Widget _buildPendingStrip() {
    if (_media.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 76,
      margin: const EdgeInsets.only(bottom: 14),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _media.length,
        itemBuilder: (context, index) {
          final item = _media[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: item.isVideo
                        ? Container(
                      color: Colors.grey[800],
                      child: const Center(
                        child: Icon(Icons.play_circle_fill,
                            color: Colors.white, size: 26),
                      ),
                    )
                        : Image.file(
                      item.file,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: kc.line,
                        child: Icon(Icons.broken_image, color: kc.textFaint),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _media.removeAt(index)),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child:
                      const Icon(Icons.close, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _skipButton() {
    final busy = _isProcessingSkip;
    return GestureDetector(
      onTap: busy ? null : _handleSkip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: busy ? kc.grey(200) : kc.grey(300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.skip_next,
                size: 18, color: busy ? kc.grey(400) : kc.grey(700)),
            const SizedBox(width: 6),
            Text(
              busy ? 'Skipping...' : 'Skip Today',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: busy ? kc.grey(400) : kc.grey(700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: kc.surfaceMuted,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 22, color: kc.textMuted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Container(
                margin:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: kc.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          spreadRadius: 2,
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildSkipIndicator(),
                            Expanded(
                              child: Text(
                                widget.dailyTitle,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: kc.text,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close,
                                  color: kc.textMuted, size: 24),
                              onPressed: widget.onBack,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '${widget.dailyEntryPrompt}:',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: kc.text,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        _buildPendingStrip(),
                        TextField(
                          controller: widget.entryController,
                          decoration: InputDecoration(
                            hintText: 'Type your entry here...',
                            hintStyle:
                            TextStyle(color: kc.textFaint, fontSize: 16),
                            filled: true,
                            fillColor: kc.surfaceMuted,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                  color: Colors.cyan, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                          ),
                          style: TextStyle(fontSize: 16, color: kc.text),
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 8,
                          minLines: 8,
                          maxLength: 500,
                          autofocus: true,
                          buildCounter: (context,
                              {required currentLength,
                                required isFocused,
                                maxLength}) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '$currentLength/$maxLength',
                                style: TextStyle(
                                    fontSize: 12, color: kc.grey(600)),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            // Takes the room the buttons don't need; only
                            // shrinks on very narrow phones.
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: _skipButton(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _roundButton(
                                Icons.camera_alt_outlined, _openCamera),
                            const SizedBox(width: 6),
                            _roundButton(Icons.perm_media, _openMediaSheet),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _handleSend,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.cyan,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.cyan.withOpacity(0.4),
                                      spreadRadius: 2,
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.send,
                                    color: Colors.white, size: 24),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}