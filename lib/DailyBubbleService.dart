import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'StoryMediaItem.dart';

/// A single Daily Bubble as stored in Firestore, with its cover already
/// cached locally as a File for display. Covers are always photos.
class DailyBubbleRecord {
  final String id;
  final String name;
  final File? cover;

  DailyBubbleRecord({required this.id, required this.name, this.cover});
}

/// Firestore-backed storage for Daily Bubbles (name, cover) and the Your
/// Daily media posted to each one — photos AND video clips, same split
/// used everywhere else in the app (Your Daily's own story via
/// FriendDailyService, Daily messages via MessageStorage): photos
/// compress to base64 straight into Firestore; videos upload to Storage
/// and only the download URL gets stored, since a video would blow past
/// Firestore's 1MB document limit if stored inline like a photo is.
/// Structure:
///   users/{uid}/dailyBubbles/{bubbleId}
///     name, coverBase64, createdAt
///   users/{uid}/dailyBubbles/{bubbleId}/photos/{itemId}
///     mediaType ('photo' | 'video'), photoBase64 OR videoUrl, postedAt
class DailyBubbleService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static String? get currentUid => _auth.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>> _bubblesRef(String uid) =>
      _firestore.collection('users').doc(uid).collection('dailyBubbles');

  static Future<Uint8List?> _compress(File file) async {
    return await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 400,
      minHeight: 400,
      quality: 70,
      format: CompressFormat.jpeg,
    );
  }

  /// Creates a new bubble under the current user's account. Returns the
  /// new bubble's Firestore doc id, or null on failure. Cover is always a
  /// photo.
  static Future<String?> createBubble({
    required String name,
    File? cover,
  }) async {
    final uid = currentUid;
    if (uid == null) return null;

    try {
      String? coverBase64;
      if (cover != null) {
        final compressed = await _compress(cover);
        if (compressed != null) coverBase64 = base64Encode(compressed);
      }

      final docRef = await _bubblesRef(uid).add({
        'name': name,
        'coverBase64': coverBase64,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('DailyBubbleService: Created bubble ${docRef.id} for $uid');
      return docRef.id;
    } catch (e) {
      print('DailyBubbleService: createBubble error: $e');
      return null;
    }
  }

  /// Updates an existing bubble's name and/or cover. Cover is only touched
  /// if a new File is passed.
  static Future<bool> updateBubble({
    required String bubbleId,
    required String name,
    File? cover,
  }) async {
    final uid = currentUid;
    if (uid == null) return false;

    try {
      final data = <String, dynamic>{'name': name};

      if (cover != null) {
        final compressed = await _compress(cover);
        if (compressed != null) data['coverBase64'] = base64Encode(compressed);
      }

      await _bubblesRef(uid).doc(bubbleId).set(data, SetOptions(merge: true));
      print('DailyBubbleService: Updated bubble $bubbleId for $uid');
      return true;
    } catch (e) {
      print('DailyBubbleService: updateBubble error: $e');
      return false;
    }
  }

  /// Adds a posted Your Daily photo or video clip to a bubble, timestamped
  /// so it can be replayed in posted order later.
  static Future<bool> addMediaToBubble({
    required String bubbleId,
    required File file,
    required bool isVideo,
  }) async {
    final uid = currentUid;
    if (uid == null) return false;

    try {
      if (isVideo) {
        final itemId = DateTime.now().millisecondsSinceEpoch.toString();
        final ref = _storage.ref().child('dailyBubbles/$uid/$bubbleId/$itemId.mp4');
        await ref.putFile(file, SettableMetadata(contentType: 'video/mp4'));
        final videoUrl = await ref.getDownloadURL();

        await _bubblesRef(uid).doc(bubbleId).collection('photos').doc(itemId).set({
          'mediaType': 'video',
          'videoUrl': videoUrl,
          'postedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final compressed = await _compress(file);
        if (compressed == null) return false;

        await _bubblesRef(uid).doc(bubbleId).collection('photos').add({
          'mediaType': 'photo',
          'photoBase64': base64Encode(compressed),
          'postedAt': FieldValue.serverTimestamp(),
        });
      }

      print('DailyBubbleService: Added ${isVideo ? 'video' : 'photo'} to bubble $bubbleId');
      return true;
    } catch (e) {
      print('DailyBubbleService: addMediaToBubble error: $e');
      return false;
    }
  }

  /// Loads every bubble for a user (default: current user), oldest first,
  /// caching each cover to a local file.
  static Future<List<DailyBubbleRecord>> loadBubbles({String? uid}) async {
    final targetUid = uid ?? currentUid;
    if (targetUid == null) return [];

    try {
      final snapshot = await _bubblesRef(targetUid)
          .orderBy('createdAt', descending: false)
          .get();

      final records = <DailyBubbleRecord>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String? ?? '';
        final coverBase64 = data['coverBase64'] as String?;

        File? coverFile;
        if (coverBase64 != null) {
          coverFile = await _cacheBase64ToFile(
            coverBase64,
            'bubble_cover_${targetUid}_${doc.id}.jpg',
          );
        }

        records.add(DailyBubbleRecord(id: doc.id, name: name, cover: coverFile));
      }

      return records;
    } catch (e) {
      print('DailyBubbleService: loadBubbles error: $e');
      return [];
    }
  }

  /// Loads every photo/video posted to a bubble, oldest first — same
  /// order a normal Your Daily story would play in. Photos decode
  /// straight from base64; videos download from their Storage URL —
  /// either way the caller gets a ready-to-play local file wrapped in a
  /// StoryMediaItem.
  static Future<List<StoryMediaItem>> loadBubbleMedia({
    required String bubbleId,
    String? uid,
  }) async {
    final targetUid = uid ?? currentUid;
    if (targetUid == null) return [];

    try {
      final snapshot = await _bubblesRef(targetUid)
          .doc(bubbleId)
          .collection('photos')
          .orderBy('postedAt', descending: false)
          .get();

      final items = <StoryMediaItem>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final mediaType = data['mediaType'] as String? ?? 'photo';

        if (mediaType == 'video') {
          final videoUrl = data['videoUrl'] as String?;
          if (videoUrl == null) continue;
          final file = await _downloadVideo(
            videoUrl,
            'bubble_video_${targetUid}_${bubbleId}_${doc.id}.mp4',
          );
          if (file != null) items.add(StoryMediaItem(file: file, isVideo: true));
        } else {
          final base64String = data['photoBase64'] as String?;
          if (base64String == null) continue;
          final file = await _cacheBase64ToFile(
            base64String,
            'bubble_photo_${targetUid}_${bubbleId}_${doc.id}.jpg',
          );
          if (file != null) items.add(StoryMediaItem(file: file, isVideo: false));
        }
      }

      return items;
    } catch (e) {
      print('DailyBubbleService: loadBubbleMedia error: $e');
      return [];
    }
  }

  static Future<File?> _cacheBase64ToFile(String base64String, String filename) async {
    try {
      final bytes = base64Decode(base64String);
      final directory = await getApplicationDocumentsDirectory();
      final localFile = File('${directory.path}/$filename');
      await localFile.writeAsBytes(bytes);
      return localFile;
    } catch (e) {
      print('DailyBubbleService: cache error: $e');
      return null;
    }
  }

  static Future<File?> _downloadVideo(String videoUrl, String filename) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final localFile = File('${directory.path}/$filename');
      await _storage.refFromURL(videoUrl).writeToFile(localFile);
      return localFile;
    } catch (e) {
      print('DailyBubbleService: video download error: $e');
      return null;
    }
  }
}