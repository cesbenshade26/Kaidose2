import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Profile.dart';
import 'Dailies.dart';
import 'Search.dart';
import 'Add.dart' show kAddRouteName;
import 'Clips.dart';
import 'Chat.dart';
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

// ═══════════════════════════════════════════════════════════════════════════
// Tab swiping (moved here from HomeSwipe.dart, which is no longer used)
// ═══════════════════════════════════════════════════════════════════════════

/// Swiping between the Home tabs from the screen edges.
///
/// Every tab is built ONCE and kept alive (like an IndexedStack). A swipe
/// just slides the current tab and its neighbor side by side; nothing is
/// rebuilt or recreated, so it stays smooth even on heavy tabs.
///
///  * Starts only from the left/right edge ([edgeThreshold]), so swipes
///    inside a tab (story bar, carousels) aren't stolen.
///  * Follows your finger 1:1, with a rubber-band pull past the first and
///    last tab.
///  * Let go: a spring finishes the swipe, carrying your finger's speed, or
///    snaps back if it wasn't far or fast enough.
///  * The tab bar switches as soon as the swipe is committed, and tapping
///    a tab mid-swipe still works.
class HomeSwipeDetector extends StatefulWidget {
  final int currentIndex;
  final int totalPages;
  final Function(int) onPageChanged;
  final List<Widget> pages;
  final double edgeThreshold;

  const HomeSwipeDetector({
    Key? key,
    required this.currentIndex,
    required this.totalPages,
    required this.onPageChanged,
    required this.pages,
    this.edgeThreshold = 80.0,
  }) : super(key: key);

  @override
  State<HomeSwipeDetector> createState() => _HomeSwipeDetectorState();
}

class _HomeSwipeDetectorState extends State<HomeSwipeDetector>
    with SingleTickerProviderStateMixin {
  // Where the pages are, in pages: 2.0 = tab 2 fills the screen, 2.4 = 60%
  // of tab 2 and 40% of tab 3 showing. Only the slides listen to this, so
  // a swipe never rebuilds the tabs themselves.
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
    value: widget.currentIndex.toDouble(),
  );

  // Swipes past this share of the screen, or flicked faster than
  // [_flickSpeed], go to the next tab.
  static const double _distanceToSwitch = 0.35;
  static const double _flickSpeed = 450; // px/s

  // Fast and smooth, no wobble.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 1.0,
  );

  bool _edgeDown = false; // finger went down at an edge
  bool _dragging = false;
  double _dragStartPos = 0;
  int? _settlingTo; // tab a finished swipe is sliding to

  int get _last => widget.totalPages - 1;

  @override
  void didUpdateWidget(HomeSwipeDetector old) {
    super.didUpdateWidget(old);
    final i = widget.currentIndex;
    if (i == old.currentIndex) return;
    // Our own swipe told Home to switch: let the spring finish the slide.
    if (i == _settlingTo) return;
    // A tab was tapped: switch straight there (stops any swipe).
    _dragging = false;
    _settlingTo = null;
    _pos.stop();
    _pos.value = i.toDouble();
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  // ─── Gestures ─────────────────────────────────────────────────────────────

  void _onDown(DragDownDetails d) {
    // Decide on the exact spot the finger touched (not after it moved).
    final w = MediaQuery.of(context).size.width;
    final x = d.globalPosition.dx;
    _edgeDown = x <= widget.edgeThreshold || x >= w - widget.edgeThreshold;
  }

  void _onStart(DragStartDetails d) {
    if (!_edgeDown) return;
    _dragging = true;
    _settlingTo = null;
    _pos.stop(); // catch a slide that's still moving
    _dragStartPos = _pos.value;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final w = MediaQuery.of(context).size.width;
    final step = -d.delta.dx / w;
    var p = _pos.value + step;
    // Past the first / last tab: rubber band (gets stiffer the further).
    if (p < 0) {
      p = _pos.value + step * _resistance(-_pos.value);
    } else if (p > _last) {
      p = _pos.value + step * _resistance(_pos.value - _last);
    } else {
      // Never more than one tab away from where the swipe started.
      p = p.clamp(_dragStartPos.floorToDouble() - 1, _dragStartPos.ceilToDouble() + 1);
    }
    _pos.value = p;
  }

  double _resistance(double over) => (0.45 * (1 - over * 2.5)).clamp(0.05, 0.45);

  void _onEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final w = MediaQuery.of(context).size.width;
    final vx = d.velocity.pixelsPerSecond.dx; // + = finger moving right
    final from = widget.currentIndex;
    final moved = _pos.value - from; // + = toward the next tab

    var target = from;
    if (vx.abs() > _flickSpeed) {
      // A flick goes the way the finger was moving (unless it reversed
      // back past where the swipe started).
      final dir = vx < 0 ? 1 : -1;
      if (moved * dir >= -0.02) target = from + dir;
    } else if (moved.abs() > _distanceToSwitch) {
      target = from + (moved > 0 ? 1 : -1);
    }
    target = target.clamp(0, _last);
    _settle(target, -vx / w);
  }

  void _onCancel() {
    if (!_dragging) return;
    _dragging = false;
    _settle(widget.currentIndex, 0);
  }

  /// Springs to [target], carrying the finger's speed ([velocity] in
  /// pages per second), and switches the tab bar right away.
  void _settle(int target, double velocity) {
    _settlingTo = target;
    // Finger was moving away from where it's going (snapping back): don't
    // carry that speed, or it would overshoot.
    final toward = target - _pos.value;
    if (toward * velocity < 0) velocity = 0;
    _pos.animateWith(
        SpringSimulation(_spring, _pos.value, target.toDouble(), velocity))
        .whenCompleteOrCancel(() {
      if (_settlingTo == target) {
        _pos.value = target.toDouble(); // land exactly on the tab
        _settlingTo = null;
      }
    });
    if (target != widget.currentIndex) widget.onPageChanged(target);
  }

  // ─── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragDown: _onDown,
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onCancel,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.pages.length; i++)
              _Slide(
                // Same key and same widget shape every build, so each tab's
                // state is never recreated.
                key: ValueKey('home_page_$i'),
                index: i,
                position: _pos,
                child: widget.pages[i],
              ),
          ],
        ),
      ),
    );
  }
}

/// One tab, slid into place. Off screen it isn't laid out, painted or
/// ticking (animations/videos pause), but keeps all its state.
class _Slide extends StatelessWidget {
  final int index;
  final Animation<double> position;
  final Widget child;

  const _Slide({
    Key? key,
    required this.index,
    required this.position,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // The tab itself is built once and passed through; only the wrapper
    // below rebuilds as the swipe moves.
    final page = RepaintBoundary(child: child);
    return AnimatedBuilder(
      animation: position,
      child: page,
      builder: (context, page) {
        final offset = index - position.value; // in screens
        final visible = offset.abs() < 0.999;
        return Offstage(
          offstage: !visible,
          child: TickerMode(
            enabled: visible,
            child: FractionalTranslation(
              translation: Offset(visible ? offset : 0, 0),
              transformHitTests: true,
              child: page,
            ),
          ),
        );
      },
    );
  }
}