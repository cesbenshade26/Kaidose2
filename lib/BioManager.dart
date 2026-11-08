import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:convert';

/// Plain-text bio. One fixed style everywhere, so the only setting is the text.
class BioManager {
  static const int maxLength = 150;

  static String? _globalBioText;
  static String? _loadedForUid;
  static final List<VoidCallback> _listeners = [];

  static String _localFileName(String uid) => 'user_bio_data_$uid.json';

  static String? get globalBioText => _globalBioText;

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static void _notifyListeners() {
    for (var listener in List.of(_listeners)) {
      try {
        listener();
      } catch (e) {
        print('BioManager: Error calling listener: $e');
      }
    }
  }

  /// Set the bio — saves locally and syncs to Firestore.
  static void setBio(String? text) {
    final trimmed = text?.trim();
    _globalBioText = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    _saveBioLocally();
    _saveBioToFirestore();
    _notifyListeners();
  }

  /// Call on logout to wipe state so next user starts clean
  static void clearForLogout() {
    _globalBioText = null;
    _loadedForUid = null;
    _notifyListeners();
  }

  /// Load bio for the current user. Priority: local cache -> Firestore
  static Future<void> loadBioFromStorage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      _globalBioText = null;
      _loadedForUid = null;
      return;
    }

    // Different user: clear immediately so a stale bio doesn't show
    if (_loadedForUid != uid) {
      _globalBioText = null;
      _loadedForUid = uid;
      _notifyListeners();
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/${_localFileName(uid)}');

      if (await file.exists()) {
        _applyFromJson(json.decode(await file.readAsString()));
        _notifyListeners();
      }

      _refreshFromFirestore(uid);
    } catch (e) {
      print('BioManager: Load error: $e');
    }
  }

  static Future<void> _refreshFromFirestore(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null || _loadedForUid != uid) return;

      // New plain bio field first, then the old bioData map (formatting is ignored)
      String? text = data['bio'] as String?;
      if (text == null || text.isEmpty) {
        final old = data['bioData'];
        if (old is Map) text = old['text'] as String?;
      }

      _globalBioText = (text == null || text.trim().isEmpty) ? null : text.trim();
      await _saveBioLocally();
      _notifyListeners();
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
      await file.writeAsString(json.encode({'text': _globalBioText}));
    } catch (e) {
      print('BioManager: Local save error: $e');
    }
  }

  static Future<void> _saveBioToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'bio': _globalBioText ?? '',
        'bioData': FieldValue.delete(), // retire the old formatted version
      }, SetOptions(merge: true));
    } catch (e) {
      print('BioManager: Firestore save error: $e');
    }
  }

  static void _applyFromJson(Map<String, dynamic> data) {
    final t = data['text'] as String?;
    _globalBioText = (t == null || t.trim().isEmpty) ? null : t.trim();
  }

  // Kept for compatibility
  static Future<void> refreshBioFromStorage() async => await loadBioFromStorage();
  static Future<void> forceRefresh() async => await loadBioFromStorage();
  static void clearBio() => setBio(null);
}