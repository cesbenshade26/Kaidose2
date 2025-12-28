import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class ClipsArchivesScreen extends StatefulWidget {
  const ClipsArchivesScreen({Key? key}) : super(key: key);

  @override
  State<ClipsArchivesScreen> createState() => _ClipsArchivesScreenState();
}

class _ClipsArchivesScreenState extends State<ClipsArchivesScreen> {
  List<String> _availableDates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvailableDates();
  }

  Future<void> _loadAvailableDates() async {
    print('Loading available clip dates...');
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dailyClipsDir = Directory('${directory.path}/daily_clips');

      if (await dailyClipsDir.exists()) {
        final List<FileSystemEntity> entities = await dailyClipsDir.list().toList();

        List<String> dates = [];
        for (var entity in entities) {
          if (entity is Directory) {
            // Extract date from directory name (YYYY-MM-DD format)
            final dirName = entity.path.split('/').last;
            if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dirName)) {
              dates.add(dirName);
            }
          }
        }

        // Sort dates in descending order (newest first)
        dates.sort((a, b) => b.compareTo(a));

        setState(() {
          _availableDates = dates;
          _isLoading = false;
        });

        print('Found ${dates.length} dates with clips');
      } else {
        setState(() {
          _isLoading = false;
        });
        print('No daily clips directory found');
      }
    } catch (e) {
      print('Error loading available dates: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openDateArchive(String date) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClipsArchiveViewerScreen(date: date),
      ),
    );
  }

  String _formatDateForDisplay(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];

      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  String _getDayOfWeek(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return days[date.weekday - 1];
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clips Archives'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Colors.blue,
        ),
      )
          : _availableDates.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_outlined,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No Clips Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Start posting clips to see them here!',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _availableDates.length,
        itemBuilder: (context, index) {
          final date = _availableDates[index];
          final displayDate = _formatDateForDisplay(date);
          final dayOfWeek = _getDayOfWeek(date);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Icon(
                    Icons.videocam,
                    color: Colors.purple,
                    size: 24,
                  ),
                ),
                title: Text(
                  displayDate,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  dayOfWeek,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                ),
                onTap: () => _openDateArchive(date),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Clips Archive Viewer Screen - Shows clips for a specific date
class ClipsArchiveViewerScreen extends StatefulWidget {
  final String date;

  const ClipsArchiveViewerScreen({Key? key, required this.date}) : super(key: key);

  @override
  State<ClipsArchiveViewerScreen> createState() => _ClipsArchiveViewerScreenState();
}

class _ClipsArchiveViewerScreenState extends State<ClipsArchiveViewerScreen> {
  List<File> _dateClips = [];
  int _currentClipIndex = 0;
  bool _isLoading = true;
  VideoPlayerController? _videoController;
  bool _isInitializingVideo = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadClipsForDate();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadClipsForDate() async {
    print('Loading clips for date: ${widget.date}');
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dateDir = Directory('${directory.path}/daily_clips/${widget.date}');

      if (await dateDir.exists()) {
        final files = await dateDir.list().toList();
        List<File> clips = [];

        for (var file in files) {
          if (file is File && file.path.endsWith('.mp4')) {
            clips.add(file);
          }
        }

        // Sort by filename (which includes timestamp)
        clips.sort((a, b) => a.path.compareTo(b.path));

        setState(() {
          _dateClips = clips;
          _isLoading = false;
        });

        if (clips.isNotEmpty) {
          await _initializeVideo(clips[0]);
        }

        print('Loaded ${clips.length} clips for ${widget.date}');
      } else {
        setState(() {
          _isLoading = false;
        });
        print('No clips directory found for ${widget.date}');
      }
    } catch (e) {
      print('Error loading clips for date: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeVideo(File videoFile) async {
    print('========== ARCHIVE VIDEO INITIALIZATION START ==========');
    print('Video file path: ${videoFile.path}');
    print('Video file exists: ${videoFile.existsSync()}');

    setState(() {
      _isInitializingVideo = true;
      _errorMessage = null;
    });

    try {
      // Dispose of old controller if exists
      if (_videoController != null) {
        await _videoController!.pause();
        await _videoController!.dispose();
        _videoController = null;
      }

      print('Creating VideoPlayerController...');
      _videoController = VideoPlayerController.file(videoFile);

      print('Initializing controller...');
      await _videoController!.initialize();

      print('Controller initialized successfully!');
      print('Video duration: ${_videoController!.value.duration}');
      print('Video size: ${_videoController!.value.size}');

      _videoController!.setLooping(true);
      print('Set looping to true');

      await _videoController!.play();
      print('Video play() called');

      if (mounted) {
        setState(() {
          _isInitializingVideo = false;
        });
      }

      print('Video is now playing');
      print('Is playing: ${_videoController!.value.isPlaying}');
    } catch (e, stackTrace) {
      print('ERROR initializing video: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isInitializingVideo = false;
          _errorMessage = 'Failed to load video: $e';
        });
      }
    }
    print('========== ARCHIVE VIDEO INITIALIZATION END ==========');
  }

  void _navigateClip(int direction) async {
    if (_dateClips.isEmpty) return;

    int newIndex = (_currentClipIndex + direction).clamp(0, _dateClips.length - 1);
    if (newIndex == _currentClipIndex) return;

    setState(() {
      _currentClipIndex = newIndex;
    });

    await _initializeVideo(_dateClips[_currentClipIndex]);
  }

  String _formatDateForDisplay(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];

      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_formatDateForDisplay(widget.date)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      )
          : _dateClips.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_outlined,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No Clips Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      )
          : Stack(
        children: [
          // Full screen video
          Positioned.fill(
            child: _buildVideoDisplay(),
          ),

          // Left arrow
          if (_currentClipIndex > 0)
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _navigateClip(-1),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),

          // Right arrow
          if (_currentClipIndex < _dateClips.length - 1)
            Positioned(
              right: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _navigateClip(1),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),

          // Clip counter
          Positioned(
            top: 20,
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
                  'Clip ${_currentClipIndex + 1} of ${_dateClips.length}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
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

    if (_isInitializingVideo) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Colors.white,
              ),
              SizedBox(height: 16),
              Text(
                'Loading video...',
                style: TextStyle(color: Colors.white, fontSize: 16),
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

    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_file, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Video not ready',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// Embedded Clips Archives View - For Profile Tab
class ClipsArchivesView extends StatefulWidget {
  const ClipsArchivesView({Key? key}) : super(key: key);

  @override
  State<ClipsArchivesView> createState() => _ClipsArchivesViewState();
}

class _ClipsArchivesViewState extends State<ClipsArchivesView> {
  List<String> _availableDates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvailableDates();
  }

  Future<void> _loadAvailableDates() async {
    print('Loading available clip dates...');
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dailyClipsDir = Directory('${directory.path}/daily_clips');

      if (await dailyClipsDir.exists()) {
        final List<FileSystemEntity> entities = await dailyClipsDir.list().toList();

        List<String> dates = [];
        for (var entity in entities) {
          if (entity is Directory) {
            // Extract date from directory name (YYYY-MM-DD format)
            final dirName = entity.path.split('/').last;
            if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dirName)) {
              dates.add(dirName);
            }
          }
        }

        // Sort dates in descending order (newest first)
        dates.sort((a, b) => b.compareTo(a));

        setState(() {
          _availableDates = dates;
          _isLoading = false;
        });

        print('Found ${dates.length} dates with clips');
      } else {
        setState(() {
          _isLoading = false;
        });
        print('No daily clips directory found');
      }
    } catch (e) {
      print('Error loading available dates: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openDateArchive(String date) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClipsArchiveViewerScreen(date: date),
      ),
    );
  }

  String _formatDateForDisplay(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];

      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  String _getDayOfWeek(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return days[date.weekday - 1];
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.purple,
        ),
      );
    }

    if (_availableDates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Clips Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start posting clips to see them here!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _availableDates.length,
      itemBuilder: (context, index) {
        final date = _availableDates[index];
        final displayDate = _formatDateForDisplay(date);
        final dayOfWeek = _getDayOfWeek(date);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Icon(
                  Icons.videocam,
                  color: Colors.purple,
                  size: 24,
                ),
              ),
              title: Text(
                displayDate,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                dayOfWeek,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
              onTap: () => _openDateArchive(date),
            ),
          ),
        );
      },
    );
  }
}