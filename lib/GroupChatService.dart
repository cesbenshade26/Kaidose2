import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_reactions.dart';
import 'ChatMedia.dart';
import 'UnifiedMediaPicker.dart';

/// A group chat. Stored at groupChats/{id}.
class GroupChat {
  final String id;
  final List<String> memberIds;
  final Map<String, String> memberUsernames; // uid -> username
  final String createdBy;
  final String? lastMessageText;
  final String? lastSenderUsername;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final String? name;
  final String? wallpaperUrl;
  final bool wallpaperTopDark;
  final List<String> pinnedBy;
  final List<String> mutedBy;

  GroupChat({
    required this.id,
    required this.memberIds,
    required this.memberUsernames,
    required this.createdBy,
    this.lastMessageText,
    this.lastSenderUsername,
    this.lastMessageAt,
    this.createdAt,
    this.name,
    this.wallpaperUrl,
    this.wallpaperTopDark = false,
    this.pinnedBy = const [],
    this.mutedBy = const [],
  });

  factory GroupChat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return GroupChat(
      id: doc.id,
      memberIds: List<String>.from(d['memberIds'] ?? const []),
      memberUsernames: Map<String, String>.from(d['memberUsernames'] ?? {}),
      createdBy: d['createdBy'] ?? '',
      lastMessageText: d['lastMessageText'] as String?,
      lastSenderUsername: d['lastSenderUsername'] as String?,
      lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      name: d['name'] as String?,
      wallpaperUrl: d['wallpaperUrl'] as String?,
      wallpaperTopDark: d['wallpaperTopDark'] == true,
      pinnedBy: List<String>.from(d['pinnedBy'] ?? const []),
      mutedBy: List<String>.from(d['mutedBy'] ?? const []),
    );
  }

  /// "Aaron, David, Charlie" (everyone except [myUid]).
  String namesExcluding(String? myUid) {
    final names = memberIds
        .where((id) => id != myUid)
        .map((id) => memberUsernames[id] ?? 'Unknown')
        .toList();
    return names.join(', ');
  }

  bool get hasName => name != null && name!.trim().isNotEmpty;

  /// The group's name if it has one, otherwise "Aaron, David, Charlie".
  String displayName(String? myUid) =>
      hasName ? name!.trim() : namesExcluding(myUid);

  bool isPinnedFor(String? uid) => uid != null && pinnedBy.contains(uid);

  bool isMutedFor(String? uid) => uid != null && mutedBy.contains(uid);

  DateTime get sortTime =>
      lastMessageAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class GroupMessage {
  final String id;
  final String text;
  final String senderId;
  final String senderUsername;
  final DateTime timestamp;
  final String? parentMessageId;
  final String? parentText;
  final String? imageUrl;
  final String? videoUrl;
  final String? thumbUrl;
  final bool isSystem;

  /// Set when this was sent from a Daily ({dailyId, dailyTitle, private}).
  final Map<String, dynamic>? source;

  GroupMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderUsername,
    required this.timestamp,
    this.parentMessageId,
    this.parentText,
    this.imageUrl,
    this.videoUrl,
    this.thumbUrl,
    this.isSystem = false,
    this.source,
  });

  bool get hasMedia =>
      (imageUrl != null && imageUrl!.isNotEmpty) ||
          (videoUrl != null && videoUrl!.isNotEmpty);

  factory GroupMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return GroupMessage(
      id: doc.id,
      text: d['text'] ?? '',
      senderId: d['senderId'] ?? '',
      senderUsername: d['senderUsername'] ?? '',
      timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      parentMessageId: d['parentMessageId'] as String?,
      parentText: d['parentText'] as String?,
      imageUrl: d['imageUrl'] as String?,
      videoUrl: d['videoUrl'] as String?,
      thumbUrl: d['thumbUrl'] as String?,
      isSystem: d['system'] == true,
      source: d['source'] is Map
          ? Map<String, dynamic>.from(d['source'] as Map)
          : null,
    );
  }
}

class GroupChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groupChats');

  /// Every group the current user is in, newest activity first.
  Stream<List<GroupChat>> getMyGroups() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    return _groups.where('memberIds', arrayContains: uid).snapshots().map((s) {
      final list = s.docs.map(GroupChat.fromDoc).toList();
      list.sort((a, b) {
        final ap = a.isPinnedFor(uid) ? 1 : 0;
        final bp = b.isPinnedFor(uid) ? 1 : 0;
        if (ap != bp) return bp - ap;
        return b.sortTime.compareTo(a.sortTime);
      });
      return list;
    });
  }

  Stream<GroupChat?> watchGroup(String groupId) {
    return _groups
        .doc(groupId)
        .snapshots()
        .map((d) => d.exists ? GroupChat.fromDoc(d) : null);
  }

  /// [others] maps uid -> username for everyone except the current user.
  Future<String> createGroup({
    required Map<String, String> others,
    required String myUsername,
  }) async {
    final uid = currentUserId!;
    final usernames = {uid: myUsername, ...others};
    final doc = await _groups.add({
      'memberIds': [uid, ...others.keys],
      'memberUsernames': usernames,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Newest first (the chat list is reversed).
  Stream<List<GroupMessage>> getMessages(String groupId) {
    return _groups
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((s) => s.docs.map(GroupMessage.fromDoc).toList());
  }

  Future<void> sendMessage({
    required String groupId,
    required String text,
    required String senderUsername,
    String? parentMessageId,
    String? parentText,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    final ref = _groups.doc(groupId);
    await ref.collection('messages').add({
      'text': text,
      'senderId': uid,
      'senderUsername': senderUsername,
      'timestamp': FieldValue.serverTimestamp(),
      if (parentMessageId != null) 'parentMessageId': parentMessageId,
      if (parentText != null) 'parentText': parentText,
    });
    await ref.update({
      'lastMessageText': text,
      'lastSenderUsername': senderUsername,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  /// A message sent into the group from a Daily (text and/or an already
  /// uploaded photo/video URL), tagged with the Daily it came from.
  Future<void> sendSharedFromDaily({
    required String groupId,
    required String senderUsername,
    String text = '',
    String? imageUrl,
    String? videoUrl,
    required Map<String, dynamic> source,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    final ref = _groups.doc(groupId);
    await ref.collection('messages').add({
      'text': text,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (videoUrl != null) 'videoUrl': videoUrl,
      'source': source,
      'senderId': uid,
      'senderUsername': senderUsername,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await ref.update({
      'lastMessageText': text.isNotEmpty
          ? text
          : (videoUrl != null ? 'Video' : (imageUrl != null ? 'Photo' : '')),
      'lastSenderUsername': senderUsername,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _systemMessage(String groupId, String text) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _groups.doc(groupId).collection('messages').add({
      'text': text,
      'system': true,
      'senderId': uid,
      'senderUsername': '',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Photo or video message (with an optional caption / reply).
  Future<void> sendMedia({
    required String groupId,
    required PickedMedia media,
    required String senderUsername,
    String text = '',
    String? parentMessageId,
    String? parentText,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    final up = await ChatMediaUploader.upload(
        media, 'groupChats/$groupId/media');
    final ref = _groups.doc(groupId);
    await ref.collection('messages').add({
      'text': text,
      if (up.isVideo) 'videoUrl': up.url else 'imageUrl': up.url,
      if (up.thumbUrl != null) 'thumbUrl': up.thumbUrl,
      'senderId': uid,
      'senderUsername': senderUsername,
      'timestamp': FieldValue.serverTimestamp(),
      if (parentMessageId != null) 'parentMessageId': parentMessageId,
      if (parentText != null) 'parentText': parentText,
    });
    await ref.update({
      'lastMessageText':
      text.isNotEmpty ? text : (up.isVideo ? 'Video' : 'Photo'),
      'lastSenderUsername': senderUsername,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> _uploadImage(File file, String path,
      {required int maxWidth}) async {
    final bytes = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: maxWidth,
      minHeight: maxWidth,
      quality: 82,
      format: CompressFormat.jpeg,
    );
    final storageRef = FirebaseStorage.instance.ref(path);
    final task = bytes != null
        ? await storageRef.putData(
        bytes, SettableMetadata(contentType: 'image/jpeg'))
        : await storageRef.putFile(
        file, SettableMetadata(contentType: 'image/jpeg'));
    return task.ref.getDownloadURL();
  }

  /// Wallpaper is shared by everyone in the group. Pass null to remove it.
  Future<void> setWallpaper(String groupId, File? file,
      {required String byUsername}) async {
    if (file == null) {
      await _groups.doc(groupId).update({
        'wallpaperUrl': FieldValue.delete(),
        'wallpaperTopDark': FieldValue.delete(),
      });
      return;
    }
    final url = await _uploadImage(
        file, 'groupChats/$groupId/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg',
        maxWidth: 1080);
    final topDark = await _isTopDark(file);
    await _groups.doc(groupId).update({
      'wallpaperUrl': url,
      'wallpaperTopDark': topDark,
    });
    await _systemMessage(groupId, '$byUsername changed the wallpaper');
  }

  Future<bool> _isTopDark(File file) => ChatMediaUploader.isTopDark(file);

  /// Empty name clears it (falls back to the member list).
  Future<void> renameGroup(String groupId, String name,
      {required String byUsername}) async {
    final trimmed = name.trim();
    await _groups.doc(groupId).update({
      'name': trimmed.isEmpty ? FieldValue.delete() : trimmed,
    });
    await _systemMessage(
      groupId,
      trimmed.isEmpty
          ? '$byUsername removed the group name'
          : '$byUsername named the group "$trimmed"',
    );
  }

  /// Anyone in the group can remove anyone.
  Future<void> kickMember({
    required String groupId,
    required String memberId,
    required String memberUsername,
    required String byUsername,
  }) async {
    await _groups.doc(groupId).update({
      'memberIds': FieldValue.arrayRemove([memberId]),
      'memberUsernames.$memberId': FieldValue.delete(),
      'pinnedBy': FieldValue.arrayRemove([memberId]),
      'mutedBy': FieldValue.arrayRemove([memberId]),
    });
    await _systemMessage(groupId, '$byUsername removed $memberUsername');
  }

  /// "Delete" for the current user: leave the group. Once the last person
  /// leaves, the group document is removed.
  Future<void> leaveGroup(String groupId, {required String myUsername}) async {
    final uid = currentUserId;
    if (uid == null) return;
    final ref = _groups.doc(groupId);
    final snap = await ref.get();
    final members = List<String>.from(snap.data()?['memberIds'] ?? const []);
    if (members.length <= 1) {
      await ref.delete();
      return;
    }
    await _systemMessage(groupId, '$myUsername left');
    await ref.update({
      'memberIds': FieldValue.arrayRemove([uid]),
      'memberUsernames.$uid': FieldValue.delete(),
      'pinnedBy': FieldValue.arrayRemove([uid]),
      'mutedBy': FieldValue.arrayRemove([uid]),
    });
  }

  Future<void> setMuted(String groupId, bool muted) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _groups.doc(groupId).update({
      'mutedBy':
      muted ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
    });
  }

  Future<void> togglePin(String groupId, bool pin) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _groups.doc(groupId).update({
      'pinnedBy':
      pin ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
    });
  }

  /// One reaction per person per message. Once you react it stays: it
  /// can't be changed or removed (same as 1:1 chats).
  Future<void> toggleReaction({
    required String groupId,
    required String messageId,
    required String emoji,
    required String username,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    final ref = _groups
        .doc(groupId)
        .collection('messages')
        .doc(messageId)
        .collection('reactions')
        .doc(uid);
    final existing = await ref.get();
    if (existing.exists) return;
    await ref.set({
      'emoji': emoji,
      'user_id': uid,
      'username': username,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Stream<List<ChatReaction>> getReactions({
    required String groupId,
    required String messageId,
  }) {
    return _groups
        .doc(groupId)
        .collection('messages')
        .doc(messageId)
        .collection('reactions')
        .snapshots()
        .map((s) => s.docs.map((d) => ChatReaction.fromJson(d.data())).toList());
  }
}