import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'ClipManager.dart';
import 'ClipTracker.dart';

class VideoArchives {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> openVideoArchives(BuildContext context) async {
    print("Video Archives button tapped!");

    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        print('Selected video path: ${video.path}');
        return video;
      } else {
        print('No video selected - user cancelled');
        return null;
      }
    } catch (e) {
      print('Error accessing video archives: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accessing videos: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }
}

class UseFilm {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> openFilm(BuildContext context) async {
    print("Film button tapped!");

    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
        preferredCameraDevice: CameraDevice.rear,
      );

      if (video != null) {
        print('Filmed video path: ${video.path}');
        return video;
      } else {
        print('No video captured - user cancelled');
        return null;
      }
    } catch (e) {
      print('Error accessing camera for video: $e');

      String errorMessage = 'Unable to access camera';
      if (e.toString().contains('camera_access_denied')) {
        errorMessage = 'Camera access denied. Please enable camera permission in settings.';
      } else if (e.toString().contains('no_available_camera')) {
        errorMessage = 'No camera available on this device.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
      return null;
    }
  }
}

class AddClipWidget extends StatefulWidget {
  const AddClipWidget({Key? key}) : super(key: key);

  @override
  State<AddClipWidget> createState() => _AddClipWidgetState();
}

class _AddClipWidgetState extends State<AddClipWidget> {
  File? _selectedVideo;
  String? _videoPath;
  VideoPlayerController? _videoController;
  bool _isInitializing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo(File videoFile) async {
    print('========== VIDEO INITIALIZATION START ==========');
    print('Video file path: ${videoFile.path}');
    print('Video file exists: ${videoFile.existsSync()}');

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      // Dispose of old controller if exists
      await _videoController?.dispose();
      _videoController = null;

      print('Creating VideoPlayerController...');
      _videoController = VideoPlayerController.file(videoFile);

      print('Initializing controller...');
      await _videoController!.initialize();

      print('Controller initialized successfully!');
      print('Video duration: ${_videoController!.value.duration}');
      print('Video size: ${_videoController!.value.size}');

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }

      // Small delay before playing
      await Future.delayed(const Duration(milliseconds: 100));

      _videoController!.setLooping(true);
      _videoController!.play();

      print('Video is now playing');
    } catch (e, stackTrace) {
      print('ERROR initializing video: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Failed to load video: $e';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading video: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    print('========== VIDEO INITIALIZATION END ==========');
  }

  Future<void> _openVideoArchives() async {
    print("Opening video archives...");
    final XFile? pickedFile = await VideoArchives.openVideoArchives(context);
    if (pickedFile != null) {
      print('Video selected: ${pickedFile.path}');
      final File videoFile = File(pickedFile.path);

      setState(() {
        _selectedVideo = videoFile;
        _videoPath = pickedFile.path;
      });

      await _initializeVideo(videoFile);
      print('Selected video set in state: ${_selectedVideo?.path}');
    } else {
      print('No video selected from archives');
    }
  }

  Future<void> _openFilm() async {
    print("Opening film camera...");
    final XFile? pickedFile = await UseFilm.openFilm(context);
    if (pickedFile != null) {
      print('Video filmed: ${pickedFile.path}');
      final File videoFile = File(pickedFile.path);

      setState(() {
        _selectedVideo = videoFile;
        _videoPath = pickedFile.path;
      });

      await _initializeVideo(videoFile);
      print('Filmed video set in state: ${_selectedVideo?.path}');
    } else {
      print('No video filmed from camera');
    }
  }

  Future<void> _confirmVideo(String buttonType) async {
    print('========== CONFIRM VIDEO DEBUG ($buttonType) ==========');
    print('_selectedVideo: ${_selectedVideo?.path ?? "NULL"}');
    print('_selectedVideo exists: ${_selectedVideo?.existsSync() ?? false}');

    if (_selectedVideo != null && _selectedVideo!.existsSync()) {
      print('Valid video found, proceeding with save...');

      try {
        await ClipTracker.addClip(_selectedVideo!);
        await ClipManager.setClip(_selectedVideo!);

        print('Clip saved via both systems');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Clip posted successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }

        // Dispose video controller and reset state
        await _videoController?.dispose();
        _videoController = null;

        setState(() {
          _selectedVideo = null;
          _videoPath = null;
          _errorMessage = null;
        });

        print('Clip confirmed and saved successfully');
      } catch (e) {
        print('ERROR in _confirmVideo: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving clip: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      print('NO VALID VIDEO - showing dialog');
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Your Clip Awaits!'),
            content: const Text('Select a video from Video Archives or film a new one to create Your Clip.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it!'),
              ),
            ],
          ),
        );
      }
    }
    print('========== END CONFIRM VIDEO DEBUG ==========');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildVideoPreview(),
                ),
              ),
            ),
          ),
        ),
        if (_selectedVideo != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => _confirmVideo("Clip Post"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Post Clip!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _openVideoArchives,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.video_library, size: 24),
                          SizedBox(width: 12),
                          Text('Video Archives', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _openFilm,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam, size: 24),
                          SizedBox(width: 12),
                          Text('Film', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPreview() {
    if (_errorMessage != null) {
      return Container(
        color: Colors.red[50],
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  'Video Error',
                  style: TextStyle(fontSize: 18, color: Colors.red[700], fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(fontSize: 12, color: Colors.red[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_selectedVideo != null) {
      if (_isInitializing) {
        return Container(
          color: Colors.grey[200],
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Loading video...',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );
      }

      if (_videoController != null && _videoController!.value.isInitialized) {
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        );
      }

      // Fallback state
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Text(
            'Video not ready',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }

    // No video selected
    return Container(
      color: Colors.grey[50],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Video Preview', style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}