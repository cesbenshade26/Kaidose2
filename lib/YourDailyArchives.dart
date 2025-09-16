import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'DailyPhotoTracker.dart'; // Import for accessing daily photos

class YourDailyArchivesScreen extends StatefulWidget {
  const YourDailyArchivesScreen({Key? key}) : super(key: key);

  @override
  State<YourDailyArchivesScreen> createState() => _YourDailyArchivesScreenState();
}

class _YourDailyArchivesScreenState extends State<YourDailyArchivesScreen> {
  List<String> _availableDates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvailableDates();
  }

  Future<void> _loadAvailableDates() async {
    print('Loading available dates...');
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dailyPhotosDir = Directory('${directory.path}/daily_photos');

      if (await dailyPhotosDir.exists()) {
        final List<FileSystemEntity> entities = await dailyPhotosDir.list().toList();

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

        print('Found ${dates.length} dates with daily photos');
      } else {
        setState(() {
          _isLoading = false;
        });
        print('No daily photos directory found');
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
        builder: (context) => DailyArchiveViewerScreen(date: date),
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
        title: const Text('Your Daily Archives'),
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
              Icons.photo_camera_outlined,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No Daily Photos Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Start taking daily photos to see them here!',
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
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    color: Colors.blue,
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

// Archive Viewer Screen - Shows photos for a specific date
class DailyArchiveViewerScreen extends StatefulWidget {
  final String date;

  const DailyArchiveViewerScreen({Key? key, required this.date}) : super(key: key);

  @override
  State<DailyArchiveViewerScreen> createState() => _DailyArchiveViewerScreenState();
}

class _DailyArchiveViewerScreenState extends State<DailyArchiveViewerScreen> with TickerProviderStateMixin {
  List<File> _datePhotos = [];
  int _currentPhotoIndex = 0;
  bool _isLoading = true;
  bool _isAnimating = false;

  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();

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
      appBar: AppBar(
        title: Text(_formatDateForDisplay(widget.date)),
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
          : _datePhotos.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_outlined,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No Photos Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
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
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
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