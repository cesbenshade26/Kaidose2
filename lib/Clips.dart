import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import 'ClipManager.dart';
import 'ClipTracker.dart';
import 'AddClip.dart';

class ClipsWidget extends StatefulWidget {
  const ClipsWidget({Key? key}) : super(key: key);

  @override
  State<ClipsWidget> createState() => _ClipsWidgetState();
}

class _ClipsWidgetState extends State<ClipsWidget> {
  File? _selectedVideo;
  File? _currentDisplayVideo;
  int _currentVideoIndex = -1;
  List<File> _todaysVideos = [];
  VoidCallback? _trackerListener;
  VideoPlayerController? _videoController;
  bool _isInitializing = false;
  String? _errorMessage;
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();

    _initializeTracker();

    _trackerListener = () {
      if (mounted) {
        setState(() {
          _todaysVideos = ClipTracker.todaysClips;
          if (_todaysVideos.isNotEmpty && _currentVideoIndex == -1 && _selectedVideo == null) {
            _currentVideoIndex = _todaysVideos.length - 1;
            _currentDisplayVideo = _todaysVideos[_currentVideoIndex];
            _initializeVideo(_currentDisplayVideo!);
          }
        });
      }
    };

    ClipTracker.addListener(_trackerListener!);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    if (_trackerListener != null) {
      ClipTracker.removeListener(_trackerListener!);
    }
    super.dispose();
  }

  Future<void> _initializeVideo(File videoFile) async {
    print('========== CLIPS VIDEO INITIALIZATION START ==========');
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

      // Add listener to detect when video is ready
      _videoController!.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });

      print('Initializing controller...');
      await _videoController!.initialize();

      print('Controller initialized successfully!');
      print('Video duration: ${_videoController!.value.duration}');
      print('Video size: ${_videoController!.value.size}');

      // Set looping BEFORE setState
      _videoController!.setLooping(true);

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });

        // Play after setState completes
        await Future.delayed(const Duration(milliseconds: 50));
        _videoController!.play();

        // Force another setState to ensure playing state is reflected
        await Future.delayed(const Duration(milliseconds: 50));
        setState(() {});
      }

      print('Video is now playing: ${_videoController!.value.isPlaying}');
    } catch (e, stackTrace) {
      print('ERROR initializing video: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Failed to load video: $e';
        });
      }
    }
    print('========== CLIPS VIDEO INITIALIZATION END ==========');
  }

  Future<void> _initializeTracker() async {
    await ClipTracker.initialize();
    if (mounted) {
      setState(() {
        _todaysVideos = ClipTracker.todaysClips;
        if (_todaysVideos.isNotEmpty) {
          _currentVideoIndex = _todaysVideos.length - 1;
          _currentDisplayVideo = _todaysVideos[_currentVideoIndex];
          _initializeVideo(_currentDisplayVideo!);
        }
      });
    }
  }

  void _navigateVideos(int direction) {
    if (_todaysVideos.isEmpty) return;

    int newIndex;
    if (_currentVideoIndex == -1) {
      if (direction > 0) {
        newIndex = 0;
      } else {
        return;
      }
    } else {
      newIndex = (_currentVideoIndex + direction).clamp(0, _todaysVideos.length - 1);
    }

    if (newIndex >= 0 && newIndex < _todaysVideos.length) {
      setState(() {
        _currentVideoIndex = newIndex;
        _currentDisplayVideo = _todaysVideos[_currentVideoIndex];
        _selectedVideo = null;
        _isLiked = false; // Reset like state when changing videos
      });
      _initializeVideo(_currentDisplayVideo!);
    }
  }

  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;
    });
  }

  bool get _canNavigateLeft => _todaysVideos.isNotEmpty && _currentVideoIndex > 0;
  bool get _canNavigateRight => _todaysVideos.isNotEmpty && _currentVideoIndex < _todaysVideos.length - 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: Stack(
        children: [
          // Full screen video display
          Positioned.fill(
            top: 0,
            bottom: 0,
            child: _buildVideoDisplay(),
          ),

          // Navigation arrows
          if (_canNavigateLeft)
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _navigateVideos(-1),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),

          if (_canNavigateRight)
            Positioned(
              right: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _navigateVideos(1),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),

          // Video counter
          if (_todaysVideos.isNotEmpty && _currentVideoIndex >= 0)
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Clip ${_currentVideoIndex + 1} of ${_todaysVideos.length}',
                    style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),

          // Social interaction buttons (Like, Comment, Share)
          if (_todaysVideos.isNotEmpty && _currentVideoIndex >= 0)
            Positioned(
              right: 16,
              bottom: 120,
              child: Column(
                children: [
                  // Like button
                  GestureDetector(
                    onTap: _toggleLike,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked ? Colors.red : Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Comment button
                  GestureDetector(
                    onTap: () {
                      print('Comment button tapped');
                      // TODO: Implement comment functionality
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mode_comment_outlined,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Share button
                  GestureDetector(
                    onTap: () {
                      print('Share button tapped');
                      // TODO: Implement share functionality
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send_outlined,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoDisplay() {
    if (_errorMessage != null) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  'Video Error',
                  style: TextStyle(fontSize: 24, color: Colors.red[400], fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_currentDisplayVideo != null && _currentDisplayVideo!.existsSync()) {
      if (_isInitializing) {
        return Container(
          color: Colors.grey[900],
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading video...',
                  style: TextStyle(color: Colors.grey[400], fontSize: 16),
                ),
              ],
            ),
          ),
        );
      }

      if (_videoController != null && _videoController!.value.isInitialized) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        );
      }

      // Fallback state
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.video_file, size: 80, color: Colors.grey[600]),
              const SizedBox(height: 16),
              Text(
                'Video not ready',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // No video selected
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_outlined, size: 80, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No Clips Yet',
              style: TextStyle(fontSize: 24, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'Post your first clip from the Add tab',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}