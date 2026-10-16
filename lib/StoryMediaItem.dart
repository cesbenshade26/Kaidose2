import 'dart:io';

/// A single piece of story media, already downloaded/cached to a local
/// file regardless of whether it originated as a photo (base64 in
/// Firestore) or a video (uploaded to Firebase Storage). Callers key off
/// [isVideo] rather than caring how it got here.
class StoryMediaItem {
  final File file;
  final bool isVideo;

  StoryMediaItem({required this.file, required this.isVideo});
}