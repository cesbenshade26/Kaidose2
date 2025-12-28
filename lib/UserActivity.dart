import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class UserActivityWidget extends StatefulWidget {
  const UserActivityWidget({Key? key}) : super(key: key);

  @override
  State<UserActivityWidget> createState() => _UserActivityWidgetState();
}

class _UserActivityWidgetState extends State<UserActivityWidget> {
  String _selectedFilter = 'Clips'; // Default to Clips

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Content - full screen
        _buildContent(),

        // Dropdown overlay - positioned on top
        Positioned(
          top: 8,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!.withOpacity(0.5), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  spreadRadius: 0,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: DropdownButton<String>(
              value: _selectedFilter,
              underline: const SizedBox(),
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600], size: 20),
              isDense: true,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
              items: const [
                DropdownMenuItem(
                  value: 'Clips',
                  child: Text('Clips'),
                ),
                DropdownMenuItem(
                  value: 'Daily Posts',
                  child: Text('Daily Posts'),
                ),
                DropdownMenuItem(
                  value: 'Your Daily',
                  child: Text('Your Daily'),
                ),
              ],
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedFilter = newValue;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_selectedFilter) {
      case 'Clips':
        return _buildClipsView();
      case 'Daily Posts':
        return _buildDailyPostsView();
      case 'Your Daily':
        return const YourDailyArchivesView();
      default:
        return _buildClipsView();
    }
  }

  Widget _buildClipsView() {
    // TODO: Replace with actual clips data
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
            'Your video clips will appear here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyPostsView() {
    // TODO: Replace with actual daily posts data
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_camera_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Daily Posts Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your daily photo posts will appear here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

// Your Daily Archives View - Embedded in UserActivity
class YourDailyArchivesView extends StatefulWidget {
  const YourDailyArchivesView({Key? key}) : super(key: key);

  @override
  State<YourDailyArchivesView> createState() => _YourDailyArchivesViewState();
}

class _YourDailyArchivesViewState extends State<YourDailyArchivesView> {
  Map<String, List<File>> _photosByDate = {};
  List<String> _sortedDates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllPhotos();
  }

  Future<void> _loadAllPhotos() async {
    print('Loading all daily photos...');
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dailyPhotosDir = Directory('${directory.path}/daily_photos');

      if (await dailyPhotosDir.exists()) {
        final List<FileSystemEntity> entities = await dailyPhotosDir.list().toList();
        Map<String, List<File>> photosByDate = {};

        for (var entity in entities) {
          if (entity is Directory) {
            final dirName = entity.path.split('/').last;
            if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dirName)) {
              // Load photos for this date
              final files = await entity.list().toList();
              List<File> photos = [];

              for (var file in files) {
                if (file is File && file.path.endsWith('.jpg')) {
                  photos.add(file);
                }
              }

              if (photos.isNotEmpty) {
                photos.sort((a, b) => a.path.compareTo(b.path));
                photosByDate[dirName] = photos;
              }
            }
          }
        }

        // Sort dates in descending order (newest first)
        List<String> sortedDates = photosByDate.keys.toList();
        sortedDates.sort((a, b) => b.compareTo(a));

        setState(() {
          _photosByDate = photosByDate;
          _sortedDates = sortedDates;
          _isLoading = false;
        });

        print('Loaded photos for ${sortedDates.length} dates');
      } else {
        setState(() {
          _isLoading = false;
        });
        print('No daily photos directory found');
      }
    } catch (e) {
      print('Error loading daily photos: $e');
      setState(() {
        _isLoading = false;
      });
    }
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

  void _openPhotoViewer(String date, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DailyArchiveViewerScreen(
          date: date,
          initialPhotoIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.cyan,
        ),
      );
    }

    if (_photosByDate.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_camera_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Daily Photos Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start taking daily photos to see them here!',
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
      padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 16),
      itemCount: _sortedDates.length,
      itemBuilder: (context, dateIndex) {
        final date = _sortedDates[dateIndex];
        final photos = _photosByDate[date]!;
        final displayDate = _formatDateForDisplay(date);
        final dayOfWeek = _getDayOfWeek(date);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.calendar_today,
                      color: Colors.cyan,
                      size: 20,
                    ),
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
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        dayOfWeek,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${photos.length} ${photos.length == 1 ? 'photo' : 'photos'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.cyan,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Photos grid for this date
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: photos.length,
              itemBuilder: (context, photoIndex) {
                return GestureDetector(
                  onTap: () => _openPhotoViewer(date, photoIndex),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.file(
                        photos[photoIndex],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[200],
                            child: Icon(
                              Icons.error_outline,
                              color: Colors.grey[400],
                              size: 32,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),

            // Divider between dates
            if (dateIndex < _sortedDates.length - 1)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Divider(
                  color: Colors.grey[300],
                  thickness: 1,
                ),
              ),
          ],
        );
      },
    );
  }
}

// Archive Viewer Screen - Shows photos for a specific date
class DailyArchiveViewerScreen extends StatefulWidget {
  final String date;
  final int initialPhotoIndex;

  const DailyArchiveViewerScreen({
    Key? key,
    required this.date,
    this.initialPhotoIndex = 0,
  }) : super(key: key);

  @override
  State<DailyArchiveViewerScreen> createState() => _DailyArchiveViewerScreenState();
}

class _DailyArchiveViewerScreenState extends State<DailyArchiveViewerScreen> with TickerProviderStateMixin {
  List<File> _datePhotos = [];
  late int _currentPhotoIndex;
  bool _isLoading = true;
  bool _isAnimating = false;

  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _currentPhotoIndex = widget.initialPhotoIndex;

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    _loadPhotosForDate();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadPhotosForDate() async {
    print('Loading photos for date: ${widget.date}');
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dateDir = Directory('${directory.path}/daily_photos/${widget.date}');

      if (await dateDir.exists()) {
        final files = await dateDir.list().toList();
        List<File> photos = [];

        for (var file in files) {
          if (file is File && file.path.endsWith('.jpg')) {
            photos.add(file);
          }
        }

        // Sort by filename (which includes timestamp)
        photos.sort((a, b) => a.path.compareTo(b.path));

        setState(() {
          _datePhotos = photos;
          _isLoading = false;
        });

        print('Loaded ${photos.length} photos for ${widget.date}');
      } else {
        setState(() {
          _isLoading = false;
        });
        print('No photos directory found for ${widget.date}');
      }
    } catch (e) {
      print('Error loading photos for date: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigatePhoto(int direction) async {
    if (_datePhotos.isEmpty || _isAnimating) return;

    int newIndex = (_currentPhotoIndex + direction).clamp(0, _datePhotos.length - 1);
    if (newIndex == _currentPhotoIndex) return;

    setState(() {
      _isAnimating = true;
    });

    _slideController.reset();

    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: direction > 0 ? 1.0 : -1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    await _slideController.forward();

    setState(() {
      _currentPhotoIndex = newIndex;
      _isAnimating = false;
    });

    _slideController.reset();
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_formatDateForDisplay(widget.date)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Colors.cyan,
        ),
      )
          : _datePhotos.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Photos Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      )
          : Column(
        children: [
          // Photo counter
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${_currentPhotoIndex + 1} of ${_datePhotos.length}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),

          // Photo display with sliding animation
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[300]!, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    AnimatedBuilder(
                      animation: _slideAnimation,
                      builder: (context, child) {
                        return Stack(
                          children: [
                            // Current photo
                            Transform.translate(
                              offset: Offset(-_slideAnimation.value * MediaQuery.of(context).size.width, 0),
                              child: Image.file(
                                _datePhotos[_currentPhotoIndex],
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),

                            // Next photo sliding in
                            if (_isAnimating && _slideAnimation.value > 0 && _currentPhotoIndex + 1 < _datePhotos.length) ...[
                              Transform.translate(
                                offset: Offset(
                                  MediaQuery.of(context).size.width - (_slideAnimation.value * MediaQuery.of(context).size.width),
                                  0,
                                ),
                                child: Image.file(
                                  _datePhotos[_currentPhotoIndex + 1],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                            ],

                            // Previous photo sliding in
                            if (_isAnimating && _slideAnimation.value < 0 && _currentPhotoIndex - 1 >= 0) ...[
                              Transform.translate(
                                offset: Offset(
                                  -MediaQuery.of(context).size.width - (_slideAnimation.value * MediaQuery.of(context).size.width),
                                  0,
                                ),
                                child: Image.file(
                                  _datePhotos[_currentPhotoIndex - 1],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),

                    // Left arrow
                    if (_currentPhotoIndex > 0 && !_isAnimating)
                      Positioned(
                        left: 10,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () => _navigatePhoto(-1),
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
                    if (_currentPhotoIndex < _datePhotos.length - 1 && !_isAnimating)
                      Positioned(
                        right: 10,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () => _navigatePhoto(1),
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
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}