import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

// BackgroundPicManager class with notification system and local storage
class BackgroundPicManager {
  static File? _globalBackgroundPic;
  static bool _showSeparator = false;
  static Color _separatorColor = Colors.black;
  static final List<VoidCallback> _listeners = [];
  static const String _backgroundPicFileName = 'user_background_picture.png';
  static const String _settingsFileName = 'background_settings.json';

  static File? get globalBackgroundPic => _globalBackgroundPic;
  static bool get showSeparator => _showSeparator;
  static Color get separatorColor => _separatorColor;

  static set globalBackgroundPic(File? file) {
    print('BackgroundPicManager: Setting globalBackgroundPic to: ${file?.path}');

    // Clear any cached image before setting new one
    if (_globalBackgroundPic != null && _globalBackgroundPic != file) {
      _clearImageCache();
    }

    _globalBackgroundPic = file;

    // Save to local storage whenever it changes
    _saveBackgroundPicLocally(file);

    // Notify all listeners when background pic changes
    print('BackgroundPicManager: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      listener();
    }
    print('BackgroundPicManager: All listeners notified');
  }

  static void setSeparatorSettings(bool show, Color color) {
    _showSeparator = show;
    _separatorColor = color;
    _saveSettingsLocally();

    // Notify listeners when separator settings change
    for (var listener in _listeners) {
      listener();
    }
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
      print('Background image cache cleared');
    } catch (e) {
      print('Error clearing background image cache: $e');
    }
  }

  // Load background picture and settings from local storage on app start
  static Future<void> loadBackgroundPicFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_backgroundPicFileName');

      if (await file.exists()) {
        // Clear cache before loading
        _clearImageCache();

        _globalBackgroundPic = file;
        print('Background picture loaded from: ${file.path}');
      } else {
        print('No saved background picture found');
        _globalBackgroundPic = null;
      }

      // Load separator settings
      await _loadSettingsFromStorage();

      // Notify listeners that we loaded everything
      for (var listener in _listeners) {
        listener();
      }
    } catch (e) {
      print('Error loading background picture: $e');
      _globalBackgroundPic = null;
    }
  }

  // Save separator settings to local storage
  static Future<void> _saveSettingsLocally() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final settingsFile = File('${directory.path}/$_settingsFileName');

      final settings = {
        'showSeparator': _showSeparator,
        'separatorColor': _separatorColor.value,
      };

      await settingsFile.writeAsString(json.encode(settings));
      print('Background settings saved: $settings');
    } catch (e) {
      print('Error saving background settings: $e');
    }
  }

  // Load separator settings from local storage
  static Future<void> _loadSettingsFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final settingsFile = File('${directory.path}/$_settingsFileName');

      if (await settingsFile.exists()) {
        final settingsString = await settingsFile.readAsString();
        final settings = json.decode(settingsString);

        _showSeparator = settings['showSeparator'] ?? false;
        _separatorColor = Color(settings['separatorColor'] ?? Colors.black.value);

        print('Background settings loaded: showSeparator=$_showSeparator, color=$_separatorColor');
      } else {
        print('No saved background settings found, using defaults');
      }
    } catch (e) {
      print('Error loading background settings: $e');
      _showSeparator = false;
      _separatorColor = Colors.black;
    }
  }

  // Save background picture to local storage
  static Future<void> _saveBackgroundPicLocally(File? file) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final savedFile = File('${directory.path}/$_backgroundPicFileName');

      if (file != null) {
        // Delete existing file first to avoid conflicts
        if (await savedFile.exists()) {
          await savedFile.delete();
          print('Deleted existing background picture');
        }

        // Clear image cache before saving new file
        _clearImageCache();

        // Copy the file to our app's documents directory with a unique name to avoid caching issues
        final bytes = await file.readAsBytes();
        await savedFile.writeAsBytes(bytes);

        // Update the global reference to point to the saved file
        if (_globalBackgroundPic?.path != savedFile.path) {
          _globalBackgroundPic = savedFile;
        }

        print('Background picture saved to: ${savedFile.path}');
      } else {
        // If file is null (removing background pic), delete the saved file
        if (await savedFile.exists()) {
          await savedFile.delete();
          print('Background picture removed from storage');
        }
        _globalBackgroundPic = null;
        _clearImageCache();
      }
    } catch (e) {
      print('Error saving background picture: $e');
    }
  }

  // Force refresh the current background picture (useful for debugging)
  static Future<void> forceRefresh() async {
    print('Force refreshing background picture...');
    _clearImageCache();
    await loadBackgroundPicFromStorage();
  }

  // Get the stored background picture file path (useful for API integration later)
  static Future<String?> getStoredBackgroundPicPath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_backgroundPicFileName');

      if (await file.exists()) {
        return file.path;
      }
    } catch (e) {
      print('Error getting stored background pic path: $e');
    }
    return null;
  }

  // Clean up old temporary files (call this periodically to free up space)
  static Future<void> cleanupTempFiles() async {
    try {
      final tempDir = Directory.systemTemp;
      final files = tempDir.listSync();

      for (var file in files) {
        if (file is File && file.path.contains('cropped_background_')) {
          try {
            final stats = await file.stat();
            final age = DateTime.now().difference(stats.modified);

            // Delete temp files older than 1 hour
            if (age.inHours > 1) {
              await file.delete();
              print('Deleted old background temp file: ${file.path}');
            }
          } catch (e) {
            print('Error checking background temp file: $e');
          }
        }
      }
    } catch (e) {
      print('Error cleaning up background temp files: $e');
    }
  }
}