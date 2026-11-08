import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'DrawPad.dart';
import 'UnifiedMediaPicker.dart';
import 'YourDaily.dart' show UseCam;

/// The chat bar from Inside Daily, shared by every chat screen:
/// media button on the left (opens the photo/video picker under the bar),
/// text field, and a camera button on the right that turns into Send as soon
/// as there is text or attached media.
///
/// Camera: tap = take a photo, hold = record a video.
class ChatComposer extends StatefulWidget {
  /// Called with the text and any attached media when Send is pressed.
  final Future<void> Function(String text, List<PickedMedia> media) onSend;
  final FocusNode focusNode;

  /// Shown above the bar (e.g. the "Replying to..." banner).
  final Widget? banner;

  const ChatComposer({
    Key? key,
    required this.onSend,
    required this.focusNode,
    this.banner,
  }) : super(key: key);

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final List<PickedMedia> _pending = [];
  late final AnimationController _picker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  bool _showPicker = false;
  bool _sending = false;
  double _knownKeyboard = 0;

  bool get _canSend =>
      _controller.text.trim().isNotEmpty || _pending.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _picker.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- picker

  void _openPicker() {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    setState(() => _showPicker = true);
    if (inset > 0) {
      // Keyboard is up: the picker takes over its space as it drops.
      _picker.value = 1;
      widget.focusNode.unfocus();
    } else {
      _picker.forward();
    }
  }

  void _closePicker() {
    _picker.reverse().then((_) {
      if (mounted) setState(() => _showPicker = false);
    });
  }

  void _togglePicker() => _showPicker ? _closePicker() : _openPicker();

  void _onPicked(List<PickedMedia> items) {
    setState(() => _pending.addAll(items));
    _closePicker();
  }

  Future<void> _openDrawPad() async {
    final File? drawing = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          onDrawingComplete: (file) => Navigator.pop(context, file),
        ),
      ),
    );
    if (drawing != null && mounted) {
      setState(() => _pending.add(PickedMedia(file: drawing, isVideo: false)));
      _closePicker();
    }
  }

  // ------------------------------------------------------------- camera

  Future<void> _takePhoto() async {
    final image = await UseCam.openCamera(context);
    if (image != null && mounted) {
      setState(
              () => _pending.add(PickedMedia(file: File(image.path), isVideo: false)));
    }
  }

  Future<void> _recordVideo() async {
    try {
      final video = await ImagePicker().pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 1),
      );
      if (video != null && mounted) {
        setState(() =>
            _pending.add(PickedMedia(file: File(video.path), isVideo: true)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not record video: $e')));
      }
    }
  }

  // --------------------------------------------------------------- send

  Future<void> _send() async {
    if (!_canSend || _sending) return;
    final text = _controller.text.trim();
    final media = List<PickedMedia>.from(_pending);

    _controller.clear();
    setState(() {
      _pending.clear();
      _sending = media.isNotEmpty;
    });
    if (_showPicker) _closePicker();

    try {
      await widget.onSend(text, media);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  // ----------------------------------------------------------------- UI

  Widget _pendingStrip() {
    if (_pending.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 90,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _pending.length,
        itemBuilder: (context, index) {
          final item = _pending[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[300]!, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.isVideo
                        ? Container(
                      color: Colors.grey[800],
                      child: const Center(
                        child: Icon(Icons.play_circle_fill,
                            color: Colors.white, size: 28),
                      ),
                    )
                        : Image.file(
                      item.file,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: Icon(Icons.broken_image,
                            color: Colors.grey[400]),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _pending.removeAt(index)),
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

  /// Plain (no ink) round button. These two swap inside an AnimatedSwitcher,
  /// and ink widgets there throw focus-highlight errors while typing.
  Widget _roundButton(IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration:
      const BoxDecoration(color: Colors.cyan, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }

  Widget _bar() {
    return Row(
      children: [
        Container(
          decoration:
          BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
          child: IconButton(
            icon: Icon(Icons.perm_media, color: Colors.grey[700], size: 22),
            onPressed: _togglePicker,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              decoration: InputDecoration(
                hintText: 'Message...',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 16),
                border: InputBorder.none,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              style: const TextStyle(fontSize: 16, color: Colors.black87),
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
        ),
        const SizedBox(width: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _canSend
              ? GestureDetector(
            key: const ValueKey('send'),
            behavior: HitTestBehavior.opaque,
            onTap: _send,
            child: _roundButton(Icons.send),
          )
              : GestureDetector(
            key: const ValueKey('camera'),
            behavior: HitTestBehavior.opaque,
            onTap: _takePhoto,
            onLongPress: _recordVideo,
            child: _roundButton(Icons.camera_alt),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = mq.viewInsets.bottom;
    final safeBottom = mq.padding.bottom;
    if (inset > _knownKeyboard) _knownKeyboard = inset;

    return AnimatedBuilder(
      animation: _picker,
      builder: (context, _) {
        // Total space the picker occupies below the bar. It gives way to the
        // keyboard (and takes over from it) frame by frame, so switching
        // between the two never jumps.
        final total = _knownKeyboard > 0 ? _knownKeyboard : 336.0 + safeBottom;
        final panelH = _showPicker
            ? (total * _picker.value - inset).clamp(0.0, total)
            : 0.0;

        // The keyboard has fully taken the picker's place: remove it.
        if (_showPicker &&
            widget.focusNode.hasFocus &&
            panelH <= 0 &&
            inset > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _picker.value = 0;
            setState(() => _showPicker = false);
          });
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                bottom: !_showPicker,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.banner != null) widget.banner!,
                    if (_sending)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.cyan),
                            ),
                            const SizedBox(width: 10),
                            Text('Sending...',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    _pendingStrip(),
                    _bar(),
                  ],
                ),
              ),
            ),
            if (_showPicker)
              ClipRect(
                child: SizedBox(
                  height: panelH,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: total,
                    maxHeight: total,
                    child: Column(
                      children: [
                        SizedBox(
                          height: total - safeBottom,
                          child: UnifiedMediaPickerPanel(
                            height: total - safeBottom,
                            onMediaSelected: _onPicked,
                            onDrawTap: _openDrawPad,
                            onClose: _closePicker,
                          ),
                        ),
                        SizedBox(height: safeBottom),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}