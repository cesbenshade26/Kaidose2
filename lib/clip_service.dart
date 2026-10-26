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

  /// 'video' (default, and what every existing clip is) or 'photo'.
  /// Photo clips have an empty [videoUrl]; their image is [photoUrl], which
  /// is also used as [thumbnailUrl] so grids keep working unchanged.
  final String mediaType;
  final String? photoUrl;

  /// Topic keywords generated from the caption by a Cloud Function (may be
  /// empty for a brand-new clip). Used by the feed, not shown to users.
  final List<String> terms;

  bool get isPhoto => mediaType == 'photo';

  ClipData({
    required this.id,
    required this.creatorUid,
    required this.creatorUsername,
    required this.caption,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.createdAt,
    this.mediaType = 'video',
    this.photoUrl,
    this.terms = const [],
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
      mediaType: data['mediaType'] ?? 'video',
      photoUrl: data['photoUrl'],
      terms: data['terms'] is List
          ? List<String>.from((data['terms'] as List).whereType<String>())
          : const [],
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
      'mediaType': mediaType,
      'photoUrl': photoUrl,
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

  /// Upload a photo clip. Same collection and shape as a video clip, with
  /// mediaType 'photo'; the image doubles as the thumbnail.
  static Future<bool> uploadPhotoClip({
    required File photoFile,
    required String caption,
  }) async {
    final uid = currentUid;
    if (uid == null) return false;

    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final username = userDoc.data()?['username'] ?? 'Unknown';

      final clipId = DateTime.now().millisecondsSinceEpoch.toString();

      final path = photoFile.path.toLowerCase();
      final String ext;
      final String contentType;
      if (path.endsWith('.png')) {
        ext = 'png';
        contentType = 'image/png';
      } else if (path.endsWith('.heic') || path.endsWith('.heif')) {
        ext = 'heic';
        contentType = 'image/heic';
      } else {
        ext = 'jpg';
        contentType = 'image/jpeg';
      }

      print('ClipService: uploading photo...');
      final photoRef = _storage.ref().child('clips/$uid/$clipId/photo.$ext');
      final upload = await photoRef.putFile(
        photoFile,
        SettableMetadata(contentType: contentType),
      );
      final photoUrl = await upload.ref.getDownloadURL();

      final clip = ClipData(
        id: clipId,
        creatorUid: uid,
        creatorUsername: username,
        caption: caption,
        videoUrl: '',
        thumbnailUrl: photoUrl,
        createdAt: DateTime.now(),
        mediaType: 'photo',
        photoUrl: photoUrl,
      );

      await _firestore
          .collection('clips')
          .doc(clipId)
          .set(clip.toFirestoreJson());

      print('ClipService: photo clip $clipId saved to Firestore');
      return true;
    } catch (e) {
      print('ClipService: photo upload error: $e');
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
      if (clip.isPhoto) {
        if (clip.photoUrl != null) {
          await _storage.refFromURL(clip.photoUrl!).delete();
        }
        await _firestore.collection('clips').doc(clip.id).delete();
        print('ClipService: deleted photo clip ${clip.id}');
        return;
      }

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