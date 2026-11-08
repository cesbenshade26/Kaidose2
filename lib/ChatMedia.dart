import 'dart:io';
import 'dart:ui' as ui;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'UnifiedMediaPicker.dart';

class UploadedChatMedia {
  final String url;
  final String? thumbUrl; // videos only
  final bool isVideo;

  UploadedChatMedia({required this.url, this.thumbUrl, required this.isVideo});
}

/// Uploads a photo or video picked for a chat to Firebase Storage.
class ChatMediaUploader {
  static const int maxVideoBytes = 100 * 1024 * 1024; // 100 MB

  /// [folder] e.g. "chat_media/<uid>" or "groupChats/<id>/media".
  static Future<UploadedChatMedia> upload(
      PickedMedia item, String folder) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return item.isVideo
        ? _uploadVideo(item.file, folder, stamp)
        : _uploadImage(item.file, folder, stamp);
  }

  static Future<UploadedChatMedia> _uploadImage(
      File file, String folder, int stamp) async {
    final bytes = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 1440,
      minHeight: 1440,
      quality: 82,
      format: CompressFormat.jpeg,
    );
    final ref = FirebaseStorage.instance.ref('$folder/$stamp.jpg');
    final meta = SettableMetadata(contentType: 'image/jpeg');
    final task = bytes != null
        ? await ref.putData(bytes, meta)
        : await ref.putFile(file, meta);
    return UploadedChatMedia(url: await task.ref.getDownloadURL(), isVideo: false);
  }

  static Future<UploadedChatMedia> _uploadVideo(
      File file, String folder, int stamp) async {
    if (await file.length() > maxVideoBytes) {
      throw Exception('Video is too large (max 100 MB)');
    }
    final lower = file.path.toLowerCase();
    final isMov = lower.endsWith('.mov');
    final ext = isMov ? 'mov' : 'mp4';
    final ref = FirebaseStorage.instance.ref('$folder/$stamp.$ext');
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: isMov ? 'video/quicktime' : 'video/mp4'),
    );
    final url = await task.ref.getDownloadURL();

    // A small still frame so grids and previews don't have to load the video.
    String? thumbUrl;
    try {
      final thumb = await VideoThumbnail.thumbnailData(
        video: file.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        quality: 70,
      );
      if (thumb != null) {
        final tRef = FirebaseStorage.instance.ref('$folder/${stamp}_thumb.jpg');
        final tTask = await tRef.putData(
            thumb, SettableMetadata(contentType: 'image/jpeg'));
        thumbUrl = await tTask.ref.getDownloadURL();
      }
    } catch (_) {}

    return UploadedChatMedia(url: url, thumbUrl: thumbUrl, isVideo: true);
  }

  /// Uploads a wallpaper photo (compressed) and returns its download URL.
  static Future<String> uploadWallpaper(File file, String path) async {
    final bytes = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 1080,
      minHeight: 1080,
      quality: 82,
      format: CompressFormat.jpeg,
    );
    final ref = FirebaseStorage.instance.ref(path);
    final meta = SettableMetadata(contentType: 'image/jpeg');
    final task = bytes != null
        ? await ref.putData(bytes, meta)
        : await ref.putFile(file, meta);
    return task.ref.getDownloadURL();
  }

  /// Whether the top of the photo (the part behind the title bar) is dark,
  /// so the bar's text and icons can switch to white. Plain average
  /// brightness of the top 20% of the image, no AI involved.
  static Future<bool> isTopDark(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 80);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return false;
      final w = img.width;
      final h = img.height;
      final rows = (h * 0.2).ceil().clamp(1, h);
      double sum = 0;
      int n = 0;
      for (int y = 0; y < rows; y++) {
        for (int x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          sum += (0.299 * data.getUint8(i) +
              0.587 * data.getUint8(i + 1) +
              0.114 * data.getUint8(i + 2)) /
              255;
          n++;
        }
      }
      return n > 0 && (sum / n) < 0.5;
    } catch (_) {
      return false;
    }
  }
}