import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class VideoArchives {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> openVideoArchives(BuildContext context) async {
    print("Video Archives button tapped!");

    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5), // Optional: limit video duration
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accessing camera: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
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

  @override
  void dispose() {
    super.dispose();
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

      print('Selected video set in state: ${_selectedVideo?.path}');
    } else {
      print('No video selected from archives');
    }
  }

  Future<void> _openFilm() async {
    print("Opening film...");

    // Show coming soon dialog
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Coming Soon!'),
        content: const Text('Video recording feature coming soon.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmVideo(String buttonType) async {
    print('========== CONFIRM VIDEO DEBUG ($buttonType) ==========');
    print('_selectedVideo: ${_selectedVideo?.path ?? "NULL"}');
    print('_selectedVideo exists: ${_selectedVideo?.existsSync() ?? false}');

    if (_selectedVideo != null && _selectedVideo!.existsSync()) {
      print('Valid video found, proceeding with save...');

      if (buttonType == "Share with Friends") {
        // Show coming soon message for Share with Friends
        if (mounted) {
          showDialog(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: const Text('Coming Soon!'),
              content: const Text('Share with friends feature coming soon.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it!'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // TODO: Implement actual video saving logic
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Clip saved as $buttonType!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Reset after saving
      setState(() {
        _selectedVideo = null;
        _videoPath = null;
      });

      print('Clip confirmed and saved successfully as $buttonType');
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
        // Preview area
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
                  child: _selectedVideo != null
                      ? Container(
                    color: Colors.grey[200],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.video_file,
                            size: 64,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Video Selected',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              _videoPath?.split('/').last ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      : Container(
                    color: Colors.grey[50],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Video Preview',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Confirm buttons (only when video is selected)
        if (_selectedVideo != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _confirmVideo("Share with Friends"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Share with Friends!',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _confirmVideo("Clip Post"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Clip Post!',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Bottom section with buttons
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Video Archives button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _openVideoArchives,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                  // Film button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _openFilm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
}