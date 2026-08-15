import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DailyPhotoManager {
  static File? _globalDailyPhoto;
  static String? _loadedForUid;
  static final List<VoidCallback> _listeners = [];

  static String _fileName(String uid) => 'daily_photo_$uid.jpg';

  static File? get globalDailyPhoto => _globalDailyPhoto;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static void _notifyListeners() {
    print('DailyPhotoManager: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      try { listener(); } catch (e) { print('DailyPhotoManager: listener error: $e'); }
    }
  }

  static void _clearImageCache() {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      print('Image cache cleared');
    } catch (e) {
      print('Error clearing image cache: $e');
    }
  }

  /// Call on logout so the next user starts clean
  static void clearForLogout() {
    _clearImageCache();
    _globalDailyPhoto = null;
    _loadedForUid = null;
    _notifyListeners();
    print('DailyPhotoManager: Cleared for logout');
  }

  /// Save a daily photo for the current user
  static Future<void> setDailyPhoto(File photoFile) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      print('DailyPhotoManager: Starting to save daily photo...');
      print('Source file: ${photoFile.path}');
      print('Source file exists: ${photoFile.existsSync()}');
      print('Source file size: ${photoFile.lengthSync()} bytes');

      final directory = await getApplicationDocumentsDirectory();
      final dailyPhotoPath = '${directory.path}/${_fileName(uid)}';
      print('Target path: $dailyPhotoPath');

      final targetFile = File(dailyPhotoPath);
      if (targetFile.existsSync()) {
        print('Deleting existing daily photo...');
        await targetFile.delete();
        print('Existing photo deleted');
      }

      _clearImageCache();

      final bytes = await photoFile.readAsBytes();
      await targetFile.writeAsBytes(bytes);

      _globalDailyPhoto = targetFile;
      _loadedForUid = uid;

      print('Photo saved successfully!');
      print('Saved file path: ${targetFile.path}');
      print('Saved file exists: ${targetFile.existsSync()}');
      print('Saved file size: ${targetFile.lengthSync()} bytes');

      _notifyListeners();
    } catch (e) {
      print('ERROR in DailyPhotoManager.setDailyPhoto: $e');
      rethrow;
    }
  }

  /// Load daily photo for the current user from local storage
  static Future<void> loadDailyPhotoFromStorage() async {
    final uid = _uid;

    if (uid == null) {
      _globalDailyPhoto = null;
      _loadedForUid = null;
      return;
    }

    // Different user — clear immediately
    if (_loadedForUid != uid) {
      _clearImageCache();
      _globalDailyPhoto = null;
      _loadedForUid = uid;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${_fileName(uid)}');

      if (await file.exists()) {
        _clearImageCache();
        _globalDailyPhoto = file;
        _loadedForUid = uid;
        print('Daily photo loaded from: ${file.path}');
      } else {
        print('No saved daily photo found for $uid');
        _globalDailyPhoto = null;
      }

      _notifyListeners();
    } catch (e) {
      print('Error loading daily photo: $e');
      _globalDailyPhoto = null;
    }
  }

  /// Get the current user's daily photo
  static Future<File?> getDailyPhoto() async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${_fileName(uid)}');

      if (file.existsSync()) {
        _globalDailyPhoto = file;
        _loadedForUid = uid;
        return file;
      } else {
        _globalDailyPhoto = null;
        return null;
      }
    } catch (e) {
      print('ERROR in DailyPhotoManager.getDailyPhoto: $e');
      return null;
    }
  }

  /// Check if a daily photo exists for the current user
  static Future<bool> hasDailyPhoto() async {
    final uid = _uid;
    if (uid == null) return false;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${_fileName(uid)}');
      return file.existsSync();
    } catch (e) {
      print('ERROR in DailyPhotoManager.hasDailyPhoto: $e');
      return false;
    }
  }

  /// Delete the current user's daily photo
  static Future<void> deleteDailyPhoto() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      print('DailyPhotoManager: Deleting daily photo...');

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${_fileName(uid)}');

      if (file.existsSync()) {
        await file.delete();
        print('Daily photo deleted successfully');
      } else {
        print('No daily photo to delete');
      }

      _globalDailyPhoto = null;
      _clearImageCache();
      _notifyListeners();
    } catch (e) {
      print('ERROR in DailyPhotoManager.deleteDailyPhoto: $e');
      rethrow;
    }
  }

  static Future<void> forceRefresh() async {
    print('Force refreshing daily photo...');
    _clearImageCache();
    await loadDailyPhotoFromStorage();
  }
}