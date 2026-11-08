import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'SendDailyMessage.dart';

/// Firestore + Storage-backed message persistence for Dailies. Public API
/// (saveMessages/loadMessages/addListener/etc.) is unchanged from the old
/// SharedPreferences-only version, so nothing calling MessageStorage needs
/// to change — only what happens inside it.
///
/// Messages live at dailies/{dailyId}/daily_messages/{messageId}. Any
/// local image/video path gets uploaded to Firebase Storage before being
/// written, so every member of the Daily can see it — not just the device
/// that posted it. A path that's already a network URL (already uploaded,
/// or a clip's videoUrl sent in via Share) is never re-uploaded.
class MessageStorage {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static const String _subcollection = 'daily_messages';
  static final List<Function()> _listeners = [];

  static void addListener(Function() listener) => _listeners.add(listener);
  static void removeListener(Function() listener) => _listeners.remove(listener);
  static void _notifyListeners() {
    for (final l in _listeners) l();
  }

  static CollectionReference<Map<String, dynamic>> _messagesRef(String dailyId) =>
      _firestore.collection('dailies').doc(dailyId).collection(_subcollection);

  static bool _isNetworkPath(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  /// Uploads a local file to Storage and returns its download URL. Returns
  /// the path unchanged if it's already a URL, the file no longer exists
  /// locally, or the upload fails (so a message never silently loses its
  /// media reference).
  static Future<String> _ensureUploaded({
    required String dailyId,
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
          .child('daily_messages/$dailyId/$messageId/$storageFileName');
      final upload = await ref.putFile(
        file,
        SettableMetadata(contentType: contentType),
      );
      return await upload.ref.getDownloadURL();
    } catch (e) {
      print('MessageStorage: upload error for $localPath: $e');
      return localPath;
    }
  }

  /// Save messages for a specific daily. Uploads any not-yet-uploaded
  /// image/video first, then upserts every message's document.
  static Future<void> saveMessages(String dailyId, List<DailyMessage> messages) async {
    _prefetched.remove(dailyId);
    try {
      final batch = _firestore.batch();

      for (final msg in messages) {
        final uploadedMedia = <DailyMediaItem>[];

        for (int i = 0; i < msg.media.length; i++) {
          final item = msg.media[i];
          final uploadedPath = await _ensureUploaded(
            dailyId: dailyId,
            messageId: msg.messageId,
            localPath: item.path,
            storageFileName: item.isVideo ? 'media_$i.mp4' : 'media_$i.jpg',
            contentType: item.isVideo ? 'video/mp4' : 'image/jpeg',
          );
          uploadedMedia.add(DailyMediaItem(path: uploadedPath, isVideo: item.isVideo));
        }

        final data = msg.toJson();
        data['media'] = uploadedMedia.map((m) => m.toJson()).toList();
        // Keep the legacy single-path fields in sync with the (now
        // uploaded) first image/video, for any older code reading them
        // directly.
        data['image_path'] = _firstPath(uploadedMedia, false);
        data['video_path'] = _firstPath(uploadedMedia, true);

        batch.set(_messagesRef(dailyId).doc(msg.messageId), data);
      }

      await batch.commit();
      print('Saved ${messages.length} messages for daily: $dailyId');
      _notifyListeners();
    } catch (e) {
      print('Error saving messages: $e');
    }
  }

  static String? _firstPath(List<DailyMediaItem> items, bool isVideo) {
    for (final m in items) {
      if (m.isVideo == isVideo) return m.path;
    }
    return null;
  }

  // Messages fetched ahead of time (see [prefetch]), used once.
  static final Map<String, _Prefetched> _prefetched = {};
  static const Duration _prefetchTtl = Duration(seconds: 45);

  /// Starts loading a Daily's messages in the background, so opening that
  /// Daily moments later finds them already there. Used once, then thrown
  /// away, and discarded after 45 seconds so nothing stale lingers.
  static void prefetch(String dailyId) {
    final existing = _prefetched[dailyId];
    if (existing != null &&
        DateTime.now().difference(existing.at) < _prefetchTtl) {
      return;
    }
    _prefetched[dailyId] = _Prefetched(_loadFresh(dailyId), DateTime.now());
  }

  /// Load messages for a specific daily, oldest first.
  static Future<List<DailyMessage>> loadMessages(String dailyId) {
    final p = _prefetched.remove(dailyId);
    if (p != null && DateTime.now().difference(p.at) < _prefetchTtl) {
      return p.future;
    }
    return _loadFresh(dailyId);
  }

  static Future<List<DailyMessage>> _loadFresh(String dailyId) async {
    try {
      final snapshot = await _messagesRef(dailyId)
          .orderBy('timestamp', descending: false)
          .get();

      final messages =
      snapshot.docs.map((doc) => DailyMessage.fromJson(doc.data())).toList();

      print('Loaded ${messages.length} messages for daily: $dailyId');
      return messages;
    } catch (e) {
      print('Error loading messages: $e');
      return [];
    }
  }

  /// Deletes one message from a Daily, plus any files uploaded for it. It's
  /// gone for everyone in the Daily. Returns false if the delete failed.
  static Future<bool> deleteMessage(String dailyId, String messageId) async {
    _prefetched.remove(dailyId);
    try {
      await _messagesRef(dailyId).doc(messageId).delete();
    } catch (e) {
      print('MessageStorage: delete message error: $e');
      return false;
    }

    // The message is already gone; leftover files are only clutter, so a
    // failure here is ignored.
    try {
      final listing = await _storage
          .ref()
          .child('daily_messages/$dailyId/$messageId')
          .listAll();
      for (final file in listing.items) {
        try {
          await file.delete();
        } catch (_) {}
      }
    } catch (_) {}

    _notifyListeners();
    return true;
  }

  /// Delete all messages for a specific daily.
  static Future<void> deleteMessages(String dailyId) async {
    _prefetched.remove(dailyId);
    try {
      final snapshot = await _messagesRef(dailyId).get();
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('Deleted messages for daily: $dailyId');
    } catch (e) {
      print('Error deleting messages: $e');
    }
  }

  /// Every daily ID that currently has at least one saved message.
  /// Debugging/testing helper — uses a collection-group query, which may
  /// need "Collection group" query scope enabled for daily_messages in the
  /// Firebase console the first time it runs.
  static Future<List<String>> getAllDailyIds() async {
    try {
      final snapshot = await _firestore.collectionGroup(_subcollection).get();
      final Set<String> dailyIds = {};
      for (final doc in snapshot.docs) {
        final parentDaily = doc.reference.parent.parent; // dailies/{dailyId}
        if (parentDaily != null) dailyIds.add(parentDaily.id);
      }
      return dailyIds.toList();
    } catch (e) {
      print('Error getting daily IDs: $e');
      return [];
    }
  }

  /// Clear every message across every Daily (debugging/testing only).
  static Future<void> clearAllMessages() async {
    try {
      final snapshot = await _firestore.collectionGroup(_subcollection).get();
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('Cleared all messages');
    } catch (e) {
      print('Error clearing all messages: $e');
    }
  }
}

class _Prefetched {
  final Future<List<DailyMessage>> future;
  final DateTime at;
  const _Prefetched(this.future, this.at);
}