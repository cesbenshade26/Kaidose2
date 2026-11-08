import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'ProfilePicManager.dart';
export 'ProfilePicManager.dart' show DefaultProfilePic;
import 'BackgroundPicManager.dart';
import 'BioManager.dart';
import 'UserManager.dart';
import 'ProfilePic.dart';
import 'BackgroundPic.dart';
import 'SettingBar.dart';
import 'Bio.dart';
import 'DailyPostActivity.dart';
import 'ClipsActivity.dart';
import 'NotificationScreen.dart';
import 'NotificationBell.dart';
import 'friend_request_service.dart';
import 'YourDailyBubbles.dart';
import 'Add.dart';
import 'ProfileStatsRow.dart';
import 'auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileWidget extends StatefulWidget {
  const ProfileWidget({Key? key}) : super(key: key);

  @override
  State<ProfileWidget> createState() => _ProfileWidgetState();
}

class _ProfileWidgetState extends State<ProfileWidget> with WidgetsBindingObserver {
  File? _profilePic;
  File? _backgroundPic;
  bool _showSeparator = false;
  Color _separatorColor = Colors.black;
  String? _bio;
  String? _username;
  int _selectedTabIndex = 0;
  VoidCallback? _profilePicListener;
  VoidCallback? _backgroundPicListener;
  VoidCallback? _bioListener;
  VoidCallback? _usernameListener;
  VoidCallback? _bubbleListener;

  // Whole-page scrolling: the banner, avatar, stats, bio, bubbles and tab
  // bar are one header that scrolls away with the content. Scrolling back
  // UP a little brings in a compact bar (tabs, notifications, settings).
  final ScrollController _outer = ScrollController();
  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 460;
  bool _showBar = false;
  double _upAccum = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _profilePic = ProfilePicManager.globalProfilePic;
    _backgroundPic = BackgroundPicManager.globalBackgroundPic;
    _showSeparator = BackgroundPicManager.showSeparator;
    _separatorColor = BackgroundPicManager.separatorColor;
    _loadBioData();
    _loadUsernameData();
    _loadFromStorage();

    _profilePicListener = () {
      if (mounted) {
        setState(() {
          _profilePic = ProfilePicManager.globalProfilePic;
        });
      }
    };

    _backgroundPicListener = () {
      if (mounted) {
        setState(() {
          _backgroundPic = BackgroundPicManager.globalBackgroundPic;
          _showSeparator = BackgroundPicManager.showSeparator;
          _separatorColor = BackgroundPicManager.separatorColor;
        });
      }
    };

    _bioListener = () {
      if (mounted) {
        setState(() {
          _loadBioData();
        });
      }
    };

    _usernameListener = () {
      if (mounted) {
        setState(() {
          _loadUsernameData();
        });
      }
    };

    // Rebuilds the bubble preview row as its name/cover are edited
    _bubbleListener = () {
      if (mounted) {
        setState(() {});
      }
    };

    ProfilePicManager.addListener(_profilePicListener!);
    BackgroundPicManager.addListener(_backgroundPicListener!);
    BioManager.addListener(_bioListener!);
    UserManager.addListener(_usernameListener!);
    YourDailyBubbleManager.addListener(_bubbleListener!);

    // Load your clips now and warm the first thumbnails, so the Clips tab is
    // ready the moment it's opened.
    MyClipsCache.instance.start();
    MyClipsCache.instance.addListener(_warmClipThumbnails);
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmClipThumbnails());
  }

  void _warmClipThumbnails() {
    if (!mounted) return;
    MyClipsCache.instance.precacheThumbnails(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadBioData();
    }
  }

  void _loadBioData() {
    _bio = BioManager.globalBioText;
  }

  void _loadUsernameData() async {
    String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (userDoc.exists && mounted) {
        setState(() {
          _username = userDoc.data()?['username'] ?? "No Name";
        });
        // Accounts made before username reservations existed claim their
        // name the first time the profile loads.
        final name = userDoc.data()?['username'] as String?;
        if (name != null && name.isNotEmpty) {
          AuthService().ensureUsernameReserved(name);
        }
        // The server uses this to decide which calendar day a post lights
        // up for them.
        userDoc.reference.set({
          'tzOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
        }, SetOptions(merge: true));
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted) {
      _loadBioData();
    }
  }

  Future<void> _loadFromStorage() async {
    // loadProfilePicFromStorage is now UID-aware — loads the correct
    // user's local cache and refreshes from Firebase in the background
    await ProfilePicManager.loadProfilePicFromStorage();
    await BackgroundPicManager.loadBackgroundPicFromStorage();
    await BioManager.loadBioFromStorage();
    await UserManager.loadUsernameFromStorage();
    if (mounted) {
      setState(() {
        _profilePic = ProfilePicManager.globalProfilePic;
        _backgroundPic = BackgroundPicManager.globalBackgroundPic;
        _showSeparator = BackgroundPicManager.showSeparator;
        _separatorColor = BackgroundPicManager.separatorColor;
        _loadBioData();
        _loadUsernameData();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_profilePicListener != null) ProfilePicManager.removeListener(_profilePicListener!);
    if (_backgroundPicListener != null) BackgroundPicManager.removeListener(_backgroundPicListener!);
    if (_bioListener != null) BioManager.removeListener(_bioListener!);
    if (_usernameListener != null) UserManager.removeListener(_usernameListener!);
    if (_bubbleListener != null) YourDailyBubbleManager.removeListener(_bubbleListener!);
    MyClipsCache.instance.removeListener(_warmClipThumbnails);
    _outer.dispose();
    super.dispose();
  }

  void _openAddYourDaily() {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: kAddRouteName),
        builder: (context) =>
        const AddWidget(destination: AddDestination.yourDaily),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _buildBioText() {
    final hasBio = _bio != null && _bio!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          hasBio ? _bio! : 'Add a bio',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.3,
            color: hasBio ? Colors.grey[800] : Colors.grey[500],
          ),
        ),
      ),
    );
  }

  void _setTab(int i) {
    if (i == _selectedTabIndex) return;
    setState(() {
      _selectedTabIndex = i;
      _showBar = false;
      _upAccum = 0;
    });
  }

  /// Shows the compact bar when the user scrolls UP after the header has
  /// scrolled out of view; hides it when scrolling down or when the real
  /// header is back on screen.
  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification) return false;

    final outerOffset = _outer.hasClients ? _outer.offset : 0.0;
    if (outerOffset < _headerHeight - 2) {
      _upAccum = 0;
      if (_showBar) setState(() => _showBar = false);
      return false;
    }

    // Ignore the bounce past the end of a list.
    if (n.metrics.pixels > n.metrics.maxScrollExtent) return false;

    final delta = n.scrollDelta ?? 0;
    if (delta < 0) {
      _upAccum += -delta;
      if (_upAccum > 8 && !_showBar) setState(() => _showBar = true);
    } else if (delta > 0) {
      _upAccum = 0;
      if (_showBar) setState(() => _showBar = false);
    }
    return false;
  }

  Widget _barTab(int i, IconData off, IconData on, String label) {
    final selected = _selectedTabIndex == i;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setTab(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Icon(
            selected ? on : off,
            size: 24,
            color: selected ? Colors.black : Colors.grey[400],
          ),
        ),
      ),
    );
  }

  /// The compact bar: both tabs plus notifications and settings. Faint and
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
                height: topInset + 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.86),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    _barTab(0, Icons.wb_sunny_outlined, Icons.wb_sunny_rounded,
                        'Dailies'),
                    _barTab(1, Icons.videocam_outlined, Icons.videocam, 'Clips'),
                    const Spacer(),
                    const NotificationBell(size: 26),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          color: Colors.black, size: 26),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const SettingsScreen()),
                        );
                      },
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

  Widget _buildBanner() {
    const double h = BackgroundSpec.bannerHeight;
    final bool hasPic = _backgroundPic != null && _backgroundPic!.existsSync();
    return SizedBox(
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          hasPic
              ? Image.file(
            _backgroundPic!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: h,
            key: ValueKey(_backgroundPic!.path +
                _backgroundPic!.lastModifiedSync().toString()),
            errorBuilder: (context, error, stackTrace) =>
                Container(decoration: BackgroundSpec.defaultDecoration),
          )
              : Container(decoration: BackgroundSpec.defaultDecoration),
          // Light scrim so the status bar and top icons stay readable
          IgnorePointer(
              child: Container(decoration: BackgroundSpec.scrimDecoration)),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    // Dailies, Clips (Saved lives behind a button in Settings for now)
    const icons = [
      [Icons.wb_sunny_outlined, Icons.wb_sunny_rounded],
      [Icons.videocam_outlined, Icons.videocam],
    ];
    const labels = ['Dailies', 'Clips'];

    return Column(
      children: [
        Row(
          children: List.generate(2, (i) {
            final selected = _selectedTabIndex == i;
            return Expanded(
              child: Semantics(
                label: labels[i],
                button: true,
                selected: selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setTab(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: TweenAnimationBuilder<Color?>(
                      duration: const Duration(milliseconds: 200),
                      tween: ColorTween(
                        end: selected ? Colors.black : Colors.grey[400],
                      ),
                      builder: (context, color, _) => Icon(
                        icons[i][selected ? 1 : 0],
                        size: 25,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        SizedBox(
          height: 2.5,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(height: 1, color: Colors.grey[200]),
              ),
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment(_selectedTabIndex * 2 - 1.0, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / 2,
                  child: Center(
                    child: Container(
                      width: 28,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return const DailyPostActivity();
      case 1:
        return const ClipsActivity();
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Measure the header so we know when it has fully scrolled away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _headerKey.currentContext?.size?.height;
      if (h != null && h > 0) _headerHeight = h;
    });

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: NestedScrollView(
            controller: _outer,
            headerSliverBuilder: (context, innerScrolled) => [
              SliverToBoxAdapter(child: _buildHeader()),
            ],
            body: _buildTabContent(),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildFloatingBar(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Stack(
      key: _headerKey,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: BackgroundSpec.bannerHeight,
          child: _buildBanner(),
        ),
        SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: BackgroundSpec.bannerHeight - BackgroundSpec.avatarSize / 2),
              // Avatar row: counts sit under the banner on either side of the avatar
              SizedBox(
                height: BackgroundSpec.avatarSize,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Center(child:
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ProfilePicScreen()),
                        ).then((_) {
                          setState(() {
                            _profilePic = ProfilePicManager.globalProfilePic;
                          });
                        });
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: BackgroundSpec.avatarSize,
                            height: BackgroundSpec.avatarSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey[300],
                            ),
                            child: ClipOval(
                              child: _profilePic != null && _profilePic!.existsSync()
                                  ? Image.file(
                                _profilePic!,
                                fit: BoxFit.cover,
                                width: BackgroundSpec.avatarSize,
                                height: BackgroundSpec.avatarSize,
                                key: ValueKey(_profilePic!.path + _profilePic!.lastModifiedSync().toString()),
                                errorBuilder: (context, error, stackTrace) {
                                  return const DefaultProfilePic(size: BackgroundSpec.avatarSize, borderWidth: 0);
                                },
                              )
                                  : const DefaultProfilePic(size: BackgroundSpec.avatarSize, borderWidth: 0),
                            ),
                          ),
                          // Small "+" — post to Your Daily. Closing that screen comes
                          // straight back to the profile.
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: GestureDetector(
                              onTap: _openAddYourDaily,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.cyan,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.add, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ProfileStatsRow(
                userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                username: _username ?? '',
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const BioScreen()),
                  );
                  await BioManager.loadBioFromStorage();
                  setState(() {
                    _loadBioData();
                  });
                },
                child: _buildBioText(),
              ),
              // Daily Bubble row — sits below the days-lit counter/bio and above
              // the tab bar. Only shown while a bubble is being created for now;
              // this is where saved bubbles will eventually be listed.
              if (YourDailyBubbleManager.isCreating || YourDailyBubbleManager.bubbles.isNotEmpty) ...[
                const SizedBox(height: 8),
                YourDailyBubbleRow(),
              ],
              const SizedBox(height: 4),
              _buildTabBar(),
            ],
          ),
        ),

        // Notification Bell (Top Left)
        const Positioned(
          top: 50,
          left: 16,
          child: NotificationBell(color: Colors.white),
        ),

        // Settings Button (Top Right)
        Positioned(
          top: 50,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  File? _backgroundPic;
  bool _showSeparator = false;
  Color _separatorColor = Colors.black;
  VoidCallback? _backgroundPicListener;
  VoidCallback? _bubbleListener;

  @override
  void initState() {
    super.initState();

    _backgroundPic = BackgroundPicManager.globalBackgroundPic;
    _showSeparator = BackgroundPicManager.showSeparator;
    _separatorColor = BackgroundPicManager.separatorColor;

    _loadBackgroundFromStorage();

    _backgroundPicListener = () {
      if (mounted) {
        setState(() {
          _backgroundPic = BackgroundPicManager.globalBackgroundPic;
          _showSeparator = BackgroundPicManager.showSeparator;
          _separatorColor = BackgroundPicManager.separatorColor;
        });
      }
    };

    BackgroundPicManager.addListener(_backgroundPicListener!);

    // Rebuilds to show/hide the dark "creating a bubble" overlay
    _bubbleListener = () {
      if (mounted) {
        setState(() {});
      }
    };
    YourDailyBubbleManager.addListener(_bubbleListener!);

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // Each load runs independently and is caught on its own — a failure in
    // one (e.g. bio) should never silently block the others from running,
    // which is what was stopping Daily Bubbles from loading before.
    await Future.wait([
      _safeLoad('BioManager', BioManager.loadBioFromStorage),
      _safeLoad('UserManager', UserManager.loadUsernameFromStorage),
      _safeLoad('YourDailyBubbleManager', YourDailyBubbleManager.loadBubblesFromFirestore),
    ]);
  }

  Future<void> _safeLoad(String label, Future<void> Function() loader) async {
    try {
      await loader();
    } catch (e) {
      print('ProfilePage: $label failed to load: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setState(() {
      _backgroundPic = BackgroundPicManager.globalBackgroundPic;
      _showSeparator = BackgroundPicManager.showSeparator;
      _separatorColor = BackgroundPicManager.separatorColor;
    });
  }

  Future<void> _loadBackgroundFromStorage() async {
    await BackgroundPicManager.loadBackgroundPicFromStorage();
    if (mounted) {
      setState(() {
        _backgroundPic = BackgroundPicManager.globalBackgroundPic;
        _showSeparator = BackgroundPicManager.showSeparator;
        _separatorColor = BackgroundPicManager.separatorColor;
      });
    }
  }

  @override
  void dispose() {
    if (_backgroundPicListener != null) {
      BackgroundPicManager.removeListener(_backgroundPicListener!);
    }
    if (_bubbleListener != null) {
      YourDailyBubbleManager.removeListener(_bubbleListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Banner, avatar, stats, tabs and the page's scrolling all live in
          // ProfileWidget now.
          const ProfileWidget(),

          // Dark "creating a bubble" overlay — covers the whole screen
          // (including the bell/settings buttons) until the user finishes
          // or backs out via the X.
          if (YourDailyBubbleManager.isCreating) const YourDailyBubbleCreatorOverlay(),
        ],
      ),
    );
  }
}