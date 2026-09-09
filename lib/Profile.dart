import 'package:flutter/material.dart';
import 'dart:io';
import 'ProfilePicManager.dart';
import 'BackgroundPicManager.dart';
import 'BioManager.dart';
import 'UserManager.dart';
import 'UserFollowers.dart';
import 'UserFollowing.dart';
import 'ProfilePic.dart';
import 'BackgroundPic.dart';
import 'SettingBar.dart';
import 'Bio.dart';
import 'DailyPostActivity.dart';
import 'ClipsActivity.dart';
import 'Archives.dart';
import 'NotificationScreen.dart';
import 'friend_request_service.dart';
import 'YourDailyBubbles.dart';
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
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderlined = false;
  TextAlign _textAlign = TextAlign.center;
  Color _textColor = Colors.black;
  String? _username;
  int _followersCount = 0;
  int _followingCount = 0;
  int _selectedTabIndex = 0;
  VoidCallback? _profilePicListener;
  VoidCallback? _backgroundPicListener;
  VoidCallback? _bioListener;
  VoidCallback? _usernameListener;
  VoidCallback? _followersListener;
  VoidCallback? _followingListener;
  VoidCallback? _bubbleListener;

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
    _loadFollowersData();
    _loadFollowingData();

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

    _followersListener = () {
      if (mounted) {
        setState(() {
          _loadFollowersData();
        });
      }
    };

    _followingListener = () {
      if (mounted) {
        setState(() {
          _loadFollowingData();
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
    UserFollowers.addListener(_followersListener!);
    UserFollowing.addListener(_followingListener!);
    YourDailyBubbleManager.addListener(_bubbleListener!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadBioData();
    }
  }

  void _loadBioData() {
    _bio = BioManager.globalBioText;
    _isBold = BioManager.globalBold;
    _isItalic = BioManager.globalItalic;
    _isUnderlined = BioManager.globalUnderlined;
    _textAlign = BioManager.globalAlign;
    _textColor = BioManager.globalColor;
  }

  void _loadUsernameData() async {
    String? uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (userDoc.exists && mounted) {
        setState(() {
          _username = userDoc.data()?['username'] ?? "No Name";
          _bio = userDoc.data()?['bio'] ?? "";
        });
      }
    }
  }

  void _loadFollowersData() {
    _followersCount = UserFollowers.followersCount;
  }

  void _loadFollowingData() {
    _followingCount = UserFollowing.followingCount;
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
    await UserFollowers.loadFollowersCountFromStorage();
    await UserFollowing.loadFollowingCountFromStorage();
    if (mounted) {
      setState(() {
        _profilePic = ProfilePicManager.globalProfilePic;
        _backgroundPic = BackgroundPicManager.globalBackgroundPic;
        _showSeparator = BackgroundPicManager.showSeparator;
        _separatorColor = BackgroundPicManager.separatorColor;
        _loadBioData();
        _loadUsernameData();
        _loadFollowersData();
        _loadFollowingData();
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
    if (_followersListener != null) UserFollowers.removeListener(_followersListener!);
    if (_followingListener != null) UserFollowing.removeListener(_followingListener!);
    if (_bubbleListener != null) YourDailyBubbleManager.removeListener(_bubbleListener!);
    super.dispose();
  }

  Widget _buildBioText(double screenWidth) {
    const double profilePicSize = 160.0;
    final double profilePicStartX = (screenWidth - profilePicSize) / 2;

    if (_bio == null || _bio!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!, width: 1),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey[50],
          ),
          child: Text(
            'Tap to add bio',
            style: TextStyle(fontSize: 16, color: Colors.grey[600], fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    Widget bioText = Text(
      _bio!,
      style: TextStyle(
        fontSize: 16,
        color: _textColor,
        fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
        decoration: _isUnderlined ? TextDecoration.underline : TextDecoration.none,
      ),
      textAlign: _textAlign,
    );

    switch (_textAlign) {
      case TextAlign.left:
        return Padding(
          padding: EdgeInsets.only(left: profilePicStartX, right: 24),
          child: Align(alignment: Alignment.centerLeft, child: bioText),
        );
      case TextAlign.right:
        return Padding(
          padding: EdgeInsets.only(left: 24, right: profilePicStartX),
          child: Align(alignment: Alignment.centerRight, child: bioText),
        );
      case TextAlign.center:
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(width: double.infinity, child: bioText),
        );
    }
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return const DailyPostActivity();
      case 1:
        return const ClipsActivity();
      case 2:
        return const ArchivesView();
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      children: [
        const SizedBox(height: 40),
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
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[300],
              border: Border.all(color: Colors.grey[400]!, width: 3),
            ),
            child: ClipOval(
              child: _profilePic != null && _profilePic!.existsSync()
                  ? Image.file(
                _profilePic!,
                fit: BoxFit.cover,
                width: 160,
                height: 160,
                key: ValueKey(_profilePic!.path + _profilePic!.lastModifiedSync().toString()),
                errorBuilder: (context, error, stackTrace) {
                  return const DefaultProfilePic(size: 160, borderWidth: 0);
                },
              )
                  : const DefaultProfilePic(size: 160, borderWidth: 0),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                children: [
                  Text(
                    '$_followersCount',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Followers',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
              if (_username != null && _username!.isNotEmpty)
                Text(
                  _username!,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
                  textAlign: TextAlign.center,
                ),
              Column(
                children: [
                  Text(
                    '$_followingCount',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Following',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
          child: _buildBioText(screenWidth),
        ),
        // Daily Bubble row — sits below followers/following/bio and above
        // the tab bar. Only shown while a bubble is being created for now;
        // this is where saved bubbles will eventually be listed.
        if (YourDailyBubbleManager.isCreating || YourDailyBubbleManager.bubbles.isNotEmpty) ...[
          const SizedBox(height: 12),
          YourDailyBubbleRow(),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Icon(
                          Icons.insert_chart_outlined,
                          size: 24,
                          color: _selectedTabIndex == 0 ? Colors.black : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Icon(
                          Icons.videocam_outlined,
                          size: 24,
                          color: _selectedTabIndex == 1 ? Colors.black : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Icon(
                          Icons.folder_outlined,
                          size: 24,
                          color: _selectedTabIndex == 2 ? Colors.black : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 2,
                child: Stack(
                  children: [
                    Container(width: double.infinity, height: 2, color: Colors.transparent),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      left: MediaQuery.of(context).size.width * _selectedTabIndex / 3,
                      width: MediaQuery.of(context).size.width / 3,
                      child: Container(height: 2, color: Colors.black),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _buildTabContent(),
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
      _safeLoad('UserFollowers', UserFollowers.loadFollowersCountFromStorage),
      _safeLoad('UserFollowing', UserFollowing.loadFollowingCountFromStorage),
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
    const double backgroundHeight = 160.0;

    return Scaffold(
      body: Stack(
        children: [
          if (_backgroundPic != null && _backgroundPic!.existsSync())
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: backgroundHeight,
              child: Stack(
                children: [
                  Image.file(
                    _backgroundPic!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: backgroundHeight,
                    key: ValueKey(_backgroundPic!.path + _backgroundPic!.lastModifiedSync().toString()),
                    errorBuilder: (context, error, stackTrace) {
                      return Container(color: Colors.white);
                    },
                  ),
                  if (_showSeparator)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(height: 3, color: _separatorColor),
                    ),
                ],
              ),
            ),
          if (_backgroundPic == null || !_backgroundPic!.existsSync())
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: backgroundHeight,
              child: Container(color: Colors.white),
            ),
          Positioned(
            top: backgroundHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(color: Colors.white),
          ),
          const ProfileWidget(),

          // Notification Bell (Top Left)
          Positioned(
            top: 50,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                  StreamBuilder<int>(
                    stream: FriendRequestService().getIncomingRequestCount(),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      if (count == 0) return const SizedBox();
                      return Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Settings Button (Top Right)
          Positioned(
            top: 50,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  );
                },
              ),
            ),
          ),

          // Dark "creating a bubble" overlay — covers the whole screen
          // (including the bell/settings buttons above) until the user
          // finishes or backs out via the X.
          if (YourDailyBubbleManager.isCreating) const YourDailyBubbleCreatorOverlay(),
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
        border: Border.all(color: Colors.grey[400]!, width: borderWidth),
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
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[600]),
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