import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'MusicSearch.dart';

class ClipData {
  final String id;
  final String creatorUid;
  final String creatorUsername;
  final String caption;
  final String videoUrl;
  final String? thumbnailUrl;
  final DateTime createdAt;

  /// When the creator pinned this clip to the top of their profile (null if
  /// it isn't pinned). Pinned clips show in the order they were pinned.
  final DateTime? pinnedAt;
  bool get isPinned => pinnedAt != null;

  /// 'video' (default, and what every existing clip is) or 'photo'.
  /// Photo clips have an empty [videoUrl]; their image is [photoUrl], which
  /// is also used as [thumbnailUrl] so grids keep working unchanged.
  final String mediaType;
  final String? photoUrl;

  /// Every photo of a photo clip, in order ([photoUrl] is always the first).
  /// Older single-photo clips have only [photoUrl]; use [allPhotos].
  final List<String> photoUrls;

  /// A song attached to this clip. When set, its preview plays instead of the
  /// clip's own audio.
  final MusicTrack? music;

  /// Topic keywords generated from the caption by a Cloud Function (may be
  /// empty for a brand-new clip). Used by the feed, not shown to users.
  final List<String> terms;

  bool get isPhoto => mediaType == 'photo';

  /// The photos to show, whichever way this clip was saved.
  List<String> get allPhotos {
    if (photoUrls.isNotEmpty) return photoUrls;
    final u = photoUrl;
    return (u == null || u.isEmpty) ? const [] : [u];
  }

  bool get isMultiPhoto => isPhoto && allPhotos.length > 1;

  ClipData({
    required this.id,
    required this.creatorUid,
    required this.creatorUsername,
    required this.caption,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.createdAt,
    this.pinnedAt,
    this.mediaType = 'video',
    this.photoUrl,
    this.photoUrls = const [],
    this.music,
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
      pinnedAt: (data['pinnedAt'] as Timestamp?)?.toDate(),
      mediaType: data['mediaType'] ?? 'video',
      photoUrl: data['photoUrl'],
      photoUrls: data['photoUrls'] is List
          ? List<String>.from((data['photoUrls'] as List).whereType<String>())
          : const [],
      music: MusicTrack.fromMap(data['music']),
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
      if (photoUrls.isNotEmpty) 'photoUrls': photoUrls,
      if (music != null) 'music': music!.toMap(),
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
    MusicTrack? music,
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

      // Upload a thumbnail so grids can show a small image instead of
      // loading the video: the one passed in, or one made from the video.
      String? thumbnailUrl;
      try {
        final thumbRef =
        _storage.ref().child('clips/$uid/$clipId/thumbnail.jpg');
        if (thumbnailFile != null && await thumbnailFile.exists()) {
          final thumbUpload = await thumbRef.putFile(
            thumbnailFile,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          thumbnailUrl = await thumbUpload.ref.getDownloadURL();
        } else {
          final bytes = await _makeThumbnailBytes(videoFile.path);
          if (bytes != null) {
            final thumbUpload = await thumbRef.putData(
              bytes,
              SettableMetadata(contentType: 'image/jpeg'),
            );
            thumbnailUrl = await thumbUpload.ref.getDownloadURL();
          }
        }
      } catch (e) {
        // A missing thumbnail shouldn't stop the clip from posting.
        print('ClipService: thumbnail error: $e');
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
        music: music,
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

  /// Most photos one photo clip can hold.
  static const int maxPhotosPerClip = 10;

  /// Upload a photo clip made of one or more photos (in order). Same
  /// collection and shape as a video clip, with mediaType 'photo'; the first
  /// photo doubles as the thumbnail and as [ClipData.photoUrl], and all of
  /// them are saved in [ClipData.photoUrls].
  static Future<bool> uploadPhotoClip({
    required List<File> photoFiles,
    required String caption,
    MusicTrack? music,
  }) async {
    final uid = currentUid;
    if (uid == null || photoFiles.isEmpty) return false;
    final files = photoFiles.take(maxPhotosPerClip).toList();

    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final username = userDoc.data()?['username'] ?? 'Unknown';

      final clipId = DateTime.now().millisecondsSinceEpoch.toString();

      Future<String> uploadOne(int i) async {
        final file = files[i];
        final path = file.path.toLowerCase();
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
        final ref =
        _storage.ref().child('clips/$uid/$clipId/photo_$i.$ext');
        final upload =
        await ref.putFile(file, SettableMetadata(contentType: contentType));
        return upload.ref.getDownloadURL();
      }

      print('ClipService: uploading ${files.length} photo(s)...');
      // All at once; Future.wait keeps them in order.
      final urls = await Future.wait([
        for (var i = 0; i < files.length; i++) uploadOne(i),
      ]);

      final clip = ClipData(
        id: clipId,
        creatorUid: uid,
        creatorUsername: username,
        caption: caption,
        videoUrl: '',
        thumbnailUrl: urls.first,
        createdAt: DateTime.now(),
        mediaType: 'photo',
        photoUrl: urls.first,
        photoUrls: urls,
        music: music,
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

  /// A small JPEG of the video's first frame (480 px wide keeps it tiny).
  /// [video] is a local path or a URL.
  static Future<Uint8List?> _makeThumbnailBytes(String video) async {
    final bytes = await VideoThumbnail.thumbnailData(
      video: video,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 480,
      quality: 75,
    );
    return (bytes == null || bytes.isEmpty) ? null : bytes;
  }

  /// For clips posted before thumbnails were saved: makes one from the
  /// video, uploads it and saves its URL on the clip. Returns the URL, or
  /// null if it couldn't. Only works on your own clips.
  static Future<String?> backfillThumbnail(ClipData clip) async {
    final uid = currentUid;
    if (uid == null || clip.creatorUid != uid || clip.videoUrl.isEmpty) {
      return null;
    }
    final bytes = await _makeThumbnailBytes(clip.videoUrl);
    if (bytes == null) return null;
    final ref = _storage.ref().child('clips/$uid/${clip.id}/thumbnail.jpg');
    final up = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await up.ref.getDownloadURL();
    await _firestore
        .collection('clips')
        .doc(clip.id)
        .update({'thumbnailUrl': url});
    return url;
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

    // A file that's already gone from Storage must not stop the clip from
    // being removed, so each file is deleted on its own.
    Future<void> tryDelete(Reference ref) async {
      try {
        await ref.delete();
      } catch (e) {
        print('ClipService: storage delete skipped: $e');
      }
    }

    try {
      if (clip.isPhoto) {
        for (final url in clip.allPhotos) {
          try {
            await tryDelete(_storage.refFromURL(url));
          } catch (e) {
            print('ClipService: bad photo url skipped: $e');
          }
        }
      } else {
        await tryDelete(_storage.ref().child('clips/$uid/${clip.id}/video.mp4'));
        await tryDelete(
            _storage.ref().child('clips/$uid/${clip.id}/thumbnail.jpg'));
      }

      await _firestore.collection('clips').doc(clip.id).delete();
      print('ClipService: deleted clip ${clip.id}');
    } catch (e) {
      print('ClipService: delete error: $e');
    }
  }

  /// Most clips you can have pinned at once.
  static const int maxPins = 3;

  /// Pins a clip to the top of your profile (or unpins it). Pinned clips
  /// keep the order they were pinned in. Returns false if it failed.
  static Future<bool> setPinned(String clipId, bool pinned) async {
    if (currentUid == null) return false;
    try {
      await _firestore.collection('clips').doc(clipId).update({
        'pinnedAt': pinned ? Timestamp.fromDate(DateTime.now()) : FieldValue.delete(),
      });
      print('ClipService: ${pinned ? 'pinned' : 'unpinned'} clip $clipId');
      return true;
    } catch (e) {
      print('ClipService: pin error: $e');
      return false;
    }
  }
}