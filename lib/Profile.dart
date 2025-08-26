import 'package:flutter/material.dart';
import 'dart:io';
import 'ProfilePicManager.dart'; // Import the separate manager file (includes DefaultProfilePic)
import 'BackgroundPicManager.dart'; // Import the background manager
import 'BioManager.dart'; // Import the reliable Bio manager
import 'UserManager.dart'; // Import the username manager
import 'ProfilePic.dart'; // Import your ProfilePic screen
import 'BackgroundPic.dart'; // Import your BackgroundPic screen
import 'SettingBar.dart'; // Import the SettingBar screen
import 'Bio.dart'; // Import the Bio screen

// Profile Widget for the main Profile screen - Updated with custom alignment behavior
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
  String? _username; // Add username variable
  VoidCallback? _profilePicListener;
  VoidCallback? _backgroundPicListener;
  VoidCallback? _bioListener;
  VoidCallback? _usernameListener; // Add username listener

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Get any existing pictures and settings immediately
    _profilePic = ProfilePicManager.globalProfilePic;
    _backgroundPic = BackgroundPicManager.globalBackgroundPic;
    _showSeparator = BackgroundPicManager.showSeparator;
    _separatorColor = BackgroundPicManager.separatorColor;
    _loadBioData();
    _loadUsernameData(); // Add username loading

    // Load from storage
    _loadFromStorage();

    // Create listener for profile pic changes
    _profilePicListener = () {
      print('ProfileWidget: Profile pic changed!');
      if (mounted) {
        setState(() {
          _profilePic = ProfilePicManager.globalProfilePic;
        });
      }
    };

    // Create listener for background pic changes
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

    // Create listener for bio changes - SIMPLIFIED to avoid infinite loop
    _bioListener = () {
      print('ProfileWidget: Bio listener triggered');
      if (mounted) {
        setState(() {
          _loadBioData();
        });
      }
    };

    // Create listener for username changes
    _usernameListener = () {
      print('ProfileWidget: Username listener triggered');
      if (mounted) {
        setState(() {
          _loadUsernameData();
        });
      }
    };

    // Add the listeners
    ProfilePicManager.addListener(_profilePicListener!);
    BackgroundPicManager.addListener(_backgroundPicListener!);
    BioManager.addListener(_bioListener!);
    UserManager.addListener(_usernameListener!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground, refresh bio
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Simple refresh when returning from another screen
    if (mounted) {
      _loadBioData();
    }
  }

  Future<void> _loadFromStorage() async {
    await ProfilePicManager.loadProfilePicFromStorage();
    await BackgroundPicManager.loadBackgroundPicFromStorage();
    await BioManager.loadBioFromStorage();
    await UserManager.loadUsernameFromStorage(); // Add username loading
    if (mounted) {
      setState(() {
        _profilePic = ProfilePicManager.globalProfilePic;
        _backgroundPic = BackgroundPicManager.globalBackgroundPic;
        _showSeparator = BackgroundPicManager.showSeparator;
        _separatorColor = BackgroundPicManager.separatorColor;
        _loadBioData();
        _loadUsernameData(); // Add username loading
      });
      print('Bio loaded in ProfileWidget: "$_bio"');
      print('Username loaded in ProfileWidget: "$_username"');
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
    super.dispose();
  }

  Widget _buildBioText(double screenWidth) {
    const double profilePicSize = 160.0;
    final double profilePicStartX = (screenWidth - profilePicSize) / 2; // Left edge of profile pic

    // If no bio, show "Tap to add bio" message
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
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
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

    // Handle custom alignment based on profile pic position
    switch (_textAlign) {
      case TextAlign.left:
      // Text starts at the left edge of the profile pic
        return Padding(
          padding: EdgeInsets.only(left: profilePicStartX, right: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: bioText,
          ),
        );

      case TextAlign.right:
      // Text ends at the right edge of the profile pic
        return Padding(
          padding: EdgeInsets.only(left: 24, right: profilePicStartX),
          child: Align(
            alignment: Alignment.centerRight,
            child: bioText,
          ),
        );

      case TextAlign.center:
      default:
      // Center the text normally
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            child: bioText,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40), // Changed from 80 to 40 (moved up by 40px = 1/4 of 160px height)
          // Profile picture with background functionality
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfilePicScreen(),
                ),
              ).then((_) {
                // Force refresh when returning from ProfilePicScreen
                print('Returned from ProfilePicScreen, refreshing...');
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
                border: Border.all(
                  color: Colors.grey[400]!,
                  width: 3,
                ),
              ),
              child: ClipOval(
                child: _profilePic != null && _profilePic!.existsSync()
                    ? Image.file(
                  _profilePic!,
                  fit: BoxFit.cover,
                  width: 160,
                  height: 160,
                  // Add a unique key to force Flutter to reload the image
                  key: ValueKey(_profilePic!.path + _profilePic!.lastModifiedSync().toString()),
                  errorBuilder: (context, error, stackTrace) {
                    print('Error loading profile image: $error');
                    return const DefaultProfilePic(size: 160, borderWidth: 0);
                  },
                )
                    : const DefaultProfilePic(size: 160, borderWidth: 0),
              ),
            ),
          ),

          // Username display
          const SizedBox(height: 12),
          if (_username != null && _username!.isNotEmpty)
            Text(
              _username!,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),

          // Bio text display with custom alignment behavior OR tap to edit
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              // Navigate to Bio screen and wait for result
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BioScreen(),
                ),
              );

              // Always refresh bio when returning from Bio screen
              print('Returned from BioScreen, refreshing bio data...');
              await BioManager.loadBioFromStorage(); // Reload from storage to be sure
              setState(() {
                _loadBioData();
              });
            },
            child: _buildBioText(screenWidth),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// Main Profile Page - UPDATED WITH BACKGROUND INTEGRATION
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

    // Get any existing background pic and settings immediately
    _backgroundPic = BackgroundPicManager.globalBackgroundPic;
    _showSeparator = BackgroundPicManager.showSeparator;
    _separatorColor = BackgroundPicManager.separatorColor;

    // Load from storage
    _loadBackgroundFromStorage();

    // Create listener for background pic changes
    _backgroundPicListener = () {
      print('ProfilePage: Background pic or settings changed!');
      if (mounted) {
        setState(() {
          _backgroundPic = BackgroundPicManager.globalBackgroundPic;
          _showSeparator = BackgroundPicManager.showSeparator;
          _separatorColor = BackgroundPicManager.separatorColor;
        });
      }
    };

    // Add the listener
    BackgroundPicManager.addListener(_backgroundPicListener!);

    // IMPORTANT: Load bio data when the profile page initializes
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await BioManager.loadBioFromStorage();
    await UserManager.loadUsernameFromStorage(); // Add username loading
    print('ProfilePage: Initial bio and username load complete');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Force refresh when returning to this screen
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
    // Background stays at 160px height, profile pic starts at 40px
    const double backgroundHeight = 160.0;

    return Scaffold(
      body: Stack(
        children: [
          // Background image (if exists) - only covers top portion
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
                    // Add a unique key to force Flutter to reload the image
                    key: ValueKey(_backgroundPic!.path + _backgroundPic!.lastModifiedSync().toString()),
                    errorBuilder: (context, error, stackTrace) {
                      print('Error loading background image: $error');
                      return Container(color: Colors.white);
                    },
                  ),
                  // Separator line at bottom of background (if enabled)
                  if (_showSeparator)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        color: _separatorColor,
                      ),
                    ),
                ],
              ),
            ),
          // If no background, use white background for top portion
          if (_backgroundPic == null || !_backgroundPic!.existsSync())
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: backgroundHeight,
              child: Container(color: Colors.white),
            ),
          // White background for bottom portion (always present)
          Positioned(
            top: backgroundHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(color: Colors.white),
          ),
          // Content overlay
          SingleChildScrollView(
            child: Column(
              children: [
                const ProfileWidget(), // Profile picture and bio centered in top
                const SizedBox(height: 32),
                // Add more profile content here
              ],
            ),
          ),
          // Settings icon positioned in top right
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
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
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