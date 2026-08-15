import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

class ClipData {
  final String id;
  final String creatorUid;
  final String creatorUsername;
  final String caption;
  final String videoUrl;
  final String? thumbnailUrl;
  final DateTime createdAt;

  ClipData({
    required this.id,
    required this.creatorUid,
    required this.creatorUsername,
    required this.caption,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.createdAt,
  });

  factory ClipData.fromFirestore(Map<String, dynamic> data, String id) {
    return ClipData(
      id: id,
      creatorUid: data['creatorUid'] ?? '',
      creatorUsername: data['creatorUsername'] ?? '',
      caption: data['caption'] ?? '',
      videoUrl: data['videoUrl'] ?? '',
      thumbnailUrl: data['thumbnailUrl'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestoreJson() {
    return {
      'creatorUid': creatorUid,
      'creatorUsername': creatorUsername,
      'caption': caption,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

class ClipService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? get currentUid => _auth.currentUser?.uid;

  /// Upload a clip to Firebase Storage and save the URL to Firestore.
  static Future<bool> uploadClip({
    required File videoFile,
    required String caption,
    File? thumbnailFile,
  }) async {
    final uid = currentUid;
    if (uid == null) return false;

    try {
      // Get username
      final userDoc =
      await _firestore.collection('users').doc(uid).get();
      final username = userDoc.data()?['username'] ?? 'Unknown';

      final clipId = DateTime.now().millisecondsSinceEpoch.toString();

      // Upload video to Firebase Storage
      print('ClipService: uploading video...');
      final videoRef = _storage.ref().child('clips/$uid/$clipId/video.mp4');
      final videoUpload = await videoRef.putFile(
        videoFile,
        SettableMetadata(contentType: 'video/mp4'),
      );
      final videoUrl = await videoUpload.ref.getDownloadURL();
      print('ClipService: video uploaded → $videoUrl');

      // Upload thumbnail if provided
      String? thumbnailUrl;
      if (thumbnailFile != null && await thumbnailFile.exists()) {
        final thumbRef =
        _storage.ref().child('clips/$uid/$clipId/thumbnail.jpg');
        final thumbUpload = await thumbRef.putFile(
          thumbnailFile,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        thumbnailUrl = await thumbUpload.ref.getDownloadURL();
      }

      // Save metadata to Firestore (just URLs — no video bytes)
      final clip = ClipData(
        id: clipId,
        creatorUid: uid,
        creatorUsername: username,
        caption: caption,
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection('clips')
          .doc(clipId)
          .set(clip.toFirestoreJson());

      print('ClipService: clip $clipId saved to Firestore');
      return true;
    } catch (e) {
      print('ClipService: upload error: $e');
      return false;
    }
  }

  /// Stream of all clips NOT posted by the current user, newest first.
  static Stream<List<ClipData>> getOtherUsersClips() {
    final uid = currentUid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('clips')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
        .where((doc) => doc.data()['creatorUid'] != uid)
        .map((doc) => ClipData.fromFirestore(doc.data(), doc.id))
        .toList());
  }

  /// Stream of clips posted BY the current user (for profile/ClipActivity).
  static Stream<List<ClipData>> getMyClips() {
    final uid = currentUid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('clips')
        .where('creatorUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .handleError((e) {
      print('getMyClips ERROR: $e');
    })
        .map((snap) => snap.docs
        .map((doc) => ClipData.fromFirestore(doc.data(), doc.id))
        .toList());
  }

  /// Delete a clip from Storage and Firestore.
  static Future<void> deleteClip(ClipData clip) async {
    final uid = currentUid;
    if (uid == null || clip.creatorUid != uid) return;

    try {
      // Delete from Storage
      final videoRef =
      _storage.ref().child('clips/$uid/${clip.id}/video.mp4');
      await videoRef.delete();

      if (clip.thumbnailUrl != null) {
        final thumbRef =
        _storage.ref().child('clips/$uid/${clip.id}/thumbnail.jpg');
        await thumbRef.delete();
      }

      // Delete from Firestore
      await _firestore.collection('clips').doc(clip.id).delete();
      print('ClipService: deleted clip ${clip.id}');
    } catch (e) {
      print('ClipService: delete error: $e');
    }
  }
}