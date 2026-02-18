import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class ClipsActivity extends StatefulWidget {
  const ClipsActivity({Key? key}) : super(key: key);

  @override
  State<ClipsActivity> createState() => _ClipsActivityState();
}

class _ClipsActivityState extends State<ClipsActivity> {
  Map<String, List<File>> _clipsByDate = {};
  List<String> _sortedDates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllClips();
  }

  Future<void> _loadAllClips() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dailyClipsDir = Directory('${directory.path}/daily_clips');

      if (await dailyClipsDir.exists()) {
        final List<FileSystemEntity> entities = await dailyClipsDir.list().toList();
        Map<String, List<File>> clipsByDate = {};

        for (var entity in entities) {
          if (entity is Directory) {
            final dirName = entity.path.split('/').last;
            if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dirName)) {
              final files = await entity.list().toList();
              List<File> clips = [];

              for (var file in files) {
                if (file is File && file.path.endsWith('.mp4')) {
                  clips.add(file);
                }
              }

              if (clips.isNotEmpty) {
                clips.sort((a, b) => a.path.compareTo(b.path));
                clipsByDate[dirName] = clips;
              }
            }
          }
        }

        List<String> sortedDates = clipsByDate.keys.toList();
        sortedDates.sort((a, b) => b.compareTo(a)); // Newest first

        setState(() {
          _clipsByDate = clipsByDate;
          _sortedDates = sortedDates;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.purple),
      );
    }

    if (_clipsByDate.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_outlined, size: 80, color: Colors.grey[400]),
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

    // Grid view of clips - just return GridView directly
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 0,
        mainAxisSpacing: 0,
        childAspectRatio: 0.56,  // 9:16 aspect ratio for vertical videos
      ),
      itemCount: _sortedDates.length,
      itemBuilder: (context, index) {
        final date = _sortedDates[index];
        final clips = _clipsByDate[date]!;
        final firstClip = clips.first;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ClipsViewer(
                  allDates: _sortedDates,
                  clipsByDate: _clipsByDate,
                  initialDateIndex: index,
                ),
              ),
            );
          },
          child: ClipThumbnail(videoFile: firstClip),
        );
      },
    );
  }
}

// Thumbnail widget that shows first frame of video
class ClipThumbnail extends StatefulWidget {
  final File videoFile;

  const ClipThumbnail({Key? key, required this.videoFile}) : super(key: key);

  @override
  State<ClipThumbnail> createState() => _ClipThumbnailState();
}

class _ClipThumbnailState extends State<ClipThumbnail> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeThumbnail();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeThumbnail() async {
    try {
      _controller = VideoPlayerController.file(widget.videoFile);
      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Error loading thumbnail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialized && _controller != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      );
    }

    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Icon(
          Icons.videocam,
          color: Colors.grey[700],
          size: 40,
        ),
      ),
    );
  }
}

// Viewer that shows clips in scrollable format (free scrolling)
class ClipsViewer extends StatefulWidget {
  final List<String> allDates;
  final Map<String, List<File>> clipsByDate;
  final int initialDateIndex;

  const ClipsViewer({
    Key? key,
    required this.allDates,
    required this.clipsByDate,
    required this.initialDateIndex,
  }) : super(key: key);

  @override
  State<ClipsViewer> createState() => _ClipsViewerState();
}

class _ClipsViewerState extends State<ClipsViewer> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialDateIndex > 0 && _scrollController.hasClients) {
        _scrollController.jumpTo(widget.initialDateIndex * 500.0);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Clips',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: widget.allDates.length,
        itemBuilder: (context, dateIndex) {
          final date = widget.allDates[dateIndex];
          final clips = widget.clipsByDate[date]!;
          final displayDate = _formatDateForDisplay(date);
          final dayOfWeek = _getDayOfWeek(date);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.videocam, color: Colors.purple, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayDate,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          dayOfWeek,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${clips.length} ${clips.length == 1 ? 'clip' : 'clips'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 400,
                child: DailyClipsCarousel(clips: clips),
              ),
              if (dateIndex < widget.allDates.length - 1)
                Divider(color: Colors.grey[300], thickness: 1, height: 32),
            ],
          );
        },
      ),
    );
  }
}

// Horizontal clips carousel for each date with auto-play
class DailyClipsCarousel extends StatefulWidget {
  final List<File> clips;

  const DailyClipsCarousel({
    Key? key,
    required this.clips,
  }) : super(key: key);

  @override
  State<DailyClipsCarousel> createState() => _DailyClipsCarouselState();
}

class _DailyClipsCarouselState extends State<DailyClipsCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _initVideo(0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initVideo(int index) async {
    if (index >= widget.clips.length) return;

    // Dispose previous controller
    final old = _controller;
    _controller = null;
    await old?.dispose();

    if (!mounted) return;

    final controller = VideoPlayerController.file(widget.clips[index]);
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
    } catch (e) {
      controller.dispose();
      print('Error initializing video: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: widget.clips.length,
          onPageChanged: (index) {
            if (!mounted) return;
            setState(() => _currentPage = index);
            _initVideo(index);
          },
          itemBuilder: (context, index) {
            // Only show player for current page
            if (index == _currentPage && _controller != null && _controller!.value.isInitialized) {
              return FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              );
            }
            return Container(
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(color: Colors.purple),
              ),
            );
          },
        ),

        // Page dots
        if (widget.clips.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.clips.length, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == index ? 10 : 6,
                  height: _currentPage == index ? 10 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index ? Colors.purple : Colors.grey[400],
                  ),
                );
              }),
            ),
          ),

        // Counter
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_currentPage + 1}/${widget.clips.length}',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}