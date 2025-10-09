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
      print('ProfileWidget: Profile pic changed!');
      if (mounted) {
        setState(() {
          _profilePic = ProfilePicManager.globalProfilePic;
        });
      }
    };

    _backgroundPicListener = () {
      print('ProfileWidget: Background pic or settings changed!');
      if (mounted) {
        setState(() {
          _backgroundPic = BackgroundPicManager.globalBackgroundPic;
          _showSeparator = BackgroundPicManager.showSeparator;
          _separatorColor = BackgroundPicManager.separatorColor;
        });
      }
    };

    _bioListener = () {
      print('ProfileWidget: Bio listener triggered');
      if (mounted) {
        setState(() {
          _loadBioData();
        });
      }
    };

    _usernameListener = () {
      print('ProfileWidget: Username listener triggered');
      if (mounted) {
        setState(() {
          _loadUsernameData();
        });
      }
    };

    _followersListener = () {
      print('ProfileWidget: Followers listener triggered');
      if (mounted) {
        setState(() {
          _loadFollowersData();
        });
      }
    };

    _followingListener = () {
      print('ProfileWidget: Following listener triggered');
      if (mounted) {
        setState(() {
          _loadFollowingData();
        });
      }
    };

    ProfilePicManager.addListener(_profilePicListener!);
    BackgroundPicManager.addListener(_backgroundPicListener!);
    BioManager.addListener(_bioListener!);
    UserManager.addListener(_usernameListener!);
    UserFollowers.addListener(_followersListener!);
    UserFollowing.addListener(_followingListener!);
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

  void _loadUsernameData() {
    _username = UserManager.globalUsername;
    print('Username loaded in ProfileWidget: "$_username"');
  }

  void _loadFollowersData() {
    _followersCount = UserFollowers.followersCount;
    print('Followers count loaded in ProfileWidget: $_followersCount');
  }

  void _loadFollowingData() {
    _followingCount = UserFollowing.followingCount;
    print('Following count loaded in ProfileWidget: $_followingCount');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted) {
      _loadBioData();
    }
  }

  Future<void> _loadFromStorage() async {
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
    if (_profilePicListener != null) {
      ProfilePicManager.removeListener(_profilePicListener!);
    }
    if (_backgroundPicListener != null) {
      BackgroundPicManager.removeListener(_backgroundPicListener!);
    }
    if (_bioListener != null) {
      BioManager.removeListener(_bioListener!);
    }
    if (_usernameListener != null) {
      UserManager.removeListener(_usernameListener!);
    }
    if (_followersListener != null) {
      UserFollowers.removeListener(_followersListener!);
    }
    if (_followingListener != null) {
      UserFollowing.removeListener(_followingListener!);
    }
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
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
          child: Container(width: double.infinity, child: bioText),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: Column(
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
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 0;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Icon(Icons.grid_on, size: 24, color: _selectedTabIndex == 0 ? Colors.black : Colors.grey),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 1;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Icon(Icons.videocam_outlined, size: 24, color: _selectedTabIndex == 1 ? Colors.black : Colors.grey),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 2;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Icon(Icons.person_outline, size: 24, color: _selectedTabIndex == 2 ? Colors.black : Colors.grey),
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
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
          const SizedBox(height: 32),
        ],
      ),
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

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await BioManager.loadBioFromStorage();
    await UserManager.loadUsernameFromStorage();
    await UserFollowers.loadFollowersCountFromStorage();
    await UserFollowing.loadFollowingCountFromStorage();
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
          SingleChildScrollView(
            child: Column(
              children: [
                const ProfileWidget(),
                const SizedBox(height: 32),
              ],
            ),
          ),
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
        ],
      ),
    );
  }
}