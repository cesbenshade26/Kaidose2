import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'CamRoll.dart';
import 'DrawPad.dart';
import 'SelectDailiesScreen.dart';

class AddDailyMessage extends StatefulWidget {
  const AddDailyMessage({Key? key}) : super(key: key);

  @override
  State<AddDailyMessage> createState() => _AddDailyMessageState();
}

class _AddDailyMessageState extends State<AddDailyMessage> {
  final TextEditingController _messageController = TextEditingController();
  bool _showAttachMenu = false;
  XFile? _selectedImage;
  XFile? _selectedVideo;
  VideoPlayerController? _videoController;

  @override
  void dispose() {
    _messageController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _toggleAttachMenu() {
    setState(() {
      _showAttachMenu = !_showAttachMenu;
    });
  }

  Future<void> _openCameraRoll() async {
    final XFile? image = await CamRoll.openCameraRoll(context);
    if (image != null) {
      setState(() {
        _selectedImage = image;
        _selectedVideo = null;
        _showAttachMenu = false;
      });
      await _videoController?.dispose();
      _videoController = null;
    }
  }

  Future<void> _selectVideo() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? video = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        await _videoController?.dispose();
        _videoController = null;

        final videoFile = File(video.path);
        _videoController = VideoPlayerController.file(videoFile);

        try {
          await _videoController!.initialize();
          if (mounted) {
            _videoController!.setLooping(true);
            _videoController!.play();
          }
        } catch (e) {
          print('Error initializing video: $e');
        }

        setState(() {
          _selectedVideo = video;
          _selectedImage = null;
          _showAttachMenu = false;
        });
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

    if (drawingFile != null) {
      final xFile = XFile(drawingFile.path);
      setState(() {
        _selectedImage = xFile;
        _selectedVideo = null;
        _showAttachMenu = false;
      });
      await _videoController?.dispose();
      _videoController = null;
    }
  }

  void _removeMedia() {
    setState(() {
      _selectedImage = null;
      _selectedVideo = null;
    });
    _videoController?.dispose();
    _videoController = null;
  }

  Future<void> _handleNext() async {
    final text = _messageController.text.trim();

    if (text.isEmpty && _selectedImage == null && _selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a message or attach media'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Navigate to daily selection screen
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SelectDailiesScreen(
          messageText: text.isNotEmpty ? text : null,
          imagePath: _selectedImage?.path,
          videoPath: _selectedVideo?.path,
        ),
      ),
    );

    // Clear after successful send
    _messageController.clear();
    _removeMedia();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),

                  // Title
                  const Text(
                    'Compose Message',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Send a message to multiple dailies at once',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Media preview
                  if (_selectedImage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      height: 250,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.cyan, width: 2),
                      ),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              File(_selectedImage!.path),
                              width: double.infinity,
                              height: 250,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: GestureDetector(
                              onTap: _removeMedia,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
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

                  if (_selectedVideo != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      height: 250,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.cyan, width: 2),
                      ),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: _videoController != null && _videoController!.value.isInitialized
                                ? SizedBox(
                              width: double.infinity,
                              height: 250,
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _videoController!.value.size.width,
                                  height: _videoController!.value.size.height,
                                  child: VideoPlayer(_videoController!),
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
                            top: 12,
                            right: 12,
                            child: GestureDetector(
                              onTap: _removeMedia,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
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

                  // Attach button
                  GestureDetector(
                    onTap: _toggleAttachMenu,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.cyan.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.attach_file,
                            color: Colors.cyan,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Attach Media',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Attach menu
                  if (_showAttachMenu)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildAttachOption(Icons.photo_library, 'Photo', _openCameraRoll),
                          _buildAttachOption(Icons.videocam, 'Video', _selectVideo),
                          _buildAttachOption(Icons.edit, 'Draw', _openDrawPad),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Message label
                  const Text(
                    'Message',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Text input
                  TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type your message here...',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.cyan,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(20),
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                    maxLines: 8,
                    minLines: 5,
                    maxLength: 500,
                  ),
                ],
              ),
            ),
          ),

          // Send button at bottom
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _handleNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Next: Choose Dailies',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.cyan, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}