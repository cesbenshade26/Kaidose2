import 'package:flutter/material.dart';
import 'Add.dart';
import 'KaidoseBrand.dart';
import 'NotificationBell.dart';
import 'AddSheet.dart';
import 'NewDaily.dart';
import 'YourDailyBubbles.dart';
import 'DailyPhotoManager.dart';
import 'DailyPhotoTracker.dart';
import 'DailyVideoTracker.dart';
import 'StoryMediaItem.dart';
import 'ProfilePicManager.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'DailyCover.dart';
import 'DailyForYou.dart';
import 'SkipCount.dart';
import 'dart:io';
import 'FriendStoryBar.dart';
import 'CircleRevealTransition.dart';


class DailiesWidget extends StatefulWidget {
  final Function(int)? onNavigateToTab;

  const DailiesWidget({Key? key, this.onNavigateToTab}) : super(key: key);

  @override
  State<DailiesWidget> createState() => _DailiesWidgetState();
}

class _DailiesWidgetState extends State<DailiesWidget> with WidgetsBindingObserver, TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  List<File> _todaysPhotos = [];
  List<File> _todaysVideos = [];
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
  VoidCallback? _videoTrackerListener;
  VoidCallback? _profilePicListener;

  @override
  bool get wantKeepAlive => true;

  /// Today's photos and videos merged into one chronologically-ordered
  /// list — this is what actually gets shown in "Your story". Reads
  /// DIRECTLY from the trackers (the source of truth) rather than from
  /// the cached _todaysPhotos/_todaysVideos fields, so any rebuild of
  /// this widget — for any reason — always reflects the true current
  /// state, instead of depending on _loadPhotos() having already run via
  /// a listener that may not have been registered yet at post time.
  List<StoryMediaItem> get _todaysStoryItems {
    final items = <StoryMediaItem>[
      ...DailyPhotoTracker.todaysPhotos.map((f) => StoryMediaItem(file: f, isVideo: false)),
      ...DailyVideoTracker.todaysVideos.map((f) => StoryMediaItem(file: f, isVideo: true)),
    ];
    items.sort((a, b) => _extractTimestamp(a.file).compareTo(_extractTimestamp(b.file)));
    return items;
  }

  int _extractTimestamp(File file) {
    final fileName = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : '';
    final match = RegExp(r'_(\d+)\.').firstMatch(fileName);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadPhotos();
        });
      }
    };

    _trackerListener = () {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadPhotos();
        });
      }
    };

    _videoTrackerListener = () {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadPhotos();
        });
      }
    };

    _profilePicListener = () {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _profilePic = ProfilePicManager.globalProfilePic;
            });
          }
        });
      }
    };


    DailyPhotoManager.addListener(_dailyPhotoListener!);
    DailyPhotoTracker.addListener(_trackerListener!);
    DailyVideoTracker.addListener(_videoTrackerListener!);
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
    if (_videoTrackerListener != null) {
      DailyVideoTracker.removeListener(_videoTrackerListener!);
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
    await DailyVideoTracker.initialize();
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
    await DailyVideoTracker.checkAndResetIfNewDay();
    _loadPhotos();
  }

  void _loadPhotos() {
    setState(() {
      _isLoading = true;
    });

    final previousCount = _todaysPhotos.length + _todaysVideos.length;
    _todaysPhotos = DailyPhotoTracker.todaysPhotos;
    _todaysVideos = DailyVideoTracker.todaysVideos;

    if (_todaysStoryItems.isNotEmpty) {
      _currentPhotoIndex = 0;
    }

    if (_todaysPhotos.length + _todaysVideos.length != previousCount) {
      _checkViewingStatus();
    }

    setState(() {
      _isLoading = false;
    });
  }


  void _checkViewingStatus() {
    final items = _todaysStoryItems;
    int viewedCount = 0;
    for (final item in items) {
      if (_viewedPhotosPaths.contains(item.file.path)) {
        viewedCount++;
      }
    }
    _hasViewedAllPhotos = viewedCount == items.length && items.isNotEmpty;
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

  void _openPhotoCarousel(Offset tapPosition) {
    final items = _todaysStoryItems;
    if (items.isNotEmpty) {
      // Mark first item as viewed
      setState(() {
        _viewedPhotosPaths.add(items[0].file.path);
        _checkViewingStatus();
      });
      Navigator.push(
        context,
        CircleRevealRoute(
          center: tapPosition,
          builder: (context) => OwnStoryViewer(items: items),
        ),
      ).then((_) {
        // Mark all as viewed once they close the viewer
        setState(() {
          for (final item in items) {
            _viewedPhotosPaths.add(item.file.path);
          }
          _checkViewingStatus();
        });
      });
    }
  }


  /// Opens a focused Add screen (Clip or Your Daily) on top of the app. It
  /// has its own close button.
  void _openAddScreen(AddDestination destination) {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: kAddRouteName),
        builder: (context) => AddWidget(destination: destination),
        fullscreenDialog: true,
      ),
    );
  }

  /// The "+" menu. Daily Message and Daily Bubble are handled inside the
  /// sheet / bubble flow, Clip and Your Daily open their own screen, and
  /// New Daily opens the create flow.
  Future<void> _navigateToAddDaily() async {
    while (mounted) {
      final choice = await showAddSheet(context);
      if (choice == null || !mounted) return;
      switch (choice) {
        case AddOption.clip:
          _openAddScreen(AddDestination.clip);
          return;
        case AddOption.yourDaily:
          _openAddScreen(AddDestination.yourDaily);
          return;
        case AddOption.newDaily:
          NewDailyFlow.published = false;
          await Navigator.push(context, NewDailyFlow.route());
          // Closed without publishing -> back to the Add sheet.
          if (NewDailyFlow.published) return;
          continue;
        case AddOption.dailyBubble:
        // Starts bubble creation and switches Home to the Profile tab.
          YourDailyBubbleManager.startCreatingBubble();
          return;
        case AddOption.dailyMessage: // handled inside the sheet
          return;
      }
    }
  }

  // For You is always the tab the screen opens on.
  bool _showForYou = true;

  /// Sliding two-option pill: For You | My Dailies.
  Widget _buildToggle() {
    Widget option(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.black : Colors.grey[600],
              ),
              child: Text(label),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment:
              _showForYou ? Alignment.centerLeft : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                option('For You', _showForYou, () {
                  if (!_showForYou) setState(() => _showForYou = true);
                }),
                option('My Dailies', !_showForYou, () {
                  if (_showForYou) setState(() => _showForYou = false);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The original Dailies list (the Dailies the viewer created or joined),
  /// unchanged apart from now living under the toggle.
  Widget _buildMyDailies() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyan),
      );
    }

    return StreamBuilder<List<DailyData>>(
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

            if (publishedDailies.isEmpty && _todaysStoryItems.isEmpty) {
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
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: publishedDailies.length,
              itemBuilder: (context, index) {
                final daily = publishedDailies[index];
                return DailyCover(
                  daily: daily,
                  hasBeenViewed: viewedToday.contains(daily.id),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        color: Colors.white,
        width: double.infinity,
        height: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: 16, right: 16, top: 60, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Dailies',
                    style: KaidoseBrand.wordmark(32),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Notifications (friend requests, invites, join requests)
                      const NotificationBell(),
                      // Opens the Add sheet
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline,
                            color: Colors.black, size: 28),
                        onPressed: _navigateToAddDaily,
                      ),
                      // Search now lives in its own tab.
                      IconButton(
                        icon: const Icon(Icons.search,
                            color: Colors.black, size: 28),
                        onPressed: () => widget.onNavigateToTab?.call(3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            StoryBar(
              onTapOwnStory: _openPhotoCarousel,
              hasOwnPhotosToday: _todaysStoryItems.isNotEmpty,
              hasViewedAllOwnPhotos: _hasViewedAllPhotos,
            ),
            const SizedBox(height: 16),
            _buildToggle(),
            const SizedBox(height: 14),
            Expanded(
              // Both tabs stay mounted so switching back and forth never
              // reloads the feed or loses its scroll position.
              child: IndexedStack(
                index: _showForYou ? 0 : 1,
                children: [
                  const DailyForYouFeed(),
                  _buildMyDailies(),
                ],
              ),
            ),
          ],
        ),
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