import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class YourDailyActivity extends StatefulWidget {
  const YourDailyActivity({Key? key}) : super(key: key);

  @override
  State<YourDailyActivity> createState() => _YourDailyActivityState();
}

class _YourDailyActivityState extends State<YourDailyActivity> {
  Map<String, List<File>> _photosByDate = {};
  List<String> _sortedDates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllPhotos();
  }

  Future<void> _loadAllPhotos() async {
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

        List<String> sortedDates = photosByDate.keys.toList();
        sortedDates.sort((a, b) => b.compareTo(a)); // Newest first

        setState(() {
          _photosByDate = photosByDate;
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
        child: CircularProgressIndicator(color: Colors.cyan),
      );
    }

    if (_photosByDate.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_outlined, size: 80, color: Colors.grey[400]),
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

    // Grid view of posts - just return GridView directly
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 0,
        mainAxisSpacing: 0,
        childAspectRatio: 1,
      ),
      itemCount: _sortedDates.length,
      itemBuilder: (context, index) {
        final date = _sortedDates[index];
        final photos = _photosByDate[date]!;
        final firstPhoto = photos.first;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DailyPostsViewer(
                  allDates: _sortedDates,
                  photosByDate: _photosByDate,
                  initialDateIndex: index,
                ),
              ),
            );
          },
          child: Image.file(
            firstPhoto,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[200],
                child: Icon(
                  Icons.broken_image,
                  color: Colors.grey[400],
                  size: 40,
                ),
              );
            },
          ),
        );
      },
    );
  }
}


// Viewer that shows posts in scrollable format (free scrolling)
class DailyPostsViewer extends StatefulWidget {
  final List<String> allDates;
  final Map<String, List<File>> photosByDate;
  final int initialDateIndex;

  const DailyPostsViewer({
    Key? key,
    required this.allDates,
    required this.photosByDate,
    required this.initialDateIndex,
  }) : super(key: key);

  @override
  State<DailyPostsViewer> createState() => _DailyPostsViewerState();
}

class _DailyPostsViewerState extends State<DailyPostsViewer> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Scroll to initial post after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialDateIndex > 0) {
        // Estimate height per post and scroll to position
        final estimatedHeight = 500.0; // Approximate height per post
        _scrollController.jumpTo(widget.initialDateIndex * estimatedHeight);
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
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Your Daily',
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
          final photos = widget.photosByDate[date]!;
          final displayDate = _formatDateForDisplay(date);
          final dayOfWeek = _getDayOfWeek(date);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.calendar_today, color: Colors.cyan, size: 20),
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

              // Photo carousel
              SizedBox(
                height: 400,
                child: DailyPhotoCarousel(photos: photos, date: date),
              ),

              // Divider between posts
              if (dateIndex < widget.allDates.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Divider(
                    color: Colors.grey[300],
                    thickness: 1,
                    height: 1,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// Photo carousel for each post
class DailyPhotoCarousel extends StatefulWidget {
  final List<File> photos;
  final String date;

  const DailyPhotoCarousel({
    Key? key,
    required this.photos,
    required this.date,
  }) : super(key: key);

  @override
  State<DailyPhotoCarousel> createState() => _DailyPhotoCarouselState();
}

class _DailyPhotoCarouselState extends State<DailyPhotoCarousel> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) {
        setState(() {
          _currentPage = page;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: widget.photos.length,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  widget.photos[index],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, color: Colors.grey[400], size: 48),
                            const SizedBox(height: 8),
                            Text(
                              'Error loading photo',
                              style: TextStyle(color: Colors.grey[600], fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),

        // Page indicators
        if (widget.photos.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.photos.length, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == index ? 10 : 6,
                  height: _currentPage == index ? 10 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
                        ? Colors.cyan
                        : Colors.white.withOpacity(0.6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        spreadRadius: 1,
                        blurRadius: 2,
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),

        // Photo counter
        Positioned(
          top: 12,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${_currentPage + 1}/${widget.photos.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}