import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';

class ClipTracker {
  static List<File> _todaysClips = [];
  static final List<VoidCallback> _listeners = [];
  static String? _currentDate;

  static List<File> get todaysClips => _todaysClips;
  static bool get hasClipsToday => _todaysClips.isNotEmpty;
  static int get clipCount => _todaysClips.length;

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    print('ClipTracker: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      listener();
    }
  }

  static String _getCurrentDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Future<String> _getTodaysFolderPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final dateString = _getCurrentDateString();
    return '${directory.path}/daily_clips/$dateString';
  }

  static bool _isNewDay() {
    final currentDate = _getCurrentDateString();
    if (_currentDate != currentDate) {
      _currentDate = currentDate;
      return true;
    }
    return false;
  }

  static Future<void> initialize() async {
    print('ClipTracker: Initializing...');

    if (_isNewDay()) {
      print('New day detected, clearing clips list');
      _todaysClips.clear();
    }

    try {
      final folderPath = await _getTodaysFolderPath();
      final folder = Directory(folderPath);

      if (await folder.exists()) {
        final files = await folder.list().toList();
        _todaysClips.clear();

        files.sort((a, b) => a.path.compareTo(b.path));

        for (var file in files) {
          if (file is File && file.path.endsWith('.mp4')) {
            _todaysClips.add(file);
          }
        }

        print('Loaded ${_todaysClips.length} clips for today');
      } else {
        print('No folder exists for today yet');
        _todaysClips.clear();
      }

      _notifyListeners();
    } catch (e) {
      print('Error initializing ClipTracker: $e');
      _todaysClips.clear();
    }
  }

  static Future<File> addClip(File sourceVideo) async {
    print('ClipTracker: Adding new clip...');

    try {
      final folderPath = await _getTodaysFolderPath();
      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'clip_$timestamp.mp4';
      final filePath = '$folderPath/$fileName';

      final bytes = await sourceVideo.readAsBytes();
      final savedFile = File(filePath);
      await savedFile.writeAsBytes(bytes);

      _todaysClips.add(savedFile);

      print('Clip saved: $filePath');
      print('Total clips today: ${_todaysClips.length}');

      _notifyListeners();

      return savedFile;
    } catch (e) {
      print('Error adding clip: $e');
      rethrow;
    }
  }

  static File? getClipByIndex(int index) {
    if (index >= 0 && index < _todaysClips.length) {
      return _todaysClips[index];
    }
    return null;
  }

  static File? getLatestClip() {
    if (_todaysClips.isNotEmpty) {
      return _todaysClips.last;
    }
    return null;
  }

  static Future<void> deleteClip(int index) async {
    if (index >= 0 && index < _todaysClips.length) {
      try {
        final file = _todaysClips[index];
        if (await file.exists()) {
          await file.delete();
        }
        _todaysClips.removeAt(index);
        _notifyListeners();

        print('Clip deleted. Remaining clips: ${_todaysClips.length}');
      } catch (e) {
        print('Error deleting clip: $e');
      }
    }
  }

  static Future<void> clearTodaysClips() async {
    try {
      final folderPath = await _getTodaysFolderPath();
      final folder = Directory(folderPath);

      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }

      _todaysClips.clear();
      _notifyListeners();

      print('All clips for today cleared');
    } catch (e) {
      print('Error clearing today\'s clips: $e');
    }
  }

  static Future<void> checkAndResetIfNewDay() async {
    if (_isNewDay()) {
      print('New day detected! Resetting clips...');
      _todaysClips.clear();
      _notifyListeners();
    }
  }
}