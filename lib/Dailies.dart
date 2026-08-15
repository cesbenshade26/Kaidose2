import 'package:flutter/material.dart';
import 'Search.dart';
import 'DailyPhotoManager.dart';
import 'DailyPhotoTracker.dart';
import 'ProfilePicManager.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'ManageDaily.dart';
import 'UponOpeningDaily.dart';
import 'InsideDaily.dart';
import 'SkipCount.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'FriendStoryBar.dart';


class DailiesWidget extends StatefulWidget {
  final Function(int)? onNavigateToTab;

  const DailiesWidget({Key? key, this.onNavigateToTab}) : super(key: key);

  @override
  State<DailiesWidget> createState() => _DailiesWidgetState();
}

class _DailiesWidgetState extends State<DailiesWidget> with WidgetsBindingObserver, TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  List<File> _todaysPhotos = [];
  int _currentPhotoIndex = 0;
  bool _isLoading = true;
  bool _hasViewedAllPhotos = false;
  bool _isAnimating = false;
  File? _profilePic;
  Set<String> _viewedPhotosPaths = {};

  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  VoidCallback? _dailyPhotoListener;
  VoidCallback? _trackerListener;
  VoidCallback? _profilePicListener;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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

    _initializeSystems();

    _profilePic = ProfilePicManager.globalProfilePic;

    _dailyPhotoListener = () {
      if (mounted) {
        _loadPhotos();
      }
    };

    _trackerListener = () {
      if (mounted) {
        _loadPhotos();
      }
    };

    _profilePicListener = () {
      if (mounted) {
        setState(() {
          _profilePic = ProfilePicManager.globalProfilePic;
        });
      }
    };


    DailyPhotoManager.addListener(_dailyPhotoListener!);
    DailyPhotoTracker.addListener(_trackerListener!);
    ProfilePicManager.addListener(_profilePicListener!);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _slideController.dispose();
    if (_dailyPhotoListener != null) {
      DailyPhotoManager.removeListener(_dailyPhotoListener!);
    }
    if (_trackerListener != null) {
      DailyPhotoTracker.removeListener(_trackerListener!);
    }
    if (_profilePicListener != null) {
      ProfilePicManager.removeListener(_profilePicListener!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForNewDay();
      SkipCount.checkAndResetIfNewWeek();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPhotos();
  }

  Future<void> _initializeSystems() async {
    await DailyPhotoTracker.initialize();
    await DailyPhotoManager.loadDailyPhotoFromStorage();
    await ProfilePicManager.loadProfilePicFromStorage();
    await DailyList.loadFromStorage();
    if (mounted) {
      setState(() {
        _profilePic = ProfilePicManager.globalProfilePic;
      });
    }
    _loadPhotos();
  }

  Future<void> _checkForNewDay() async {
    await DailyPhotoTracker.checkAndResetIfNewDay();
    _loadPhotos();
  }

  void _loadPhotos() {
    setState(() {
      _isLoading = true;
    });

    List<File> previousPhotos = List.from(_todaysPhotos);
    _todaysPhotos = DailyPhotoTracker.todaysPhotos;

    if (_todaysPhotos.isNotEmpty) {
      _currentPhotoIndex = 0;
    }

    if (_todaysPhotos.length != previousPhotos.length) {
      _checkViewingStatus();
    }

    setState(() {
      _isLoading = false;
    });
  }


  void _checkViewingStatus() {
    int viewedCount = 0;
    for (File photo in _todaysPhotos) {
      if (_viewedPhotosPaths.contains(photo.path)) {
        viewedCount++;
      }
    }
    _hasViewedAllPhotos = viewedCount == _todaysPhotos.length && _todaysPhotos.isNotEmpty;
  }

  void _navigatePhoto(int direction) async {
    if (_todaysPhotos.isEmpty || _isAnimating) return;

    int newIndex = (_currentPhotoIndex + direction).clamp(0, _todaysPhotos.length - 1);
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

      if (_todaysPhotos.isNotEmpty && _currentPhotoIndex < _todaysPhotos.length) {
        _viewedPhotosPaths.add(_todaysPhotos[_currentPhotoIndex].path);
        _checkViewingStatus();
      }
    });

    _slideController.reset();
  }

  void _openPhotoCarousel() {
    if (_todaysPhotos.isNotEmpty) {
      // Mark first photo as viewed
      setState(() {
        _viewedPhotosPaths.add(_todaysPhotos[0].path);
        _checkViewingStatus();
      });
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OwnStoryViewer(photos: _todaysPhotos),
        ),
      ).then((_) {
        // Mark all as viewed once they close the viewer
        setState(() {
          for (final photo in _todaysPhotos) {
            _viewedPhotosPaths.add(photo.path);
          }
          _checkViewingStatus();
        });
      });
    }
  }


  void _navigateToAddDaily() {
    if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(3);
    }
  }

  bool _isUserCreatedDaily(DailyData daily) {
    return true;
  }
  TextStyle _getFontForDaily(DailyData daily) {
    final fontFamily = daily.titleFont ?? 'Default';

    switch (fontFamily) {
      case 'Roboto':
        return GoogleFonts.roboto();
      case 'Playfair Display':
        return GoogleFonts.playfairDisplay();
      case 'Pacifico':
        return GoogleFonts.pacifico();
      case 'Bebas Neue':
        return GoogleFonts.bebasNeue();
      case 'Caveat':
        return GoogleFonts.caveat();
      case 'Permanent Marker':
        return GoogleFonts.permanentMarker();
      case 'Righteous':
        return GoogleFonts.righteous();
      case 'Lobster':
        return GoogleFonts.lobster();
      case 'Dancing Script':
        return GoogleFonts.dancingScript();
      case 'Bangers':
        return GoogleFonts.bangers();
      default:
        return const TextStyle();
    }
  }

  Widget _buildDailyCard(DailyData daily, Set<String> viewedSet) {
    bool isUserCreated = _isUserCreatedDaily(daily);
    bool hasBeenViewed = viewedSet.contains(daily.id);
    final dailyColor = Color(daily.iconColor ?? 0xFF00BCD4);

    return GestureDetector(
      onTap: () async {
        bool wasUnviewed = !hasBeenViewed;

        if (wasUnviewed && daily.dailyEntryPrompt.isNotEmpty) {
          // Mark as viewed AFTER showing the prompt (moved inside UponOpeningDaily)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UponOpeningDaily(
                daily: daily,
              ),
            ),
          );
        } else {
          await DailyList.markAsViewed(daily.id);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => InsideDaily(daily: daily),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: !hasBeenViewed ? dailyColor.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: !hasBeenViewed
                ? dailyColor
                : (daily.isPinned ? dailyColor : Colors.grey[300]!),
            width: !hasBeenViewed ? 2 : (daily.isPinned ? 2 : 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Color(daily.iconColor ?? 0xFF00BCD4).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: daily.customIconPath != null && File(daily.customIconPath!).existsSync()
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(daily.customIconPath!),
                  fit: BoxFit.cover,
                ),
              )
                  : Icon(
                daily.icon,
                color: Color(daily.iconColor ?? 0xFF00BCD4),
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          daily.title,
                          style: _getFontForDaily(daily).copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (daily.isPinned)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.cyan,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.push_pin,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    daily.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Active Friends: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(daily.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: Colors.grey[600],
                size: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (value) {
                if (value == 'pin') {
                  DailyList.togglePin(daily.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        daily.isPinned ? '${daily.title} unpinned!' : '${daily.title} pinned!',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else if (value == 'delete') {
                  _showDeleteConfirmation(daily);
                } else if (value == 'manage') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManageDailyScreen(daily: daily),
                    ),
                  );
                }
              },
              itemBuilder: (BuildContext context) {
                List<PopupMenuEntry<String>> menuItems = [
                  PopupMenuItem<String>(
                    value: 'pin',
                    child: Row(
                      children: [
                        Icon(
                          daily.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                          size: 20,
                          color: Colors.black87,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          daily.isPinned ? 'Unpin' : 'Pin',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ];

                if (isUserCreated) {
                  menuItems.add(
                    const PopupMenuItem<String>(
                      value: 'manage',
                      child: Row(
                        children: [
                          Icon(Icons.settings, size: 20, color: Colors.black87),
                          SizedBox(width: 12),
                          Text(
                            'Manage',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                menuItems.add(
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        SizedBox(width: 12),
                        Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                return menuItems;
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(DailyData daily) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Daily?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${daily.title}"? This action cannot be undone.',
          style: const TextStyle(
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              DailyList.deleteDaily(daily.id);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${daily.title} deleted'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    }
  }



  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Container(
            color: Colors.white,
            width: double.infinity,
            height: double.infinity,
            child: _isLoading
                ? const Center(
              child: CircularProgressIndicator(
                color: Colors.cyan,
              ),
            )
                : StreamBuilder<List<DailyData>>(
              stream: DailyList.getDailiesStream(),
              builder: (context, dailiesSnapshot) {
                if (dailiesSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.cyan),
                  );
                }

                if (dailiesSnapshot.hasError) {
                  return Center(
                    child: Text('Error: ${dailiesSnapshot.error}'),
                  );
                }

                final publishedDailies = dailiesSnapshot.data ?? [];

                return StreamBuilder<Set<String>>(
                  stream: DailyList.getViewedDailiesStream(),
                  builder: (context, viewedSnapshot) {
                    final viewedToday = viewedSnapshot.data ?? {};

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 60, bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Dailies',
                                style: TextStyle(
                                  fontFamily: 'Slackey',
                                  fontSize: 32,
                                  color: Colors.cyan,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.search, color: Colors.black, size: 28),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const SearchScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        StoryBar(
                          onTapOwnStory: _openPhotoCarousel,
                          hasOwnPhotosToday: _todaysPhotos.isNotEmpty,
                          hasViewedAllOwnPhotos: _hasViewedAllPhotos,
                        ),
                        const SizedBox(height: 24),
                        if (publishedDailies.isEmpty && _todaysPhotos.isEmpty)
                          Expanded(
                            child: Center(
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
                                    'No Dailies Yet!',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Start your day by posting your first daily',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),
                                  GestureDetector(
                                    onTap: _navigateToAddDaily,
                                    child: Container(
                                      width: 70,
                                      height: 70,
                                      decoration: BoxDecoration(
                                        color: Colors.cyan,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.cyan.withOpacity(0.4),
                                            spreadRadius: 2,
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.add,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Add a Daily!',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: publishedDailies.length,
                              itemBuilder: (context, index) {
                                return _buildDailyCard(publishedDailies[index], viewedToday);
                              },
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DefaultProfilePic extends StatelessWidget {
  final double size;
  final double borderWidth;

  const DefaultProfilePic({
    Key? key,
    this.size = 160,
    this.borderWidth = 3,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
        border: Border.all(
          color: Colors.grey[400]!,
          width: borderWidth,
        ),
      ),
      child: ClipOval(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: size * 0.1875,
              child: Container(
                width: size * 0.3125,
                height: size * 0.3125,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[600],
                ),
              ),
            ),
            Positioned(
              bottom: -size * 0.125,
              child: Container(
                width: size * 0.875,
                height: size * 0.5,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(size * 0.4375),
                    topRight: Radius.circular(size * 0.4375),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}