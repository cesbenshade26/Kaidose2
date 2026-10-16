import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Extracts a still frame from a video cover and uploads it to Storage, so
/// a video-covered Daily can actually show an image on its card, and so
/// DailyCoverHookService has a real frame to look at instead of
/// generating the hook with no visual information at all.
class DailyCoverThumbnail {
  static const Duration _timeout = Duration(seconds: 20);

  /// Returns the uploaded thumbnail's download URL, or null if extraction
  /// or upload failed. Callers should treat null exactly like "no
  /// thumbnail available" and fall back to the classic card — this never
  /// throws out to the caller.
  static Future<String?> generateAndUpload({
    required String dailyId,
    required String key,
    required String videoUrl,
  }) async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 768,
        quality: 70,
      ).timeout(_timeout);

      if (bytes == null || bytes.isEmpty) {
        print('DailyCoverThumbnail: extraction returned nothing for $dailyId');
        return null;
      }

      final ref = FirebaseStorage.instance
          .ref()
          .child('daily_cover_thumbnails/$dailyId/$key.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      print('DailyCoverThumbnail: generated thumbnail for $dailyId');
      return url;
    } catch (e) {
      print('DailyCoverThumbnail: failed for $dailyId: $e');
      return null;
    }
  }
}