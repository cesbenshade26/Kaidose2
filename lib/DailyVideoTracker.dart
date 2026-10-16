import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

/// Tracks today's YourDaily videos for the CURRENT user only. Same
/// UID/date-scoped local-file pattern as DailyPhotoTracker — storage under
/// daily_videos/{uid}/{date}/ — just for video instead of photo.
class DailyVideoTracker {
  static List<File> _todaysVideos = [];
  static String? _currentDate;
  static String? _loadedForUid;
  static final List<VoidCallback> _listeners = [];

  static List<File> get todaysVideos => List.unmodifiable(_todaysVideos);
  static bool get hasVideosToday => _todaysVideos.isNotEmpty;

  static String get _today => DateTime.now().toIso8601String().split('T')[0];
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static void _notifyListeners() {
    for (var listener in _listeners) {
      try { listener(); } catch (e) { print('DailyVideoTracker: listener error: $e'); }
    }
  }

  /// Call on logout so next user starts with a clean state
  static void clearForLogout() {
    _todaysVideos = [];
    _currentDate = null;
    _loadedForUid = null;
    _notifyListeners();
    print('DailyVideoTracker: Cleared for logout');
  }

  /// Initialize / reload for the current user and today's date
  static Future<void> initialize() async {
    print('DailyVideoTracker: Initializing...');
    final uid = _uid;

    if (_loadedForUid != uid) {
      _todaysVideos = [];
      _loadedForUid = uid;
      _currentDate = null;
    }

    if (uid == null) {
      print('DailyVideoTracker: No user logged in');
      return;
    }

    final today = _today;

    if (_currentDate != today) {
      _todaysVideos = [];
      _currentDate = today;
      print('DailyVideoTracker: New day detected, clearing videos list');
    }

    await _loadTodaysVideos(uid, today);
  }

  static Future<void> _loadTodaysVideos(String uid, String today) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final todayDir = Directory('${directory.path}/daily_videos/$uid/$today');

      if (await todayDir.exists()) {
        final files = await todayDir.list().toList();
        final videos = files
            .whereType<File>()
            .where((f) => f.path.endsWith('.mp4'))
            .toList();
        videos.sort((a, b) => a.path.compareTo(b.path));
        _todaysVideos = videos;
        print('DailyVideoTracker: Loaded ${videos.length} videos for $uid/$today');
      } else {
        _todaysVideos = [];
        print('DailyVideoTracker: No folder exists for $uid/$today yet');
      }

      _notifyListeners();
    } catch (e) {
      print('DailyVideoTracker: Load error: $e');
      _todaysVideos = [];
    }
  }

  /// Add a new video for today (saves to UID-scoped folder)
  static Future<void> addVideo(File video) async {
    final uid = _uid;
    if (uid == null) return;

    print('DailyVideoTracker: Adding new video...');
    final today = _today;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final todayDir = Directory('${directory.path}/daily_videos/$uid/$today');
      if (!await todayDir.exists()) {
        await todayDir.create(recursive: true);
      }

      final fileName = 'daily_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final savedFile = File('${todayDir.path}/$fileName');
      await savedFile.writeAsBytes(await video.readAsBytes());

      _todaysVideos.add(savedFile);
      _currentDate = today;
      _loadedForUid = uid;

      print('DailyVideoTracker: Video saved: ${savedFile.path}');
      print('DailyVideoTracker: Total videos today: ${_todaysVideos.length}');

      _notifyListeners();
    } catch (e) {
      print('DailyVideoTracker: addVideo error: $e');
    }
  }

  /// Check if it's a new day and reset if so
  static Future<void> checkAndResetIfNewDay() async {
    final uid = _uid;
    if (uid == null) return;

    final today = _today;
    if (_currentDate != today || _loadedForUid != uid) {
      _todaysVideos = [];
      _currentDate = today;
      _loadedForUid = uid;
      await _loadTodaysVideos(uid, today);
    }
  }
}