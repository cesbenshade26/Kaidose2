import 'package:flutter/material.dart';
import 'dart:io';
import 'ProfilePicManager.dart'; // Import the separate manager file (includes DefaultProfilePic)
import 'BackgroundPicManager.dart'; // Import the background manager
import 'ProfilePic.dart'; // Import your ProfilePic screen
import 'BackgroundPic.dart'; // Import your BackgroundPic screen
import 'SettingBar.dart'; // Import the SettingBar screen

// Profile Widget for the main Profile screen - UPDATED WITH BACKGROUND FUNCTIONALITY
class ProfileWidget extends StatefulWidget {
  const ProfileWidget({Key? key}) : super(key: key);

  @override
  State<ProfileWidget> createState() => _ProfileWidgetState();
}

class _ProfileWidgetState extends State<ProfileWidget> {
  File? _profilePic;
  File? _backgroundPic;
  VoidCallback? _profilePicListener;
  VoidCallback? _backgroundPicListener;

  @override
  void initState() {
    super.initState();

    // Get any existing pictures immediately
    _profilePic = ProfilePicManager.globalProfilePic;
    _backgroundPic = BackgroundPicManager.globalBackgroundPic;

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
      print('ProfileWidget: Background pic changed!');
      if (mounted) {
        setState(() {
          _backgroundPic = BackgroundPicManager.globalBackgroundPic;
        });
      }
    };

    // Add the listeners
    ProfilePicManager.addListener(_profilePicListener!);
    BackgroundPicManager.addListener(_backgroundPicListener!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Force refresh when returning to this screen
    setState(() {
      _profilePic = ProfilePicManager.globalProfilePic;
      _backgroundPic = BackgroundPicManager.globalBackgroundPic;
    });
  }

  Future<void> _loadFromStorage() async {
    await ProfilePicManager.loadProfilePicFromStorage();
    await BackgroundPicManager.loadBackgroundPicFromStorage();
    if (mounted) {
      setState(() {
        _profilePic = ProfilePicManager.globalProfilePic;
        _backgroundPic = BackgroundPicManager.globalBackgroundPic;
      });
    }
  }

  @override
  void dispose() {
    if (_profilePicListener != null) {
      ProfilePicManager.removeListener(_profilePicListener!);
    }
    if (_backgroundPicListener != null) {
      BackgroundPicManager.removeListener(_backgroundPicListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('ProfileWidget building... _profilePic: $_profilePic, _backgroundPic: $_backgroundPic');
    print('ProfilePicManager.globalProfilePic: ${ProfilePicManager.globalProfilePic}');
    print('BackgroundPicManager.globalBackgroundPic: ${BackgroundPicManager.globalBackgroundPic}');

    return Center(
      child: Column(
        children: [
          const SizedBox(height: 80),
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
          const SizedBox(height: 20),
          // Background picture button
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BackgroundPicScreen(),
                ),
              ).then((_) {
                // Force refresh when returning from BackgroundPicScreen
                print('Returned from BackgroundPicScreen, refreshing...');
                setState(() {
                  _backgroundPic = BackgroundPicManager.globalBackgroundPic;
                });
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _backgroundPic != null ? Colors.blue : Colors.grey[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _backgroundPic != null ? Icons.wallpaper : Icons.add_photo_alternate,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _backgroundPic != null ? 'Change Background' : 'Add Background',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
  VoidCallback? _backgroundPicListener;

  @override
  void initState() {
    super.initState();

    // Get any existing background pic immediately
    _backgroundPic = BackgroundPicManager.globalBackgroundPic;

    // Load from storage
    _loadBackgroundFromStorage();

    // Create listener for background pic changes
    _backgroundPicListener = () {
      print('ProfilePage: Background pic changed!');
      if (mounted) {
        setState(() {
          _backgroundPic = BackgroundPicManager.globalBackgroundPic;
        });
      }
    };

    // Add the listener
    BackgroundPicManager.addListener(_backgroundPicListener!);
  }

  Future<void> _loadBackgroundFromStorage() async {
    await BackgroundPicManager.loadBackgroundPicFromStorage();
    if (mounted) {
      setState(() {
        _backgroundPic = BackgroundPicManager.globalBackgroundPic;
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
    // Calculate the background height: from top to midline of profile pic
    // Profile pic starts at 80px from top, has 160px height, so midline is at 80 + 80 = 160px
    const double backgroundHeight = 80 + 80; // Top padding + half profile pic height

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
              child: Image.file(
                _backgroundPic!,
                fit: BoxFit.cover,
                // Add a unique key to force Flutter to reload the image
                key: ValueKey(_backgroundPic!.path + _backgroundPic!.lastModifiedSync().toString()),
                errorBuilder: (context, error, stackTrace) {
                  print('Error loading background image: $error');
                  return Container(color: Colors.white);
                },
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
                const ProfileWidget(), // Profile picture centered in top
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