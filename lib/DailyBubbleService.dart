import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// A single Daily Bubble as stored in Firestore, with its cover already
/// cached locally as a File for display.
class DailyBubbleRecord {
  final String id;
  final String name;
  final File? cover;

  DailyBubbleRecord({required this.id, required this.name, this.cover});
}

/// Firestore-backed storage for Daily Bubbles (name, cover) and the Your
/// Daily photos posted to each one. Structure:
///   users/{uid}/dailyBubbles/{bubbleId}
///     name, coverBase64, createdAt
///   users/{uid}/dailyBubbles/{bubbleId}/photos/{photoId}
///     photoBase64, postedAt
class DailyBubbleService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

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
  /// new bubble's Firestore doc id, or null on failure.
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

  /// Adds a posted Your Daily photo to a bubble, timestamped so it can be
  /// replayed in posted order later.
  static Future<bool> addPhotoToBubble({
    required String bubbleId,
    required File photo,
  }) async {
    final uid = currentUid;
    if (uid == null) return false;

    try {
      final compressed = await _compress(photo);
      if (compressed == null) return false;

      await _bubblesRef(uid).doc(bubbleId).collection('photos').add({
        'photoBase64': base64Encode(compressed),
        'postedAt': FieldValue.serverTimestamp(),
      });

      print('DailyBubbleService: Added photo to bubble $bubbleId');
      return true;
    } catch (e) {
      print('DailyBubbleService: addPhotoToBubble error: $e');
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

  /// Loads every photo posted to a bubble, oldest first — same order a
  /// normal Your Daily story would play in — caching each to a local file.
  static Future<List<File>> loadBubblePhotos({
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

      final photos = <File>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final base64String = data['photoBase64'] as String?;
        if (base64String == null) continue;

        final file = await _cacheBase64ToFile(
          base64String,
          'bubble_photo_${targetUid}_${bubbleId}_${doc.id}.jpg',
        );
        if (file != null) photos.add(file);
      }

      return photos;
    } catch (e) {
      print('DailyBubbleService: loadBubblePhotos error: $e');
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
}