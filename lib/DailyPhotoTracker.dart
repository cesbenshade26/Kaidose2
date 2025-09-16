import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

class DailyPhotoTracker {
  static List<File> _todaysPhotos = [];
  static final List<VoidCallback> _listeners = [];
  static String? _currentDate;

  static List<File> get todaysPhotos => _todaysPhotos;
  static bool get hasPhotosToday => _todaysPhotos.isNotEmpty;
  static int get photoCount => _todaysPhotos.length;

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    print('DailyPhotoTracker: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      listener();
    }
  }

  // Clear any cached images to prevent display issues
  static void _clearImageCache() {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      print('Image cache cleared');
    } catch (e) {
      print('Error clearing image cache: $e');
    }
  }

  // Get current date string (YYYY-MM-DD format)
  static String _getCurrentDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // Get the folder path for today's photos
  static Future<String> _getTodaysFolderPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final dateString = _getCurrentDateString();
    return '${directory.path}/daily_photos/$dateString';
  }

  // Check if we've crossed into a new day
  static bool _isNewDay() {
    final currentDate = _getCurrentDateString();
    if (_currentDate != currentDate) {
      _currentDate = currentDate;
      return true;
    }
    return false;
  }

  // Initialize the tracker - load today's photos
  static Future<void> initialize() async {
    print('DailyPhotoTracker: Initializing...');

    // Check if it's a new day
    if (_isNewDay()) {
      print('New day detected, clearing photos list');
      _todaysPhotos.clear();
    }

    try {
      final folderPath = await _getTodaysFolderPath();
      final folder = Directory(folderPath);

      if (await folder.exists()) {
        final files = await folder.list().toList();
        _todaysPhotos.clear();

        // Sort files by name (which includes timestamp)
        files.sort((a, b) => a.path.compareTo(b.path));

        for (var file in files) {
          if (file is File && file.path.endsWith('.jpg')) {
            _todaysPhotos.add(file);
          }
        }

        print('Loaded ${_todaysPhotos.length} photos for today');
      } else {
        print('No folder exists for today yet');
        _todaysPhotos.clear();
      }

      _notifyListeners();
    } catch (e) {
      print('Error initializing DailyPhotoTracker: $e');
      _todaysPhotos.clear();
    }
  }

  // Add a new photo for today
  static Future<File> addPhoto(File sourcePhoto) async {
    print('DailyPhotoTracker: Adding new photo...');

    try {
      // Ensure folder exists
      final folderPath = await _getTodaysFolderPath();
      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      // Create unique filename with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'daily_photo_$timestamp.jpg';
      final filePath = '$folderPath/$fileName';

      // Copy photo to today's folder
      final bytes = await sourcePhoto.readAsBytes();
      final savedFile = File(filePath);
      await savedFile.writeAsBytes(bytes);

      // Add to today's list
      _todaysPhotos.add(savedFile);

      print('Photo saved: $filePath');
      print('Total photos today: ${_todaysPhotos.length}');

      // Clear cache and notify listeners
      _clearImageCache();
      _notifyListeners();

      return savedFile;
    } catch (e) {
      print('Error adding photo: $e');
      rethrow;
    }
  }

  // Get photo by index
  static File? getPhotoByIndex(int index) {
    if (index >= 0 && index < _todaysPhotos.length) {
      return _todaysPhotos[index];
    }
    return null;
  }

  // Get the latest photo
  static File? getLatestPhoto() {
    if (_todaysPhotos.isNotEmpty) {
      return _todaysPhotos.last;
    }
    return null;
  }

  // Delete a specific photo
  static Future<void> deletePhoto(int index) async {
    if (index >= 0 && index < _todaysPhotos.length) {
      try {
        final file = _todaysPhotos[index];
        if (await file.exists()) {
          await file.delete();
        }
        _todaysPhotos.removeAt(index);

        _clearImageCache();
        _notifyListeners();

        print('Photo deleted. Remaining photos: ${_todaysPhotos.length}');
      } catch (e) {
        print('Error deleting photo: $e');
      }
    }
  }

  // Clear all photos for today (useful for testing)
  static Future<void> clearTodaysPhotos() async {
    try {
      final folderPath = await _getTodaysFolderPath();
      final folder = Directory(folderPath);

      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }

      _todaysPhotos.clear();
      _clearImageCache();
      _notifyListeners();

      print('All photos for today cleared');
    } catch (e) {
      print('Error clearing today\'s photos: $e');
    }
  }

  // Check if it's past midnight and reset if needed
  static Future<void> checkAndResetIfNewDay() async {
    if (_isNewDay()) {
      print('New day detected! Resetting photos...');
      _todaysPhotos.clear();
      _notifyListeners();
    }
  }
}