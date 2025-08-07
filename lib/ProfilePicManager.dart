import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// ProfilePicManager class with notification system and local storage
class ProfilePicManager {
  static File? _globalProfilePic;
  static final List<VoidCallback> _listeners = [];
  static const String _profilePicFileName = 'user_profile_picture.png';

  static File? get globalProfilePic => _globalProfilePic;

  static set globalProfilePic(File? file) {
    print('ProfilePicManager: Setting globalProfilePic to: ${file?.path}');

    // Clear any cached image before setting new one
    if (_globalProfilePic != null && _globalProfilePic != file) {
      _clearImageCache();
    }

    _globalProfilePic = file;

    // Save to local storage whenever it changes
    _saveProfilePicLocally(file);

    // Notify all listeners when profile pic changes
    print('ProfilePicManager: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      listener();
    }
    print('ProfilePicManager: All listeners notified');
  }

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  // Clear any cached images to prevent display issues
  static void _clearImageCache() {
    try {
      // Force Flutter to clear its image cache
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      print('Image cache cleared');
    } catch (e) {
      print('Error clearing image cache: $e');
    }
  }

  // Load profile picture from local storage on app start
  static Future<void> loadProfilePicFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_profilePicFileName');

      if (await file.exists()) {
        // Clear cache before loading
        _clearImageCache();

        _globalProfilePic = file;
        print('Profile picture loaded from: ${file.path}');

        // Notify listeners that we loaded a profile pic
        for (var listener in _listeners) {
          listener();
        }
      } else {
        print('No saved profile picture found');
        _globalProfilePic = null;
      }
    } catch (e) {
      print('Error loading profile picture: $e');
      _globalProfilePic = null;
    }
  }

  // Save profile picture to local storage
  static Future<void> _saveProfilePicLocally(File? file) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final savedFile = File('${directory.path}/$_profilePicFileName');

      if (file != null) {
        // Delete existing file first to avoid conflicts
        if (await savedFile.exists()) {
          await savedFile.delete();
          print('Deleted existing profile picture');
        }

        // Clear image cache before saving new file
        _clearImageCache();

        // Copy the file to our app's documents directory with a unique name to avoid caching issues
        final bytes = await file.readAsBytes();
        await savedFile.writeAsBytes(bytes);

        // Update the global reference to point to the saved file
        if (_globalProfilePic?.path != savedFile.path) {
          _globalProfilePic = savedFile;
        }

        print('Profile picture saved to: ${savedFile.path}');
      } else {
        // If file is null (removing profile pic), delete the saved file
        if (await savedFile.exists()) {
          await savedFile.delete();
          print('Profile picture removed from storage');
        }
        _globalProfilePic = null;
        _clearImageCache();
      }
    } catch (e) {
      print('Error saving profile picture: $e');
    }
  }

  // Force refresh the current profile picture (useful for debugging)
  static Future<void> forceRefresh() async {
    print('Force refreshing profile picture...');
    _clearImageCache();
    await loadProfilePicFromStorage();
  }

  // Get the stored profile picture file path (useful for API integration later)
  static Future<String?> getStoredProfilePicPath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_profilePicFileName');

      if (await file.exists()) {
        return file.path;
      }
    } catch (e) {
      print('Error getting stored profile pic path: $e');
    }
    return null;
  }

  // Clean up old temporary files (call this periodically to free up space)
  static Future<void> cleanupTempFiles() async {
    try {
      final tempDir = Directory.systemTemp;
      final files = tempDir.listSync();

      for (var file in files) {
        if (file is File && file.path.contains('cropped_profile_')) {
          try {
            final stats = await file.stat();
            final age = DateTime.now().difference(stats.modified);

            // Delete temp files older than 1 hour
            if (age.inHours > 1) {
              await file.delete();
              print('Deleted old temp file: ${file.path}');
            }
          } catch (e) {
            print('Error checking temp file: $e');
          }
        }
      }
    } catch (e) {
      print('Error cleaning up temp files: $e');
    }
  }
}

// Default Profile Picture Widget
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
            // Head circle
            Positioned(
              top: size * 0.1875, // 30/160 ratio
              child: Container(
                width: size * 0.3125, // 50/160 ratio
                height: size * 0.3125,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[600],
                ),
              ),
            ),
            // Shoulders
            Positioned(
              bottom: -size * 0.125, // -20/160 ratio
              child: Container(
                width: size * 0.875, // 140/160 ratio
                height: size * 0.5, // 80/160 ratio
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(size * 0.4375), // 70/160 ratio
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