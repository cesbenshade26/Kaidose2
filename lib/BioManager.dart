import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:convert';

class BioManager {
  static String? _globalBioText;
  static bool _globalBold = false;
  static bool _globalItalic = false;
  static bool _globalUnderlined = false;
  static TextAlign _globalAlign = TextAlign.center;
  static Color _globalColor = Colors.black;
  static String? _loadedForUid;
  static final List<VoidCallback> _listeners = [];

  static String _localFileName(String uid) => 'user_bio_data_$uid.json';

  // Getters
  static String? get globalBioText => _globalBioText;
  static bool get globalBold => _globalBold;
  static bool get globalItalic => _globalItalic;
  static bool get globalUnderlined => _globalUnderlined;
  static TextAlign get globalAlign => _globalAlign;
  static Color get globalColor => _globalColor;

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static void _notifyListeners() {
    for (var listener in _listeners) {
      try {
        listener();
      } catch (e) {
        print('BioManager: Error calling listener: $e');
      }
    }
  }

  /// Set bio with formatting — saves locally and syncs to Firestore
  static void setBio(
      String? text,
      bool bold,
      bool italic,
      bool underlined,
      TextAlign align,
      Color color,
      ) {
    _globalBioText = text;
    _globalBold = bold;
    _globalItalic = italic;
    _globalUnderlined = underlined;
    _globalAlign = align;
    _globalColor = color;

    _saveBioLocally();
    _saveBioToFirestore();
    _notifyListeners();
  }

  /// Call on logout to wipe state so next user starts clean
  static void clearForLogout() {
    _globalBioText = null;
    _globalBold = false;
    _globalItalic = false;
    _globalUnderlined = false;
    _globalAlign = TextAlign.center;
    _globalColor = Colors.black;
    _loadedForUid = null;
    _notifyListeners();
    print('BioManager: Cleared for logout');
  }

  /// Load bio for the current user.
  /// Priority: local cache → Firestore
  static Future<void> loadBioFromStorage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      _resetToDefaults();
      _loadedForUid = null;
      return;
    }

    // Different user — clear immediately so stale bio doesn't show
    if (_loadedForUid != uid) {
      _resetToDefaults();
      _loadedForUid = uid;
      _notifyListeners();
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${_localFileName(uid)}');

      if (await file.exists()) {
        final bioString = await file.readAsString();
        _applyFromJson(json.decode(bioString));
        _loadedForUid = uid;
        print('BioManager: Loaded local cache for $uid');
        _notifyListeners();
      }

      // Always refresh from Firestore in the background
      _refreshFromFirestore(uid);
    } catch (e) {
      print('BioManager: Load error: $e');
      _resetToDefaults();
    }
  }

  static Future<void> _refreshFromFirestore(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final data = doc.data();
      if (data == null) return;

      // Only apply if still the same user
      if (_loadedForUid != uid) return;

      final bioData = data['bioData'];
      if (bioData == null) return;

      _applyFromJson(Map<String, dynamic>.from(bioData));
      _loadedForUid = uid;

      // Update local cache with Firestore data
      await _saveBioLocally();
      _notifyListeners();
      print('BioManager: Refreshed from Firestore for $uid');
    } catch (e) {
      print('BioManager: Firestore refresh error: $e');
    }
  }

  static Future<void> _saveBioLocally() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${_localFileName(uid)}');
      await file.writeAsString(json.encode(_toJson()));
      print('BioManager: Saved locally for $uid');
    } catch (e) {
      print('BioManager: Local save error: $e');
    }
  }

  static Future<void> _saveBioToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'bioData': _toJson()}, SetOptions(merge: true));
      print('BioManager: Saved to Firestore for $uid');
    } catch (e) {
      print('BioManager: Firestore save error: $e');
    }
  }

  static Map<String, dynamic> _toJson() {
    return {
      'text': _globalBioText,
      'bold': _globalBold,
      'italic': _globalItalic,
      'underlined': _globalUnderlined,
      'align': _globalAlign.toString().split('.').last,
      'color': _globalColor.value,
    };
  }

  static void _applyFromJson(Map<String, dynamic> data) {
    _globalBioText = data['text'];
    _globalBold = data['bold'] ?? false;
    _globalItalic = data['italic'] ?? false;
    _globalUnderlined = data['underlined'] ?? false;
    _globalAlign = _parseTextAlign(data['align'] ?? 'center');
    _globalColor = Color(data['color'] ?? Colors.black.value);
  }

  static void _resetToDefaults() {
    _globalBioText = null;
    _globalBold = false;
    _globalItalic = false;
    _globalUnderlined = false;
    _globalAlign = TextAlign.center;
    _globalColor = Colors.black;
  }

  static TextAlign _parseTextAlign(String alignString) {
    switch (alignString) {
      case 'left': return TextAlign.left;
      case 'right': return TextAlign.right;
      case 'center':
      default: return TextAlign.center;
    }
  }

  // Kept for compatibility
  static Future<void> refreshBioFromStorage() async => await loadBioFromStorage();
  static Future<void> forceRefresh() async => await loadBioFromStorage();
  static void clearBio() => setBio(null, false, false, false, TextAlign.center, Colors.black);
  static Map<String, dynamic> getBioData() => _toJson();
}