import 'package:flutter/material.dart';
import 'Search.dart'; // Import the Search screen
import 'DailyPhotoManager.dart'; // Import the DailyPhotoManager
import 'DailyPhotoTracker.dart'; // Import the new DailyPhotoTracker
import 'ProfilePicManager.dart'; // Import ProfilePicManager
import 'dart:io';

// Dailies Widget
class DailiesWidget extends StatefulWidget {
  final Function(int)? onNavigateToTab; // Add callback for navigation

  const DailiesWidget({Key? key, this.onNavigateToTab}) : super(key: key);

  @override
  State<DailiesWidget> createState() => _DailiesWidgetState();
}

class _DailiesWidgetState extends State<DailiesWidget> with WidgetsBindingObserver, TickerProviderStateMixin {
  List<File> _todaysPhotos = [];
  int _currentPhotoIndex = 0;
  bool _isLoading = true;
  bool _showPhotoCarousel = false;
  bool _hasViewedAllPhotos = false;
  bool _isAnimating = false;
  File? _profilePic;
  Set<String> _viewedPhotosPaths = {}; // Track which specific photos have been viewed

  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  VoidCallback? _dailyPhotoListener;
  VoidCallback? _trackerListener;
  VoidCallback? _profilePicListener;

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

    _initializeBothSystems();

    _profilePic = ProfilePicManager.globalProfilePic;

    _dailyPhotoListener = () {
      print('DailiesWidget: Daily photo changed!');
      if (mounted) {
        _loadPhotos();
      }
    };

    _trackerListener = () {
      print('DailiesWidget: Photo tracker changed!');
      if (mounted) {
        _loadPhotos();
      }
    };

    _profilePicListener = () {
      print('DailiesWidget: Profile pic changed!');
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
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPhotos();
  }

  Future<void> _initializeBothSystems() async {
    await DailyPhotoTracker.initialize();
    await DailyPhotoManager.loadDailyPhotoFromStorage();
    await ProfilePicManager.loadProfilePicFromStorage();
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
    print('Loading photos for Dailies...');

    setState(() {
      _isLoading = true;
    });

    List<File> previousPhotos = List.from(_todaysPhotos);
    _todaysPhotos = DailyPhotoTracker.todaysPhotos;

    if (_todaysPhotos.isNotEmpty) {
      _currentPhotoIndex = 0;
    }

    // Check if there are new photos since last load
    if (_todaysPhotos.length != previousPhotos.length) {
      // New photos added, need to check viewing status
      _checkViewingStatus();
    }

    setState(() {
      _isLoading = false;
    });

    print('Loaded ${_todaysPhotos.length} photos for Dailies display');
  }

  void _checkViewingStatus() {
    // Count how many of today's photos have been viewed
    int viewedCount = 0;
    for (File photo in _todaysPhotos) {
      if (_viewedPhotosPaths.contains(photo.path)) {
        viewedCount++;
      }
    }

    // Update hasViewedAllPhotos based on whether ALL photos have been viewed
    _hasViewedAllPhotos = viewedCount == _todaysPhotos.length && _todaysPhotos.isNotEmpty;

    print('Viewed $viewedCount of ${_todaysPhotos.length} photos. All viewed: $_hasViewedAllPhotos');
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

      // Mark current photo as viewed
      if (_todaysPhotos.isNotEmpty && _currentPhotoIndex < _todaysPhotos.length) {
        _viewedPhotosPaths.add(_todaysPhotos[_currentPhotoIndex].path);
        _checkViewingStatus();
      }
    });

    _slideController.reset();
  }

  void _openPhotoCarousel() {
    if (_todaysPhotos.isNotEmpty) {
      setState(() {
        _showPhotoCarousel = true;
        _currentPhotoIndex = 0;

        // Mark the first photo as viewed when opening carousel
        _viewedPhotosPaths.add(_todaysPhotos[0].path);
        _checkViewingStatus();
      });
    }
  }

  void _closePhotoCarousel() {
    setState(() {
      _showPhotoCarousel = false;
    });
  }

  void _navigateToAddDaily() {
    // Navigate to Add tab (index 3) in Home
    if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(3);
    }
  }

  Widget _buildProfilePicButton() {
    bool hasPhotos = _todaysPhotos.isNotEmpty;
    bool showCyanRing = hasPhotos && !_hasViewedAllPhotos;

    return GestureDetector(
      onTap: hasPhotos ? _openPhotoCarousel : null,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: showCyanRing ? Colors.cyan : Colors.grey[400]!,
            width: showCyanRing ? 4 : 3,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[300],
          ),
          child: ClipOval(
            child: _profilePic != null && _profilePic!.existsSync()
                ? Image.file(
              _profilePic!,
              fit: BoxFit.cover,
              width: 112,
              height: 112,
              key: ValueKey(_profilePic!.path + _profilePic!.lastModifiedSync().toString()),
              errorBuilder: (context, error, stackTrace) {
                print('Error loading profile image: $error');
                return const DefaultProfilePic(size: 112, borderWidth: 0);
              },
            )
                : const DefaultProfilePic(size: 112, borderWidth: 0),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoCarousel() {
    return Container(
      color: Colors.black.withOpacity(0.9),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: double.infinity,
              height: 400,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AnimatedBuilder(
                  animation: _slideAnimation,
                  builder: (context, child) {
                    return Stack(
                      children: [
                        Transform.translate(
                          offset: Offset(-_slideAnimation.value * MediaQuery.of(context).size.width, 0),
                          child: Container(
                            width: double.infinity,
                            height: double.infinity,
                            child: Image.file(
                              _todaysPhotos[_currentPhotoIndex],
                              fit: BoxFit.cover,
                              key: ValueKey('current_${_todaysPhotos[_currentPhotoIndex].path}'),
                              errorBuilder: (context, error, stackTrace) {
                                print('Error displaying daily photo: $error');
                                return Container(
                                  color: Colors.grey[800],
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          size: 48,
                                          color: Colors.grey[400],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Error loading photo',
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        if (_isAnimating && _slideAnimation.value > 0) ...[
                          Transform.translate(
                            offset: Offset(
                              MediaQuery.of(context).size.width - (_slideAnimation.value * MediaQuery.of(context).size.width),
                              0,
                            ),
                            child: Container(
                              width: double.infinity,
                              height: double.infinity,
                              child: _currentPhotoIndex + 1 < _todaysPhotos.length
                                  ? Image.file(
                                _todaysPhotos[_currentPhotoIndex + 1],
                                fit: BoxFit.cover,
                                key: ValueKey('next_${_todaysPhotos[_currentPhotoIndex + 1].path}'),
                              )
                                  : Container(color: Colors.black),
                            ),
                          ),
                        ],

                        if (_isAnimating && _slideAnimation.value < 0) ...[
                          Transform.translate(
                            offset: Offset(
                              -MediaQuery.of(context).size.width - (_slideAnimation.value * MediaQuery.of(context).size.width),
                              0,
                            ),
                            child: Container(
                              width: double.infinity,
                              height: double.infinity,
                              child: _currentPhotoIndex - 1 >= 0
                                  ? Image.file(
                                _todaysPhotos[_currentPhotoIndex - 1],
                                fit: BoxFit.cover,
                                key: ValueKey('prev_${_todaysPhotos[_currentPhotoIndex - 1].path}'),
                              )
                                  : Container(color: Colors.black),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

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
                      color: Colors.white.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.black,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),

          if (_currentPhotoIndex < _todaysPhotos.length - 1 && !_isAnimating)
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
                      color: Colors.white.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.black,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            top: 60,
            right: 20,
            child: GestureDetector(
              onTap: _closePhotoCarousel,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.black,
                  size: 24,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 100,
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
                  '${_currentPhotoIndex + 1} of ${_todaysPhotos.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          if (_todaysPhotos.length > 1)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_todaysPhotos.length, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: index == _currentPhotoIndex ? 12 : 8,
                    height: index == _currentPhotoIndex ? 12 : 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == _currentPhotoIndex
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                color: Colors.blue,
              ),
            )
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top section with title and search icon
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

                // Profile picture below title (left aligned like Instagram)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProfilePicButton(),
                      const SizedBox(height: 8),
                      // "Your story" text below profile pic
                      const Text(
                        'Your story',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Empty state with Add Daily button
                if (_todaysPhotos.isEmpty)
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
                            'Start your day by posting your first daily photo',
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
                  const Expanded(child: SizedBox()),
              ],
            ),
          ),

          if (_showPhotoCarousel && _todaysPhotos.isNotEmpty)
            _buildPhotoCarousel(),
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