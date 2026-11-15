import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Profile.dart';
import 'Dailies.dart';
import 'Search.dart';
import 'Add.dart' show kAddRouteName;
import 'Clips.dart';
import 'Chat.dart';
import 'HomeSwipe.dart';
import 'YourDailyBubbles.dart';
import 'ClipsActivity.dart' show MyClipsCache;
import 'NotificationService.dart';

class HomeScreen extends StatefulWidget {
  /// Kept for existing callers. Opening Home without a specific tab always
  /// plays the entrance now, so this no longer changes anything.
  final bool fadeInFromAnimation;

  /// Open on a specific tab (no entrance animation). Null = Dailies.
  final int? initialTabIndex;

  const HomeScreen({
    Key? key,
    this.fadeInFromAnimation = false,
    this.initialTabIndex,
  }) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late int _selectedIndex;
  int _previousIndex = 0;

  // Dailies is the tab the app opens on.
  static const int _dailiesTabIndex = 0;
  // Clips tab index — update this if you ever reorder tabs
  static const int _clipsTabIndex = 2;
  // Profile tab index — used when Daily Bubble creation force-switches tabs
  static const int _profileTabIndex = 4;

  // One controller drives the whole entrance, so every piece shares the
  // same timeline instead of separate animations chained with delays.
  late final AnimationController _entry;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;
  late final Animation<Offset> _navBarSlide;
  late final List<Animation<double>> _iconFades;

  bool _afterEntryDone = false;

  @override
  void initState() {
    super.initState();

    _selectedIndex = widget.initialTabIndex ?? _dailiesTabIndex;
    _previousIndex = _selectedIndex;

    _entry = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    // Content: fades in while drifting up a few pixels.
    _contentFade = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.015),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
    ));

    // Nav bar: slides up just behind the content.
    _navBarSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.15, 1.0, curve: Curves.easeOutCubic),
    ));

    // Nav icons: fade in left to right as the bar arrives.
    _iconFades = List.generate(5, (i) {
      final start = 0.35 + i * 0.07;
      return CurvedAnimation(
        parent: _entry,
        curve: Interval(start, (start + 0.35).clamp(0.0, 1.0),
            curve: Curves.easeOut),
      );
    });

    if (widget.initialTabIndex == null) {
      // Fresh open: play the entrance on the first frame, then start the
      // heavier background work once it's finished so nothing competes
      // with it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _entry.forward().whenComplete(_afterEntry);
      });
    } else {
      _entry.value = 1.0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _afterEntry());
    }

    // Lets YourDaily.dart force-switch to the Profile tab when the user
    // taps Daily Bubble in the Add sheet, without Add.dart needing to know about it.
    YourDailyBubbleManager.registerNavigateToProfile(() {
      // Add is opened on top of Home for now; close it first so the tab
      // switch isn't hidden behind it.
      Navigator.of(context).popUntil((route) => route.settings.name != kAddRouteName);
      _onItemTapped(_profileTabIndex);
    });
  }

  /// Background work that used to run during the entrance (and made it
  /// stutter): loading your clips + thumbnails, and registering for push
  /// notifications (which can show the permission prompt).
  void _afterEntry() {
    if (!mounted || _afterEntryDone) return;
    _afterEntryDone = true;

    // Start loading your clips (and their thumbnails), so the Clips tab
    // on your profile is ready before you ever open it.
    MyClipsCache.instance.start();
    MyClipsCache.instance.addListener(_warmClipThumbnails);
    _warmClipThumbnails();

    // Signed in: register this phone for push notifications (asks for
    // permission the first time) and handle a notification that was
    // tapped to open the app.
    NotificationService.instance.start();
  }

  void _warmClipThumbnails() {
    if (!mounted) return;
    MyClipsCache.instance.precacheThumbnails(context);
  }

  void _onItemTapped(int index) {
    if (index != _selectedIndex) {
      setState(() {
        _previousIndex = _selectedIndex;
        _selectedIndex = index;
      });
    }
  }

  @override
  void dispose() {
    YourDailyBubbleManager.unregisterNavigateToProfile();
    MyClipsCache.instance.removeListener(_warmClipThumbnails);
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String currentUid =
        FirebaseAuth.instance.currentUser?.uid ?? 'guest';

    // Build pages here so ClipsWidget gets the latest _selectedIndex
    final pages = [
      DailiesWidget(
        key: const PageStorageKey('dailies'),
        onNavigateToTab: (idx) => _onItemTapped(idx),
      ),
      const ChatWidget(key: PageStorageKey('chat')),
      ClipsWidget(
        key: const PageStorageKey('clips'),
        isTabActive: _selectedIndex == _clipsTabIndex,
      ),
      const SearchScreen(key: PageStorageKey('search'), isTab: true),
      ProfilePage(key: ValueKey('profile_$currentUid')),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _contentFade,
        child: SlideTransition(
          position: _contentSlide,
          child: HomeSwipeDetector(
            currentIndex: _selectedIndex,
            totalPages: 5,
            edgeThreshold: 80.0,
            pages: pages,
            onPageChanged: (newIndex) => _onItemTapped(newIndex),
          ),
        ),
      ),
      bottomNavigationBar: SlideTransition(
        position: _navBarSlide,
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                spreadRadius: 1,
                blurRadius: 8,
                offset: const Offset(0, -2),
              )
            ],
          ),
          child: Row(
            children: [
              _buildNavItem(0, Icons.wb_sunny, 'Sun', _iconFades[0]),
              _buildNavItem(1, Icons.chat_bubble_outline, 'Chat', _iconFades[1]),
              _buildNavItem(2, Icons.videocam_outlined, 'Camera', _iconFades[2]),
              _buildNavItem(3, Icons.search, 'Search', _iconFades[3]),
              _buildNavItem(4, Icons.person_outline, 'Profile', _iconFades[4]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label,
      Animation<double> animation) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: FadeTransition(
        opacity: animation,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onItemTapped(index),
          child: SizedBox(
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: isSelected ? 50 : 0,
                  height: isSelected ? 50 : 0,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.black : Colors.transparent,
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                Icon(icon,
                    size: 26,
                    color: isSelected ? Colors.white : Colors.black),
              ],
            ),
          ),
        ),
      ),
    );
  }
}