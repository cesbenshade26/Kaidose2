import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

/// Tracks today's YourDaily photos for the CURRENT user only.
/// All storage is scoped under daily_photos/{uid}/{date}/ so switching
/// accounts never bleeds one user's photos into another's story.
class DailyPhotoTracker {
  static List<File> _todaysPhotos = [];
  static String? _currentDate;
  static String? _loadedForUid;
  static final List<VoidCallback> _listeners = [];

  static List<File> get todaysPhotos => List.unmodifiable(_todaysPhotos);
  static bool get hasPhotosToday => _todaysPhotos.isNotEmpty;

  static String get _today => DateTime.now().toIso8601String().split('T')[0];
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static void _notifyListeners() {
    for (var listener in _listeners) {
      try { listener(); } catch (e) { print('DailyPhotoTracker: listener error: $e'); }
    }
  }

  /// Call on logout so next user starts with a clean state
  static void clearForLogout() {
    _todaysPhotos = [];
    _currentDate = null;
    _loadedForUid = null;
    _notifyListeners();
    print('DailyPhotoTracker: Cleared for logout');
  }

  /// Initialize / reload for the current user and today's date
  static Future<void> initialize() async {
    print('DailyPhotoTracker: Initializing...');
    final uid = _uid;

    // If UID changed (different user logged in), clear old data first
    if (_loadedForUid != uid) {
      _todaysPhotos = [];
      _loadedForUid = uid;
      _currentDate = null;
    }

    if (uid == null) {
      print('DailyPhotoTracker: No user logged in');
      return;
    }

    final today = _today;

    // New day — clear in-memory list
    if (_currentDate != today) {
      _todaysPhotos = [];
      _currentDate = today;
      print('DailyPhotoTracker: New day detected, clearing photos list');
    }

    await _loadTodaysPhotos(uid, today);
  }

  static Future<void> _loadTodaysPhotos(String uid, String today) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      // UID-scoped path: daily_photos/{uid}/{date}/
      final todayDir = Directory('${directory.path}/daily_photos/$uid/$today');

      if (await todayDir.exists()) {
        final files = await todayDir.list().toList();
        final photos = files
            .whereType<File>()
            .where((f) => f.path.endsWith('.jpg'))
            .toList();
        photos.sort((a, b) => a.path.compareTo(b.path));
        _todaysPhotos = photos;
        print('DailyPhotoTracker: Loaded ${photos.length} photos for $uid/$today');
      } else {
        _todaysPhotos = [];
        print('DailyPhotoTracker: No folder exists for $uid/$today yet');
      }

      _notifyListeners();
    } catch (e) {
      print('DailyPhotoTracker: Load error: $e');
      _todaysPhotos = [];
    }
  }

  /// Add a new photo for today (saves to UID-scoped folder)
  static Future<void> addPhoto(File photo) async {
    final uid = _uid;
    if (uid == null) return;

    print('DailyPhotoTracker: Adding new photo...');
    final today = _today;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final todayDir = Directory('${directory.path}/daily_photos/$uid/$today');
      if (!await todayDir.exists()) {
        await todayDir.create(recursive: true);
      }

      final fileName = 'daily_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = File('${todayDir.path}/$fileName');
      await savedFile.writeAsBytes(await photo.readAsBytes());

      _todaysPhotos.add(savedFile);
      _currentDate = today;
      _loadedForUid = uid;

      print('DailyPhotoTracker: Photo saved: ${savedFile.path}');
      print('DailyPhotoTracker: Total photos today: ${_todaysPhotos.length}');

      // Clear image cache so new photo renders correctly
      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}

      _notifyListeners();
    } catch (e) {
      print('DailyPhotoTracker: addPhoto error: $e');
    }
  }

  /// Check if it's a new day and reset if so
  static Future<void> checkAndResetIfNewDay() async {
    final uid = _uid;
    if (uid == null) return;

    final today = _today;
    if (_currentDate != today || _loadedForUid != uid) {
      _todaysPhotos = [];
      _currentDate = today;
      _loadedForUid = uid;
      await _loadTodaysPhotos(uid, today);
    }
  }
}