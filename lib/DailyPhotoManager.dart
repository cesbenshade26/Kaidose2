import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';

class DailyPhotoManager {
  static File? _globalDailyPhoto;
  static final List<VoidCallback> _listeners = [];
  static const String _dailyPhotoFileName = 'daily_photo.jpg';

  static File? get globalDailyPhoto => _globalDailyPhoto;

  static set globalDailyPhoto(File? file) {
    print('DailyPhotoManager: Setting globalDailyPhoto to: ${file?.path}');

    // Clear any cached image before setting new one
    if (_globalDailyPhoto != null && _globalDailyPhoto != file) {
      _clearImageCache();
    }

    _globalDailyPhoto = file;

    // Save to local storage whenever it changes
    _saveDailyPhotoLocally(file);

    // Notify all listeners when daily photo changes
    print('DailyPhotoManager: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      listener();
    }
    print('DailyPhotoManager: All listeners notified');
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

  /// Save a daily photo to the app's documents directory
  static Future<void> setDailyPhoto(File photoFile) async {
    try {
      print('DailyPhotoManager: Starting to save daily photo...');
      print('Source file: ${photoFile.path}');
      print('Source file exists: ${photoFile.existsSync()}');
      print('Source file size: ${photoFile.lengthSync()} bytes');

      // Get the app's documents directory
      final directory = await getApplicationDocumentsDirectory();
      final dailyPhotoPath = '${directory.path}/$_dailyPhotoFileName';

      print('Target path: $dailyPhotoPath');

      // Delete existing file if it exists
      final targetFile = File(dailyPhotoPath);
      if (targetFile.existsSync()) {
        print('Deleting existing daily photo...');
        await targetFile.delete();
        print('Existing photo deleted');
      }

      // Clear image cache before saving new file
      _clearImageCache();

      // Copy the new photo to the documents directory
      final bytes = await photoFile.readAsBytes();
      await targetFile.writeAsBytes(bytes);

      // Update the global reference to point to the saved file
      _globalDailyPhoto = targetFile;

      print('Photo saved successfully!');
      print('Saved file path: ${targetFile.path}');
      print('Saved file exists: ${targetFile.existsSync()}');
      print('Saved file size: ${targetFile.lengthSync()} bytes');

      // Notify all listeners that we have a new daily photo
      print('DailyPhotoManager: Notifying ${_listeners.length} listeners after save');
      for (var listener in _listeners) {
        listener();
      }

    } catch (e) {
      print('ERROR in DailyPhotoManager.setDailyPhoto: $e');
      rethrow;
    }
  }

  /// Get the current daily photo
  static Future<File?> getDailyPhoto() async {
    try {
      print('DailyPhotoManager: Loading daily photo...');

      // Get the app's documents directory
      final directory = await getApplicationDocumentsDirectory();
      final dailyPhotoPath = '${directory.path}/$_dailyPhotoFileName';
      final file = File(dailyPhotoPath);

      print('Looking for photo at: $dailyPhotoPath');

      if (file.existsSync()) {
        print('Daily photo found!');
        print('File size: ${file.lengthSync()} bytes');
        _globalDailyPhoto = file; // Update global reference
        return file;
      } else {
        print('No daily photo found');
        _globalDailyPhoto = null;
        return null;
      }
    } catch (e) {
      print('ERROR in DailyPhotoManager.getDailyPhoto: $e');
      return null;
    }
  }

  // Load daily photo from local storage on app start
  static Future<void> loadDailyPhotoFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_dailyPhotoFileName');

      if (await file.exists()) {
        // Clear cache before loading
        _clearImageCache();

        _globalDailyPhoto = file;
        print('Daily photo loaded from: ${file.path}');

        // Notify listeners that we loaded a daily photo
        for (var listener in _listeners) {
          listener();
        }
      } else {
        print('No saved daily photo found');
        _globalDailyPhoto = null;
      }
    } catch (e) {
      print('Error loading daily photo: $e');
      _globalDailyPhoto = null;
    }
  }

  // Save daily photo to local storage
  static Future<void> _saveDailyPhotoLocally(File? file) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final savedFile = File('${directory.path}/$_dailyPhotoFileName');

      if (file != null) {
        // Delete existing file first to avoid conflicts
        if (await savedFile.exists()) {
          await savedFile.delete();
          print('Deleted existing daily photo');
        }

        // Clear image cache before saving new file
        _clearImageCache();

        // Copy the file to our app's documents directory
        final bytes = await file.readAsBytes();
        await savedFile.writeAsBytes(bytes);

        // Update the global reference to point to the saved file
        if (_globalDailyPhoto?.path != savedFile.path) {
          _globalDailyPhoto = savedFile;
        }

        print('Daily photo saved to: ${savedFile.path}');
      } else {
        // If file is null (removing daily photo), delete the saved file
        if (await savedFile.exists()) {
          await savedFile.delete();
          print('Daily photo removed from storage');
        }
        _globalDailyPhoto = null;
        _clearImageCache();
      }
    } catch (e) {
      print('Error saving daily photo: $e');
    }
  }

  /// Check if a daily photo exists
  static Future<bool> hasDailyPhoto() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dailyPhotoPath = '${directory.path}/$_dailyPhotoFileName';
      final file = File(dailyPhotoPath);
      return file.existsSync();
    } catch (e) {
      print('ERROR in DailyPhotoManager.hasDailyPhoto: $e');
      return false;
    }
  }

  /// Delete the current daily photo
  static Future<void> deleteDailyPhoto() async {
    try {
      print('DailyPhotoManager: Deleting daily photo...');

      final directory = await getApplicationDocumentsDirectory();
      final dailyPhotoPath = '${directory.path}/$_dailyPhotoFileName';
      final file = File(dailyPhotoPath);

      if (file.existsSync()) {
        await file.delete();
        print('Daily photo deleted successfully');
      } else {
        print('No daily photo to delete');
      }

      _globalDailyPhoto = null;
      _clearImageCache();

      // Notify listeners that photo was deleted
      for (var listener in _listeners) {
        listener();
      }
    } catch (e) {
      print('ERROR in DailyPhotoManager.deleteDailyPhoto: $e');
      rethrow;
    }
  }

  // Force refresh the current daily photo (useful for debugging)
  static Future<void> forceRefresh() async {
    print('Force refreshing daily photo...');
    _clearImageCache();
    await loadDailyPhotoFromStorage();
  }
}