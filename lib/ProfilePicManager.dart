import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'ProfilePicService.dart';

class ProfilePicManager {
  static File? _globalProfilePic;
  static String? _loadedForUid; // track which user is currently loaded
  static final List<VoidCallback> _listeners = [];

  static String _localFileName(String uid) => 'profile_picture_$uid.jpg';

  static File? get globalProfilePic => _globalProfilePic;

  static set globalProfilePic(File? file) {
    print('ProfilePicManager: Setting globalProfilePic to: ${file?.path}');
    if (_globalProfilePic != null && _globalProfilePic != file) {
      _clearImageCache();
    }
    _globalProfilePic = file;
    _saveProfilePicLocally(file);
    for (var listener in _listeners) {
      listener();
    }
  }

  // Call this on logout to wipe state so next user starts clean
  static void clearForLogout() {
    _clearImageCache();
    _globalProfilePic = null;
    _loadedForUid = null;
    for (var listener in _listeners) {
      listener();
    }
    print('ProfilePicManager: Cleared for logout');
  }

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static void _clearImageCache() {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (e) {
      print('ProfilePicManager: Error clearing cache: $e');
    }
  }

  static Future<void> loadProfilePicFromStorage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // No user logged in — clear everything
    if (uid == null) {
      _globalProfilePic = null;
      _loadedForUid = null;
      return;
    }

    // Already loaded for this exact UID — just refresh from Firebase silently
    if (_loadedForUid == uid && _globalProfilePic != null) {
      _refreshFromFirebase(uid);
      return;
    }

    // Different user (or first load) — clear old pic immediately before loading new one
    if (_loadedForUid != uid) {
      _clearImageCache();
      _globalProfilePic = null;
      _loadedForUid = uid;
      // Notify so UI shows default pic while we load
      for (var listener in _listeners) listener();
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final localFile = File('${directory.path}/${_localFileName(uid)}');

      if (await localFile.exists()) {
        _clearImageCache();
        _globalProfilePic = localFile;
        _loadedForUid = uid;
        print('ProfilePicManager: Loaded local cache for $uid');
        for (var listener in _listeners) listener();
      } else {
        print('ProfilePicManager: No local cache for $uid, checking Firebase');
      }

      // Always refresh from Firebase to get latest
      _refreshFromFirebase(uid);
    } catch (e) {
      print('ProfilePicManager: Load error: $e');
      _globalProfilePic = null;
    }
  }

  static Future<void> _refreshFromFirebase(String uid) async {
    try {
      final downloaded = await ProfilePicService.downloadAndCacheProfilePic(uid: uid);
      // Only apply if the user hasn't changed while we were fetching
      if (downloaded != null && _loadedForUid == uid) {
        _clearImageCache();
        _globalProfilePic = downloaded;
        for (var listener in _listeners) listener();
        print('ProfilePicManager: Refreshed from Firebase for $uid');
      }
    } catch (e) {
      print('ProfilePicManager: Firebase refresh error: $e');
    }
  }

  static Future<void> _saveProfilePicLocally(File? file) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final savedFile = File('${directory.path}/${_localFileName(uid)}');

      if (file != null) {
        if (await savedFile.exists()) await savedFile.delete();
        _clearImageCache();
        final bytes = await file.readAsBytes();
        await savedFile.writeAsBytes(bytes);
        if (_globalProfilePic?.path != savedFile.path) {
          _globalProfilePic = savedFile;
          _loadedForUid = uid;
        }

        // Upload to Firebase in background
        ProfilePicService.uploadProfilePic(savedFile).then((url) {
          if (url != null) print('ProfilePicManager: Firebase upload done: $url');
        });

        print('ProfilePicManager: Saved locally for $uid');
      } else {
        if (await savedFile.exists()) await savedFile.delete();
        _globalProfilePic = null;
        _clearImageCache();
        await ProfilePicService.deleteProfilePic();
      }
    } catch (e) {
      print('ProfilePicManager: Save error: $e');
    }
  }

  static Future<void> forceRefresh() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _clearImageCache();
    await _refreshFromFirebase(uid);
  }
}

class DefaultProfilePic extends StatelessWidget {
  final double size;
  final double borderWidth;

  const DefaultProfilePic({
    Key? key,
    this.size = 160,
    this.borderWidth = 3,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
        border: Border.all(color: Colors.grey[400]!, width: borderWidth),
      ),
      child: ClipOval(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: size * 0.1875,
              child: Container(
                width: size * 0.3125,
                height: size * 0.3125,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[600]),
              ),
            ),
            Positioned(
              bottom: -size * 0.125,
              child: Container(
                width: size * 0.875,
                height: size * 0.5,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(size * 0.4375),
                    topRight: Radius.circular(size * 0.4375),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}