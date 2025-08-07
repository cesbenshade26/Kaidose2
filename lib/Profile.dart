import 'package:flutter/material.dart';
import 'dart:io';
import 'ProfilePicManager.dart'; // Import the separate manager file (includes DefaultProfilePic)
import 'ProfilePic.dart'; // Import your ProfilePic screen
import 'SettingBar.dart'; // Import the SettingBar screen

// Profile Widget for the main Profile screen - CORRECTED VERSION
class ProfileWidget extends StatefulWidget {
  const ProfileWidget({Key? key}) : super(key: key);

  @override
  State<ProfileWidget> createState() => _ProfileWidgetState();
}

class _ProfileWidgetState extends State<ProfileWidget> {
  File? _profilePic;
  VoidCallback? _profilePicListener;

  @override
  void initState() {
    super.initState();

    // Get any existing profile pic immediately
    _profilePic = ProfilePicManager.globalProfilePic;

    // Load from storage
    _loadFromStorage();

    // Create listener for future changes
    _profilePicListener = () {
      print('ProfileWidget: Profile pic changed!');
      if (mounted) {
        setState(() {
          _profilePic = ProfilePicManager.globalProfilePic;
        });
      }
    };

    // Add the listener
    ProfilePicManager.addListener(_profilePicListener!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Force refresh when returning to this screen
    setState(() {
      _profilePic = ProfilePicManager.globalProfilePic;
    });
  }

  Future<void> _loadFromStorage() async {
    await ProfilePicManager.loadProfilePicFromStorage();
    if (mounted) {
      setState(() {
        _profilePic = ProfilePicManager.globalProfilePic;
      });
    }
  }

  @override
  void dispose() {
    if (_profilePicListener != null) {
      ProfilePicManager.removeListener(_profilePicListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('ProfileWidget building... _profilePic: $_profilePic');
    print('ProfilePicManager.globalProfilePic: ${ProfilePicManager.globalProfilePic}');

    return Center(
      child: Column(
        children: [
          const SizedBox(height: 80),
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
                    print('Error loading image: $error');
                    return const DefaultProfilePic(size: 160, borderWidth: 0);
                  },
                )
                    : const DefaultProfilePic(size: 160, borderWidth: 0),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// Main Profile Page
class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const SingleChildScrollView(
            child: Column(
              children: [
                ProfileWidget(), // Profile picture centered in top
                SizedBox(height: 32),
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