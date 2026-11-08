import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ChatMedia.dart';
import 'GroupChatService.dart';
import 'message_service.dart';

class ChatSettings {
  final String? wallpaperUrl;
  final bool wallpaperTopDark;

  /// Everyone who has muted notifications for this chat (per person).
  final List<String> mutedBy;

  const ChatSettings({
    this.wallpaperUrl,
    this.wallpaperTopDark = false,
    this.mutedBy = const [],
  });

  bool isMutedFor(String? uid) => uid != null && mutedBy.contains(uid);
}

class ChatMediaEntry {
  final String url;
  final String? previewUrl;
  final bool isVideo;
  final DateTime time;

  ChatMediaEntry({
    required this.url,
    this.previewUrl,
    required this.isVideo,
    required this.time,
  });
}

/// One chat, either a group or a 1:1 conversation, seen through the same
/// interface so the settings screens (media, wallpaper, ...) work for both.
class ChatTarget {
  final String? groupId;
  final String? friendUserId;
  final String? friendUsername;

  ChatTarget.group(String id)
      : groupId = id,
        friendUserId = null,
        friendUsername = null;

  ChatTarget.direct(
      {required String this.friendUserId, required String this.friendUsername})
      : groupId = null;

  bool get isGroup => groupId != null;

  String get _myId => FirebaseAuth.instance.currentUser?.uid ?? '';

  DocumentReference<Map<String, dynamic>> get _directDoc {
    final cid = MessageService().getChatConversationId(_myId, friendUserId!);
    return FirebaseFirestore.instance.collection('chats').doc(cid);
  }

  /// Wallpaper and its brightness flag.
  Stream<ChatSettings?> watchSettings() {
    if (isGroup) {
      return GroupChatService().watchGroup(groupId!).map((g) => g == null
          ? null
          : ChatSettings(
          wallpaperUrl: g.wallpaperUrl,
          wallpaperTopDark: g.wallpaperTopDark,
          mutedBy: g.mutedBy));
    }
    return _directDoc.snapshots().map((d) {
      final data = d.data();
      return ChatSettings(
        wallpaperUrl: data?['wallpaperUrl'] as String?,
        wallpaperTopDark: data?['wallpaperTopDark'] == true,
        mutedBy: List<String>.from(data?['mutedBy'] ?? const []),
      );
    });
  }

  /// Every photo and video in the chat, newest first.
  Stream<List<ChatMediaEntry>> watchMedia() {
    if (isGroup) {
      return GroupChatService().getMessages(groupId!).map((msgs) => msgs
          .where((m) => m.hasMedia)
          .map((m) => ChatMediaEntry(
        url: m.videoUrl ?? m.imageUrl!,
        previewUrl: m.videoUrl != null ? m.thumbUrl : m.imageUrl,
        isVideo: m.videoUrl != null,
        time: m.timestamp,
      ))
          .toList());
    }
    return MessageService().getChatMessages(friendUserId!).map((msgs) {
      final entries = <ChatMediaEntry>[];
      for (final m in msgs.reversed) {
        final type = m.metadata?['type'] as String?;
        final video = m.metadata?['videoUrl'] as String?;
        final image = m.metadata?['imageUrl'] as String?;
        if (type == 'clip' && video != null && video.isNotEmpty) {
          entries.add(ChatMediaEntry(
            url: video,
            previewUrl: m.metadata?['thumbUrl'] as String?,
            isVideo: true,
            time: m.timestamp,
          ));
        } else if (type == 'image' && image != null && image.isNotEmpty) {
          entries.add(ChatMediaEntry(
            url: image,
            previewUrl: image,
            isVideo: false,
            time: m.timestamp,
          ));
        }
      }
      return entries;
    });
  }

  /// Mute / unmute notifications for ME in this chat. (Stored now; it takes
  /// effect once notifications are set up.)
  Future<void> setMuted(bool muted) async {
    if (isGroup) return GroupChatService().setMuted(groupId!, muted);
    await _directDoc.set({
      'participants': [_myId, friendUserId],
      'mutedBy':
      muted ? FieldValue.arrayUnion([_myId]) : FieldValue.arrayRemove([_myId]),
    }, SetOptions(merge: true));
  }

  /// Pass null to remove the wallpaper.
  Future<void> setWallpaper(File? file, {required String byUsername}) async {
    if (isGroup) {
      return GroupChatService()
          .setWallpaper(groupId!, file, byUsername: byUsername);
    }
    final doc = _directDoc;
    if (file == null) {
      await doc.set({
        'wallpaperUrl': FieldValue.delete(),
        'wallpaperTopDark': FieldValue.delete(),
      }, SetOptions(merge: true));
      return;
    }
    final url = await ChatMediaUploader.uploadWallpaper(file,
        'chat_media/$_myId/wallpapers/${DateTime.now().millisecondsSinceEpoch}.jpg');
    final dark = await ChatMediaUploader.isTopDark(file);
    await doc.set({
      'participants': [_myId, friendUserId],
      'wallpaperUrl': url,
      'wallpaperTopDark': dark,
    }, SetOptions(merge: true));
  }
}