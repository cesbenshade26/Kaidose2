import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'VideoClipPlayer.dart';

class ClipsActivity extends StatefulWidget {
  const ClipsActivity({Key? key}) : super(key: key);

  @override
  State<ClipsActivity> createState() => _ClipsActivityState();
}

class _ClipsActivityState extends State<ClipsActivity> {
  Map<String, List<File>> _clipsByDate = {};
  List<String> _sortedDates = [];
  bool _isLoading = true;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadAllClips();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.cyan,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
    });
  }

  List<String> _getFilteredDates() {
    if (_selectedDate == null) return _sortedDates;

    final dateStr = _selectedDate!.toIso8601String().split('T')[0];
    return _sortedDates.where((date) => date == dateStr).toList();
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
        sortedDates.sort((a, b) => b.compareTo(a));

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
      print('Error loading clips: $e');
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

    final filteredDates = _getFilteredDates();

    return Stack(
      children: [
        GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
            childAspectRatio: 0.56,
          ),
          itemCount: filteredDates.length,
          itemBuilder: (context, index) {
            final date = filteredDates[index];
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
                      initialDateIndex: _sortedDates.indexOf(date),
                    ),
                  ),
                );
              },
              child: ClipThumbnail(videoFile: firstClip),
            );
          },
        ),

        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_selectedDate != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: _clearDateFilter,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.clear,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: _selectDate,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.95),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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

  Future<void> _initializeThumbnail() async {
    _controller = VideoPlayerController.file(widget.videoFile);
    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing thumbnail: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: CircularProgressIndicator(color: Colors.purple, strokeWidth: 2),
        ),
      );
    }

    return Container(
      color: Colors.grey[200],
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}

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
  late PageController _pageController;
  int _currentClipIndex = 0;
  List<_ClipItem> _allClips = [];

  @override
  void initState() {
    super.initState();

    for (final date in widget.allDates) {
      final clips = widget.clipsByDate[date]!;
      for (int i = 0; i < clips.length; i++) {
        _allClips.add(_ClipItem(
          file: clips[i],
          date: date,
          clipNumber: i + 1,
          totalClips: clips.length,
        ));
      }
    }

    int initialIndex = 0;
    int clipsSoFar = 0;
    for (int i = 0; i < widget.initialDateIndex && i < widget.allDates.length; i++) {
      clipsSoFar += widget.clipsByDate[widget.allDates[i]]!.length;
    }
    initialIndex = clipsSoFar;

    _currentClipIndex = initialIndex;
    _pageController = PageController(initialPage: initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
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
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: (index) {
                setState(() {
                  _currentClipIndex = index;
                });
              },
              itemCount: _allClips.length,
              itemBuilder: (context, index) {
                final clip = _allClips[index];
                final isActive = index == _currentClipIndex;

                if (isActive) {
                  return VideoClipPlayer(
                    key: ValueKey('clip_$index'),
                    videoFile: clip.file,
                    autoPlay: true,
                    looping: true,
                    fit: BoxFit.cover,
                  );
                } else {
                  return Container(color: Colors.black);
                }
              },
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 16,
            right: 16,
            child: _allClips.isNotEmpty
                ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.videocam, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDateForDisplay(_allClips[_currentClipIndex].date),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          _getDayOfWeek(_allClips[_currentClipIndex].date),
                          style: const TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_allClips[_currentClipIndex].clipNumber}/${_allClips[_currentClipIndex].totalClips}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClipItem {
  final File file;
  final String date;
  final int clipNumber;
  final int totalClips;

  _ClipItem({
    required this.file,
    required this.date,
    required this.clipNumber,
    required this.totalClips,
  });
}