import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'SkipCount.dart';
import 'DailyList.dart';
import 'CamRoll.dart';
import 'DrawPad.dart';
import 'UseCam.dart';

class DailyPromptOverlay extends StatefulWidget {
  final String dailyTitle;
  final String dailyEntryPrompt;
  final VoidCallback onSend;
  final VoidCallback onBack;
  final TextEditingController entryController;
  final XFile? selectedImage;
  final XFile? selectedVideo;
  final VideoPlayerController? videoController;
  final VoidCallback? onMediaRemove;
  final Function(XFile?, XFile?, VideoPlayerController?)? onMediaAttach;

  const DailyPromptOverlay({
    Key? key,
    required this.dailyTitle,
    required this.dailyEntryPrompt,
    required this.onSend,
    required this.onBack,
    required this.entryController,
    this.selectedImage,
    this.selectedVideo,
    this.videoController,
    this.onMediaRemove,
    this.onMediaAttach,
  }) : super(key: key);

  @override
  State<DailyPromptOverlay> createState() => _DailyPromptOverlayState();
}

class _DailyPromptOverlayState extends State<DailyPromptOverlay> {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _blurAnimation;
  int _remainingSkips = 0;
  int _totalSkips = 0;
  bool _showAttachMenu = false;

  @override
  void initState() {
    super.initState();
    _loadSkipInfo();
  }

  void _loadSkipInfo() async {
    // Check for weekly reset first
    await SkipCount.checkAndResetIfNewWeek();

    int numDailies = DailyList.dailies.length;
    setState(() {
      _totalSkips = SkipCount.calculateTotalSkips(numDailies);
      _remainingSkips = SkipCount.getRemainingSkips(numDailies);
    });
  }

  void _toggleAttachMenu() {
    setState(() {
      _showAttachMenu = !_showAttachMenu;
    });
  }

  Future<void> _openCameraRoll() async {
    final XFile? image = await CamRoll.openCameraRoll(context);
    if (image != null && widget.onMediaAttach != null) {
      widget.onMediaAttach!(image, null, null);
      _toggleAttachMenu();
    }
  }

  Future<void> _openCamera() async {
    final XFile? image = await UseCam.openCamera(context);
    if (image != null && widget.onMediaAttach != null) {
      widget.onMediaAttach!(image, null, null);
      _toggleAttachMenu();
    }
  }

  Future<void> _selectVideo() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? video = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null && widget.onMediaAttach != null) {
        final videoFile = File(video.path);
        final controller = VideoPlayerController.file(videoFile);

        try {
          await controller.initialize();
          controller.setLooping(true);
          controller.play();
          widget.onMediaAttach!(null, video, controller);
        } catch (e) {
          print('Error initializing video: $e');
          controller.dispose();
        }
        _toggleAttachMenu();
      }
    } catch (e) {
      print('Error selecting video: $e');
    }
  }

  Future<void> _openDrawPad() async {
    final File? drawingFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          onDrawingComplete: (file) {
            Navigator.pop(context, file);
          },
        ),
      ),
    );

    if (drawingFile != null && widget.onMediaAttach != null) {
      // Convert File to XFile
      final xFile = XFile(drawingFile.path);
      widget.onMediaAttach!(xFile, null, null);
    }
    _toggleAttachMenu();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _handleSend() async {
    if (widget.entryController.text.trim().isEmpty && widget.selectedImage == null && widget.selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Add text or attach media!'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    widget.onSend();
  }

  Future<void> _handleSkip() async {
    int numDailies = DailyList.dailies.length;
    bool success = await SkipCount.useSkip(numDailies);

    if (success) {
      widget.onSend(); // Close overlay and show chat
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No skips remaining this week!'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _handleBack() async {
    widget.onBack();
  }

  Widget _buildAttachOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.cyan, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkipIndicator() {
    List<Widget> dots = [];
    for (int i = 0; i < _totalSkips; i++) {
      dots.add(
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < _remainingSkips ? Colors.cyan : Colors.grey[300],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Skips: ',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        ...dots,
        const SizedBox(width: 4),
        Text(
          '($_remainingSkips/$_totalSkips)',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 8.0,
              sigmaY: 8.0,
            ),
            child: Container(
              color: Colors.black.withOpacity(0.3),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.black54,
                                size: 24,
                              ),
                              onPressed: _handleBack,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '${widget.dailyEntryPrompt}:',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),

                        // Media preview
                        if (widget.selectedImage != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.cyan, width: 2),
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(widget.selectedImage!.path),
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: GestureDetector(
                                    onTap: widget.onMediaRemove,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (widget.selectedVideo != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.cyan, width: 2),
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: widget.videoController != null && widget.videoController!.value.isInitialized
                                      ? SizedBox(
                                    width: double.infinity,
                                    height: 200,
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: widget.videoController!.value.size.width,
                                        height: widget.videoController!.value.size.height,
                                        child: VideoPlayer(widget.videoController!),
                                      ),
                                    ),
                                  )
                                      : Container(
                                    color: Colors.grey[200],
                                    child: const Center(
                                      child: CircularProgressIndicator(color: Colors.cyan),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: GestureDetector(
                                    onTap: widget.onMediaRemove,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        Row(
                          children: [
                            // Attach button
                            GestureDetector(
                              onTap: _toggleAttachMenu,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.cyan.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.cyan, width: 1.5),
                                ),
                                child: const Icon(
                                  Icons.attach_file,
                                  color: Colors.cyan,
                                  size: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: widget.entryController,
                                decoration: InputDecoration(
                                  hintText: 'Type your entry here...',
                                  hintStyle: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 16,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(
                                      color: Colors.cyan,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                maxLines: 8,
                                minLines: 8,
                                maxLength: 500,
                                autofocus: true,
                                buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      '$currentLength/$maxLength',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),

                        // Attach menu
                        if (_showAttachMenu)
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildAttachOption(Icons.photo_library, 'Photo', _openCameraRoll),
                                _buildAttachOption(Icons.camera_alt, 'Camera', _openCamera),
                                _buildAttachOption(Icons.videocam, 'Video', _selectVideo),
                                _buildAttachOption(Icons.edit, 'Draw', _openDrawPad),
                              ],
                            ),
                          ),

                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: _handleSkip,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.skip_next,
                                      size: 18,
                                      color: Colors.grey[700],
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Skip Today',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _handleSend,
                              child: Container(
                                padding: const EdgeInsets.all(14),
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
                                child: const Icon(
                                  Icons.send,
                                  color: Colors.white,
                                  size: 24,
                                ),
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