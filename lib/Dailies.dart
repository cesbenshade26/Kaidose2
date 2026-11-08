import 'dart:ui' show ImageFilter;
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
export 'ProfilePicManager.dart' show DefaultProfilePic;
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

  // The whole screen is one scroll view (header, story bar, tabs and the
  // list scroll together).
  final ScrollController _scroll = ScrollController();
  final DailyForYouController _forYou = DailyForYouController();
  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 330;

  // Compact bar (tabs + Add + notifications) that fades in at the top when
  // the user scrolls back up after the real ones have scrolled away.
  bool _showBar = false;
  double _upAccum = 0;

  // Each tab remembers its own scroll position.
  final Map<bool, double> _tabOffsets = {true: 0, false: 0};

  // Where the user was when they opened Add / Notifications.
  double _savedOffset = 0;
  bool _savedBar = false;

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
    // A file that's gone (e.g. from an old install) would just be a black
    // screen, so leave it out.
    return items.where((i) => i.file.existsSync()).toList();
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

    _scroll.addListener(_onScrollPosition);

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
    _scroll.removeListener(_onScrollPosition);
    _scroll.dispose();
    _fade.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _forYou.dispose();
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
      // Open at the first post you haven't seen yet (the old ones stay one
      // tap back); if you've seen them all, start from the beginning.
      var start = items.indexWhere((i) => !_viewedPhotosPaths.contains(i.file.path));
      if (start < 0) start = 0;
      // Mark first item as viewed
      setState(() {
        _viewedPhotosPaths.add(items[0].file.path);
        _checkViewingStatus();
      });
      Navigator.push(
        context,
        CircleRevealRoute(
          center: tapPosition,
          builder: (context) =>
              OwnStoryViewer(items: items, initialIndex: start),
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
  Future<void> _openAddScreen(AddDestination destination) {
    return Navigator.push(
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
          await _openAddScreen(AddDestination.clip);
          return;
        case AddOption.yourDaily:
          await _openAddScreen(AddDestination.yourDaily);
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

  // ---------------------------------------------------------------------
  // Scrolling
  // ---------------------------------------------------------------------

  /// Pages the For You feed in as the user nears the bottom.
  void _onScrollPosition() {
    if (!_scroll.hasClients || !_showForYou) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _forYou.loadMoreIfNeeded();
    }
  }

  /// Shows the compact bar when the user scrolls UP after the real tabs and
  /// buttons have scrolled out of view; hides it when scrolling down or when
  /// the real ones are back on screen.
  bool _onScrollNotification(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification) return false;

    final offset = n.metrics.pixels;
    final delta = n.scrollDelta ?? 0;

    // Real tabs/buttons are visible again.
    if (offset <= _headerHeight) {
      _upAccum = 0;
      if (_showBar) setState(() => _showBar = false);
      return false;
    }

    // Ignore the bounce at the very bottom.
    if (offset >= n.metrics.maxScrollExtent - 1) return false;

    if (delta < 0) {
      _upAccum += -delta;
      if (_upAccum > 8 && !_showBar) setState(() => _showBar = true);
    } else if (delta > 0) {
      _upAccum = 0;
      if (_showBar) setState(() => _showBar = false);
    }
    return false;
  }

  /// Remember exactly where the user is before opening Add / Notifications...
  void _rememberPosition() {
    _savedOffset = _scroll.hasClients ? _scroll.offset : 0;
    _savedBar = _showBar;
  }

  /// ...and put them back there when those screens close.
  void _restorePosition() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _savedOffset.clamp(0.0, _scroll.position.maxScrollExtent);
      if ((_scroll.offset - target).abs() > 1) _scroll.jumpTo(target);
      if (_showBar != _savedBar) setState(() => _showBar = _savedBar);
    });
  }

  Future<void> _onAddPressed() async {
    _rememberPosition();
    await _navigateToAddDaily();
    _restorePosition();
  }

  void _setTab(bool forYou) {
    if (forYou == _showForYou) return;
    if (_searchOpen) _closeSearch();
    _tabOffsets[_showForYou] = _scroll.hasClients ? _scroll.offset : 0;

    // Hide the list, swap tabs and restore that tab's scroll spot while it is
    // invisible, then fade it back in. No visible jump.
    _fade.value = 0;
    setState(() {
      _showForYou = forYou;
      _showBar = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        final target = (_tabOffsets[forYou] ?? 0)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.jumpTo(target);
      }
      _fade.forward();
    });
  }

  Future<void> _onRefresh() async {
    if (_showForYou) await _forYou.loadFeed(silent: true);
  }

  // ---------------------------------------------------------------------
  // Tabs
  // ---------------------------------------------------------------------

  // For You is always the tab the screen opens on.
  bool _showForYou = true;

  // My Dailies search (icon at the right edge that expands into a bar).
  // Quick fade for the list when switching tabs.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  bool _searchOpen = false;
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _searchCtrl.clear();
    setState(() {
      _searchOpen = false;
      _query = '';
    });
  }

  /// Sliding two-option pill: For You | My Dailies.
  Widget _buildToggle() {
    Widget option(String label, bool selected, VoidCallback onTap,
        {Widget? trailing}) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              Center(
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
              if (trailing != null)
                Positioned(right: 0, top: 0, bottom: 0, child: trailing),
            ],
          ),
        ),
      );
    }

    // Search mode: the whole pill turns into a search field (same size, so
    // nothing on the screen moves).
    if (_searchOpen && !_showForYou) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(Icons.search, size: 20, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search my Dailies',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeSearch,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.close, size: 20, color: Colors.grey[600]),
                ),
              ),
            ],
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
                option('For You', _showForYou, () => _setTab(true)),
                option(
                  'My Dailies',
                  !_showForYou,
                      () => _setTab(false),
                  trailing: _showForYou
                      ? null
                      : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openSearch,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.search,
                          size: 20, color: Colors.grey[700]),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One tab in the compact bar.
  Widget _barTab(String label, bool forYou) {
    final selected = _showForYou == forYou;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setTab(forYou),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.black : Colors.grey[500],
              ),
              child: Text(label),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2.5,
              width: selected ? 22 : 0,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The compact bar: both tabs plus Notifications and Add. Faint and
  /// slightly see-through, it slides in from the top edge.
  Widget _buildFloatingBar() {
    final topInset = MediaQuery.of(context).padding.top;
    return IgnorePointer(
      ignoring: !_showBar,
      child: AnimatedSlide(
        offset: _showBar ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _showBar ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: EdgeInsets.only(top: topInset, left: 8, right: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.86),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
                  ),
                ),
                height: topInset + 48,
                child: Row(
                  children: [
                    _barTab('For You', true),
                    _barTab('My Dailies', false),
                    const Spacer(),
                    NotificationBell(
                      size: 26,
                      onBeforeOpen: _rememberPosition,
                      onAfterClose: _restorePosition,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: Colors.black, size: 26),
                      onPressed: _onAddPressed,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // My Dailies
  // ---------------------------------------------------------------------

  Widget _centered(Widget child) {
    return SizedBox(height: 360, child: Center(child: child));
  }

  /// The original Dailies list (the Dailies the viewer created or joined),
  /// now a sliver so it scrolls with the rest of the screen.
  Widget _buildMyDailiesSliver() {
    if (_isLoading) {
      return SliverToBoxAdapter(
        child: _centered(const CircularProgressIndicator(color: Colors.cyan)),
      );
    }

    return SliverToBoxAdapter(
      child: StreamBuilder<List<DailyData>>(
        stream: DailyList.getDailiesStream(),
        builder: (context, dailiesSnapshot) {
          if (dailiesSnapshot.connectionState == ConnectionState.waiting) {
            return _centered(
                const CircularProgressIndicator(color: Colors.cyan));
          }

          if (dailiesSnapshot.hasError) {
            return _centered(Text('Error: ${dailiesSnapshot.error}'));
          }

          final allDailies = dailiesSnapshot.data ?? [];
          final q = _query.trim().toLowerCase();
          final publishedDailies = q.isEmpty
              ? allDailies
              : allDailies
              .where((d) => d.title.toLowerCase().contains(q))
              .toList();

          return StreamBuilder<Set<String>>(
            stream: DailyList.getViewedDailiesStream(),
            builder: (context, viewedSnapshot) {
              final viewedToday = viewedSnapshot.data ?? {};

              if (q.isNotEmpty && publishedDailies.isEmpty) {
                return _centered(Text('No Dailies match "$_query"',
                    style: TextStyle(fontSize: 15, color: Colors.grey[600])));
              }

              if (publishedDailies.isEmpty && _todaysStoryItems.isEmpty) {
                return _centered(
                  Column(
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
                        onTap: _onAddPressed,
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

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (final daily in publishedDailies)
                      DailyCover(
                        key: ValueKey('mine_${daily.id}'),
                        daily: daily,
                        hasBeenViewed: viewedToday.contains(daily.id),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Measure the header so we know when the real tabs/buttons are off screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _headerKey.currentContext?.size?.height;
      if (h != null && h > 0) _headerHeight = h;
    });

    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: RefreshIndicator(
              color: Colors.cyan,
              edgeOffset: topInset + 8,
              onRefresh: _onRefresh,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      key: _headerKey,
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
                                  // Notifications (friend requests, invites,
                                  // join requests)
                                  NotificationBell(
                                    onBeforeOpen: _rememberPosition,
                                    onAfterClose: _restorePosition,
                                  ),
                                  // Opens the Add sheet
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline,
                                        color: Colors.black, size: 28),
                                    onPressed: _onAddPressed,
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
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: KeyedSubtree(
                            key: ValueKey(_searchOpen && !_showForYou),
                            child: _buildToggle(),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                  SliverFadeTransition(
                    opacity: CurvedAnimation(
                        parent: _fade, curve: Curves.easeOut),
                    sliver: _showForYou
                        ? DailyForYouSliver(controller: _forYou)
                        : _buildMyDailiesSliver(),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildFloatingBar(),
          ),
        ],
      ),
    );
  }
}