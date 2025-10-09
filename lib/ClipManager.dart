import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';

class ClipManager {
  static File? _globalClip;
  static final List<VoidCallback> _listeners = [];
  static const String _clipFileName = 'current_clip.mp4';

  static File? get globalClip => _globalClip;

  static set globalClip(File? file) {
    print('ClipManager: Setting globalClip to: ${file?.path}');
    _globalClip = file;
    _saveClipLocally(file);

    print('ClipManager: Notifying ${_listeners.length} listeners');
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

  static Future<void> setClip(File videoFile) async {
    try {
      print('ClipManager: Starting to save clip...');
      final directory = await getApplicationDocumentsDirectory();
      final clipPath = '${directory.path}/$_clipFileName';

      final targetFile = File(clipPath);
      if (targetFile.existsSync()) {
        await targetFile.delete();
      }

      final bytes = await videoFile.readAsBytes();
      await targetFile.writeAsBytes(bytes);

      _globalClip = targetFile;

      print('Clip saved successfully!');
      for (var listener in _listeners) {
        listener();
      }
    } catch (e) {
      print('ERROR in ClipManager.setClip: $e');
      rethrow;
    }
  }

  static Future<File?> getClip() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final clipPath = '${directory.path}/$_clipFileName';
      final file = File(clipPath);

      if (file.existsSync()) {
        _globalClip = file;
        return file;
      } else {
        _globalClip = null;
        return null;
      }
    } catch (e) {
      print('ERROR in ClipManager.getClip: $e');
      return null;
    }
  }

  static Future<void> loadClipFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_clipFileName');

      if (await file.exists()) {
        _globalClip = file;
        for (var listener in _listeners) {
          listener();
        }
      } else {
        _globalClip = null;
      }
    } catch (e) {
      print('Error loading clip: $e');
      _globalClip = null;
    }
  }

  static Future<void> _saveClipLocally(File? file) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final savedFile = File('${directory.path}/$_clipFileName');

      if (file != null) {
        if (await savedFile.exists()) {
          await savedFile.delete();
        }

        final bytes = await file.readAsBytes();
        await savedFile.writeAsBytes(bytes);

        if (_globalClip?.path != savedFile.path) {
          _globalClip = savedFile;
        }
      } else {
        if (await savedFile.exists()) {
          await savedFile.delete();
        }
        _globalClip = null;
      }
    } catch (e) {
      print('Error saving clip: $e');
    }
  }

  static Future<void> deleteClip() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final clipPath = '${directory.path}/$_clipFileName';
      final file = File(clipPath);

      if (file.existsSync()) {
        await file.delete();
      }

      _globalClip = null;

      for (var listener in _listeners) {
        listener();
      }
    } catch (e) {
      print('ERROR in ClipManager.deleteClip: $e');
      rethrow;
    }
  }
}