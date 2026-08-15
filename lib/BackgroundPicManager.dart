import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:io';
import 'dart:convert';

class BackgroundPicManager {
  static File? _globalBackgroundPic;
  static bool _showSeparator = false;
  static Color _separatorColor = Colors.black;
  static String? _loadedForUid;
  static final List<VoidCallback> _listeners = [];

  static String _bgFileName(String uid) => 'background_picture_$uid.jpg';
  static String _settingsFileName(String uid) => 'background_settings_$uid.json';

  static File? get globalBackgroundPic => _globalBackgroundPic;
  static bool get showSeparator => _showSeparator;
  static Color get separatorColor => _separatorColor;

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static void _notifyListeners() {
    for (var listener in _listeners) {
      try { listener(); } catch (e) { print('BackgroundPicManager: listener error: $e'); }
    }
  }

  static void _clearImageCache() {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (e) {
      print('BackgroundPicManager: cache clear error: $e');
    }
  }

  static set globalBackgroundPic(File? file) {
    if (_globalBackgroundPic != null && _globalBackgroundPic != file) {
      _clearImageCache();
    }
    _globalBackgroundPic = file;
    _saveBackgroundPicLocally(file);
    _notifyListeners();
  }

  static void setSeparatorSettings(bool show, Color color) {
    _showSeparator = show;
    _separatorColor = color;
    _saveSettingsLocally();
    _saveSettingsToFirestore();
    _notifyListeners();
  }

  /// Call on logout to wipe state so next user starts clean
  static void clearForLogout() {
    _clearImageCache();
    _globalBackgroundPic = null;
    _showSeparator = false;
    _separatorColor = Colors.black;
    _loadedForUid = null;
    _notifyListeners();
    print('BackgroundPicManager: Cleared for logout');
  }

  /// Load background pic + settings for the current user.
  /// Priority: local cache → Firestore
  static Future<void> loadBackgroundPicFromStorage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      _globalBackgroundPic = null;
      _loadedForUid = null;
      return;
    }

    // Different user — clear immediately
    if (_loadedForUid != uid) {
      _clearImageCache();
      _globalBackgroundPic = null;
      _showSeparator = false;
      _separatorColor = Colors.black;
      _loadedForUid = uid;
      _notifyListeners();
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final localFile = File('${directory.path}/${_bgFileName(uid)}');

      if (await localFile.exists()) {
        _clearImageCache();
        _globalBackgroundPic = localFile;
        print('BackgroundPicManager: Loaded local cache for $uid');
      }

      await _loadSettingsFromStorage(uid);
      _notifyListeners();

      // Refresh from Firestore in background
      _refreshFromFirestore(uid);
    } catch (e) {
      print('BackgroundPicManager: Load error: $e');
      _globalBackgroundPic = null;
    }
  }

  static Future<void> _refreshFromFirestore(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (_loadedForUid != uid) return;

      final data = doc.data();
      if (data == null) return;

      // Restore separator settings
      final settingsData = data['backgroundSettings'];
      if (settingsData != null) {
        _showSeparator = settingsData['showSeparator'] ?? false;
        _separatorColor = Color(settingsData['separatorColor'] ?? Colors.black.value);
        await _saveSettingsLocally();
      }

      // Restore background image
      final base64String = data['backgroundPicBase64'] as String?;
      if (base64String != null) {
        final bytes = base64Decode(base64String);
        final directory = await getApplicationDocumentsDirectory();
        final localFile = File('${directory.path}/${_bgFileName(uid)}');
        await localFile.writeAsBytes(bytes);

        if (_loadedForUid == uid) {
          _clearImageCache();
          _globalBackgroundPic = localFile;
        }
      }

      _notifyListeners();
      print('BackgroundPicManager: Refreshed from Firestore for $uid');
    } catch (e) {
      print('BackgroundPicManager: Firestore refresh error: $e');
    }
  }

  static Future<void> _saveBackgroundPicLocally(File? file) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final savedFile = File('${directory.path}/${_bgFileName(uid)}');

      if (file != null) {
        if (await savedFile.exists()) await savedFile.delete();
        _clearImageCache();

        // Compress before saving — backgrounds can be large
        final compressed = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 800,
          minHeight: 200,
          quality: 75,
          format: CompressFormat.jpeg,
        );

        if (compressed != null) {
          await savedFile.writeAsBytes(compressed);
        } else {
          final bytes = await file.readAsBytes();
          await savedFile.writeAsBytes(bytes);
        }

        if (_globalBackgroundPic?.path != savedFile.path) {
          _globalBackgroundPic = savedFile;
          _loadedForUid = uid;
        }

        // Upload to Firestore in background
        _uploadToFirestore(savedFile, uid);

        print('BackgroundPicManager: Saved locally for $uid');
      } else {
        if (await savedFile.exists()) await savedFile.delete();
        _globalBackgroundPic = null;
        _clearImageCache();
        _deleteFromFirestore(uid);
      }
    } catch (e) {
      print('BackgroundPicManager: Save error: $e');
    }
  }

  static Future<void> _uploadToFirestore(File file, String uid) async {
    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      print('BackgroundPicManager: Compressed size = ${bytes.length} bytes');

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'backgroundPicBase64': base64String}, SetOptions(merge: true));

      print('BackgroundPicManager: Uploaded to Firestore for $uid');
    } catch (e) {
      print('BackgroundPicManager: Firestore upload error: $e');
    }
  }

  static Future<void> _deleteFromFirestore(String uid) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'backgroundPicBase64': FieldValue.delete()});
    } catch (e) {
      print('BackgroundPicManager: Firestore delete error: $e');
    }
  }

  static Future<void> _saveSettingsLocally() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final settingsFile = File('${directory.path}/${_settingsFileName(uid)}');
      final settings = {
        'showSeparator': _showSeparator,
        'separatorColor': _separatorColor.value,
      };
      await settingsFile.writeAsString(json.encode(settings));
    } catch (e) {
      print('BackgroundPicManager: Settings save error: $e');
    }
  }

  static Future<void> _loadSettingsFromStorage(String uid) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final settingsFile = File('${directory.path}/${_settingsFileName(uid)}');

      if (await settingsFile.exists()) {
        final settings = json.decode(await settingsFile.readAsString());
        _showSeparator = settings['showSeparator'] ?? false;
        _separatorColor = Color(settings['separatorColor'] ?? Colors.black.value);
      } else {
        _showSeparator = false;
        _separatorColor = Colors.black;
      }
    } catch (e) {
      print('BackgroundPicManager: Settings load error: $e');
      _showSeparator = false;
      _separatorColor = Colors.black;
    }
  }

  static Future<void> _saveSettingsToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
        'backgroundSettings': {
          'showSeparator': _showSeparator,
          'separatorColor': _separatorColor.value,
        }
      }, SetOptions(merge: true));
    } catch (e) {
      print('BackgroundPicManager: Settings Firestore save error: $e');
    }
  }

  static Future<void> forceRefresh() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _clearImageCache();
    await _refreshFromFirestore(uid);
  }
}