import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'SendDailyMessage.dart';

/// Firestore-backed saved items, one subcollection per archive, at
/// users/{uid}/archives/{archiveId}/savedItems/{messageId}. Public API
/// (getSavedItems, saveItem, loadItemsForArchive, etc.) is unchanged from
/// the old SharedPreferences version — getSavedItems stays a synchronous
/// cache read, same as before, so SelectArchiveFolderScreen/
/// InsideArchiveScreen don't need any changes.
class SavedItemStorage {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static final Map<String, List<DailyMessage>> _savedItems = {};
  static final List<VoidCallback> _listeners = [];

  static String? get _uid => _auth.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>> _itemsRef(String archiveId) {
    final uid = _uid;
    if (uid == null) throw Exception('No signed-in user');
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('archives')
        .doc(archiveId)
        .collection('savedItems');
  }

  static List<DailyMessage> getSavedItems(String archiveId) {
    return List.unmodifiable(_savedItems[archiveId] ?? []);
  }

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  static bool _isNetworkPath(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  /// Uploads a local file to Storage and returns its download URL. Covers
  /// the rare case of saving a message before its own MessageStorage
  /// upload has finished — a path that's already a URL is left untouched.
  static Future<String> _ensureUploaded({
    required String archiveId,
    required String messageId,
    required String localPath,
    required String storageFileName,
    required String contentType,
  }) async {
    if (_isNetworkPath(localPath)) return localPath;

    try {
      final file = File(localPath);
      if (!await file.exists()) return localPath;

      final ref = _storage
          .ref()
          .child('saved_items/$archiveId/$messageId/$storageFileName');
      final upload = await ref.putFile(
        file,
        SettableMetadata(contentType: contentType),
      );
      return await upload.ref.getDownloadURL();
    } catch (e) {
      print('SavedItemStorage: upload error for $localPath: $e');
      return localPath;
    }
  }

  /// Save an item to a specific archive
  static Future<void> saveItem(String archiveId, DailyMessage message) async {
    if (_uid == null) return;

    // Check if already saved (avoid duplicates)
    final alreadySaved = (_savedItems[archiveId] ?? [])
        .any((item) => item.messageId == message.messageId);
    if (alreadySaved) {
      print('Item already saved to this archive');
      return;
    }

    try {
      String? imagePath = message.imagePath;
      String? videoPath = message.videoPath;

      if (imagePath != null) {
        imagePath = await _ensureUploaded(
          archiveId: archiveId,
          messageId: message.messageId,
          localPath: imagePath,
          storageFileName: 'image.jpg',
          contentType: 'image/jpeg',
        );
      }

      if (videoPath != null) {
        videoPath = await _ensureUploaded(
          archiveId: archiveId,
          messageId: message.messageId,
          localPath: videoPath,
          storageFileName: 'video.mp4',
          contentType: 'video/mp4',
        );
      }

      final data = message.toJson();
      data['image_path'] = imagePath;
      data['video_path'] = videoPath;

      await _itemsRef(archiveId).doc(message.messageId).set(data);

      _savedItems.putIfAbsent(archiveId, () => []);
      _savedItems[archiveId]!.add(message);
      _notifyListeners();
      print('Saved item to archive: $archiveId');
    } catch (e) {
      print('SavedItemStorage: saveItem error: $e');
    }
  }

  /// Remove an item from an archive
  static Future<void> removeItem(String archiveId, String messageId) async {
    if (_uid == null) return;
    try {
      await _itemsRef(archiveId).doc(messageId).delete();
      _savedItems[archiveId]?.removeWhere((item) => item.messageId == messageId);
      _notifyListeners();
      print('Removed item from archive: $archiveId');
    } catch (e) {
      print('SavedItemStorage: removeItem error: $e');
    }
  }

  /// Load saved items for a specific archive
  static Future<void> loadItemsForArchive(String archiveId) async {
    final uid = _uid;
    if (uid == null) {
      _savedItems[archiveId] = [];
      _notifyListeners();
      return;
    }

    try {
      final snapshot = await _itemsRef(archiveId)
          .orderBy('timestamp', descending: false)
          .get();

      _savedItems[archiveId] =
          snapshot.docs.map((doc) => DailyMessage.fromJson(doc.data())).toList();
      print('Loaded ${_savedItems[archiveId]!.length} items for archive: $archiveId');

      _notifyListeners();
    } catch (e) {
      print('Error loading items for archive $archiveId: $e');
      _savedItems[archiveId] = [];
    }
  }

  /// Load all saved items for all archives
  static Future<void> loadAllItems(List<String> archiveIds) async {
    for (var archiveId in archiveIds) {
      await loadItemsForArchive(archiveId);
    }
  }

  /// Clear all items from an archive
  static Future<void> clearArchive(String archiveId) async {
    if (_uid == null) return;
    try {
      final snapshot = await _itemsRef(archiveId).get();
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      _savedItems[archiveId] = [];
      _notifyListeners();
      print('Cleared archive: $archiveId');
    } catch (e) {
      print('Error clearing archive: $e');
    }
  }
}