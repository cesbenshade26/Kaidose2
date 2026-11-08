import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_reactions.dart';

enum MessageType {
  chat,        // 1-on-1 chat between friends
  daily,       // Messages in a daily
  group,       // Future: group chats
}

class Message {
  final String id;
  final String senderId;
  final String senderUsername;
  final String text;
  final DateTime timestamp;
  final bool read;
  final MessageType type;
  final Map<String, dynamic>? metadata;
  final String? parentMessageId;
  final String? parentText;
  final DateTime? deleteAfter; // legacy shared timer (old system)
  final bool hasBeenViewed;
  final bool isSaved;

  /// When the recipient first saw it (1:1 chats).
  final DateTime? readAt;

  /// Per-person hide time: userId -> when the message disappears FOR THAT
  /// PERSON. Hidden messages stay on the server (soft delete) until everyone
  /// in the chat has hidden them and the retention period has passed.
  final Map<String, DateTime> expiresAt;

  Message({
    required this.id,
    required this.senderId,
    required this.senderUsername,
    required this.text,
    required this.timestamp,
    this.read = false,
    required this.type,
    this.metadata,
    this.parentMessageId,
    this.parentText,
    this.deleteAfter,
    this.hasBeenViewed = false,
    this.isSaved = false,
    this.readAt,
    this.expiresAt = const {},
  });

  /// When this message disappears for [uid] (null = never / not started).
  DateTime? expiryFor(String uid) => expiresAt[uid];

  /// Is this message visible to [uid] right now?
  bool isVisibleTo(String uid, DateTime now) {
    if (isSaved) return true;
    final mine = expiresAt[uid];
    if (mine != null && !now.isBefore(mine)) return false;
    // Legacy shared timer from the old system.
    if (deleteAfter != null && !now.isBefore(deleteAfter!)) return false;
    return true;
  }

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final rawExpires = data['expiresAt'];
    final expires = <String, DateTime>{};
    if (rawExpires is Map) {
      rawExpires.forEach((k, v) {
        if (v is Timestamp) expires[k.toString()] = v.toDate();
      });
    }

    return Message(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderUsername: data['senderUsername'] ?? '',
      text: data['text'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      read: data['read'] ?? false,
      type: MessageType.values.firstWhere(
            (e) => e.toString().split('.').last == data['type'],
        orElse: () => MessageType.chat,
      ),
      metadata: data['metadata'] as Map<String, dynamic>?,
      parentMessageId: data['parentMessageId'],
      parentText: data['parentText'],
      deleteAfter: (data['deleteAfter'] as Timestamp?)?.toDate(),
      hasBeenViewed: data['hasBeenViewed'] ?? false,
      isSaved: data['isSaved'] ?? false,
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
      expiresAt: expires,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId,
      'senderUsername': senderUsername,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'read': read,
      'type': type.toString().split('.').last,
      'metadata': metadata,
      'parentMessageId': parentMessageId,
      'parentText': parentText,
      'deleteAfter': deleteAfter != null ? Timestamp.fromDate(deleteAfter!) : null,
      'hasBeenViewed': hasBeenViewed,
      'isSaved': isSaved,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
      if (expiresAt.isNotEmpty)
        'expiresAt': expiresAt.map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
    };
  }

  Message copyWith({
    String? id,
    String? senderId,
    String? senderUsername,
    String? text,
    DateTime? timestamp,
    bool? read,
    MessageType? type,
    Map<String, dynamic>? metadata,
    String? parentMessageId,
    String? parentText,
    DateTime? deleteAfter,
    bool? hasBeenViewed,
    bool? isSaved,
    DateTime? readAt,
    Map<String, DateTime>? expiresAt,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderUsername: senderUsername ?? this.senderUsername,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      read: read ?? this.read,
      type: type ?? this.type,
      metadata: metadata ?? this.metadata,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      parentText: parentText ?? this.parentText,
      deleteAfter: deleteAfter ?? this.deleteAfter,
      hasBeenViewed: hasBeenViewed ?? this.hasBeenViewed,
      isSaved: isSaved ?? this.isSaved,
      readAt: readAt ?? this.readAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  String getChatConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  // ==================== DISAPPEARING MESSAGES (per person) ====================
  //
  // Each person picks their own setting for a chat, stored at
  //   chats/{cid}.deleteOptions.{uid}
  // It only controls what THAT person sees. Messages are never hard-deleted
  // here: they get a per-person `expiresAt` stamp and are hidden for that
  // person. A Cloud Function permanently purges a message (and its Storage
  // files) 30 days after the last participant has hidden it.

  /// Option -> how long after viewing a message disappears.
  static const Map<String, Duration> _durations = {
    '1h': Duration(hours: 1),
    '3h': Duration(hours: 3),
    '24h': Duration(hours: 24),
    '3d': Duration(days: 3),
    '7d': Duration(days: 7),
    '30d': Duration(days: 30),
    '365d': Duration(days: 365),
  };

  static Duration? durationFor(String option) => _durations[option];

  /// "off", "after_viewing", or a timer key like "24h".
  Future<String> _myOption(String conversationId) async {
    final uid = currentUserId;
    if (uid == null) return 'off';
    try {
      final doc = await _firestore.collection('chats').doc(conversationId).get();
      final opts = doc.data()?['deleteOptions'];
      if (opts is Map) {
        final v = opts[uid];
        if (v is String) return v == 'on_close' ? 'after_viewing' : v;
      }
    } catch (e) {
      print('Error reading chat option: $e');
    }
    return 'off';
  }

  /// Save MY setting for this chat. Doesn't touch the other person's.
  Future<void> saveChatSettings({
    required String recipientUserId,
    required String deleteOption,
  }) async {
    final currentUid = currentUserId;
    if (currentUid == null) return;
    final conversationId = getChatConversationId(currentUid, recipientUserId);

    await _firestore.collection('chats').doc(conversationId).set({
      'participants': [currentUid, recipientUserId],
      'deleteOptions': {currentUid: deleteOption},
    }, SetOptions(merge: true));
  }

  /// MY setting for this chat.
  Future<String> getChatSettings(String recipientUserId) async {
    final currentUid = currentUserId;
    if (currentUid == null) return 'off';
    final conversationId = getChatConversationId(currentUid, recipientUserId);
    return _myOption(conversationId);
  }

  /// For "After viewing": hide everything I've already seen (my own sent
  /// messages, and received messages I've read). Call when the chat opens
  /// (catches anything left from a session that was killed) and when it
  /// closes.
  Future<void> onChatClosed(String recipientUserId) async {
    try {
      final me = currentUserId;
      if (me == null) return;
      final cid = getChatConversationId(me, recipientUserId);
      if (await _myOption(cid) != 'after_viewing') return;

      final snap = await _firestore
          .collection('chats')
          .doc(cid)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(300)
          .get();

      final now = Timestamp.now();
      WriteBatch batch = _firestore.batch();
      int count = 0;

      for (final doc in snap.docs) {
        final m = Message.fromFirestore(doc);
        if (m.isSaved) continue;
        if (m.expiresAt.containsKey(me)) continue;
        final seen = m.senderId == me || m.read;
        if (!seen) continue;

        batch.update(doc.reference, {'expiresAt.$me': now});
        if (++count >= 400) {
          await batch.commit();
          batch = _firestore.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    } catch (e) {
      print('Error expiring seen messages: $e');
    }
  }

  // ==================== 1:1 CHAT ====================

  // Send a chat message
  Future<bool> sendChatMessage({
    required String recipientUserId,
    required String text,
    required String senderUsername,
    String? parentMessageId,
    String? parentText,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return false;

      final conversationId = getChatConversationId(currentUid, recipientUserId);

      // MY timer starts when I send (I've obviously seen it). The other
      // person's timer starts when THEY see it, using THEIR setting.
      final option = await _myOption(conversationId);
      final d = durationFor(option);
      final expires = <String, DateTime>{
        if (d != null) currentUid: DateTime.now().add(d),
      };

      final message = Message(
        id: '',
        senderId: currentUid,
        senderUsername: senderUsername,
        text: text,
        timestamp: DateTime.now(),
        read: false,
        type: MessageType.chat,
        metadata: metadata,
        parentMessageId: parentMessageId,
        parentText: parentText,
        expiresAt: expires,
      );

      await _firestore
          .collection('chats')
          .doc(conversationId)
          .collection('messages')
          .add(message.toJson());

      String preview = text;
      if (preview.isEmpty && metadata != null) {
        preview = metadata['type'] == 'clip' ? 'Video' : 'Photo';
      }

      await _firestore.collection('chats').doc(conversationId).set({
        'participants': [currentUid, recipientUserId],
        'lastMessage': preview,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': currentUid,
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      print('Error sending chat message: $e');
      return false;
    }
  }

  // Get chat messages as I see them. Nothing is deleted here -- messages that
  // have expired for me are simply hidden. Re-checked every 20s so messages
  // vanish while the chat is open.
  Stream<List<Message>> getChatMessages(String recipientUserId) {
    final me = currentUserId;
    if (me == null) return Stream.value([]);
    final conversationId = getChatConversationId(me, recipientUserId);

    late StreamController<List<Message>> controller;
    StreamSubscription? sub;
    Timer? timer;
    List<Message> latest = [];

    void emit() {
      if (controller.isClosed) return;
      final now = DateTime.now();
      controller.add(latest.where((m) => m.isVisibleTo(me, now)).toList());
    }

    controller = StreamController<List<Message>>(
      onListen: () {
        sub = _firestore
            .collection('chats')
            .doc(conversationId)
            .collection('messages')
            .orderBy('timestamp', descending: false)
            .snapshots()
            .listen((snapshot) {
          latest = snapshot.docs.map((d) => Message.fromFirestore(d)).toList();
          emit();
        }, onError: controller.addError);
        timer = Timer.periodic(const Duration(seconds: 20), (_) => emit());
      },
      onCancel: () {
        timer?.cancel();
        sub?.cancel();
      },
    );
    return controller.stream;
  }

  // Mark messages as read, and start MY timer on them
  Future<void> markChatMessagesAsRead(String recipientUserId) async {
    try {
      final me = currentUserId;
      if (me == null) return;
      final conversationId = getChatConversationId(me, recipientUserId);

      final unread = await _firestore
          .collection('chats')
          .doc(conversationId)
          .collection('messages')
          .where('senderId', isEqualTo: recipientUserId)
          .where('read', isEqualTo: false)
          .get();
      if (unread.docs.isEmpty) return;

      final d = durationFor(await _myOption(conversationId));
      final now = DateTime.now();

      WriteBatch batch = _firestore.batch();
      int count = 0;
      for (final doc in unread.docs) {
        final Map<String, dynamic> update = {
          'read': true,
          'readAt': Timestamp.fromDate(now),
          'hasBeenViewed': true,
        };
        if (d != null) {
          update['expiresAt.$me'] = Timestamp.fromDate(now.add(d));
        }
        batch.update(doc.reference, update);
        if (++count >= 400) {
          await batch.commit();
          batch = _firestore.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // Toggle message saved status
  Future<void> toggleMessageSaved({
    required String recipientUserId,
    required String messageId,
    required bool isSaved,
  }) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return;
      final conversationId = getChatConversationId(currentUid, recipientUserId);

      await _firestore
          .collection('chats')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .update({'isSaved': isSaved});
    } catch (e) {
      print('Error toggling message saved: $e');
    }
  }

  // Add reaction (unchanged)
  Future<bool> addReaction({
    required String recipientUserId,
    required String messageId,
    required String emoji,
    required String username,
  }) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return false;

      final conversationId = getChatConversationId(currentUid, recipientUserId);

      final existingReactions = await _firestore
          .collection('chats')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .collection('reactions')
          .doc(currentUid)
          .get();

      if (existingReactions.exists) return false;

      final reaction = {
        'emoji': emoji,
        'user_id': currentUid,
        'username': username,
        'timestamp': FieldValue.serverTimestamp(),
      };

      await _firestore
          .collection('chats')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .collection('reactions')
          .doc(currentUid)
          .set(reaction);

      return true;
    } catch (e) {
      return false;
    }
  }

  Stream<List<ChatReaction>> getMessageReactions({
    required String recipientUserId,
    required String messageId,
  }) {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value([]);
    final conversationId = getChatConversationId(currentUid, recipientUserId);

    return _firestore
        .collection('chats')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .collection('reactions')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ChatReaction.fromJson(doc.data())).toList();
    });
  }

  // ==================== DAILY MESSAGES (Unchanged) ====================

  Future<bool> sendDailyMessage({
    required String dailyId,
    required String text,
    required String senderUsername,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return false;

      final message = Message(
        id: '',
        senderId: currentUid,
        senderUsername: senderUsername,
        text: text,
        timestamp: DateTime.now(),
        read: false,
        type: MessageType.daily,
        metadata: metadata,
      );

      await _firestore
          .collection('dailies')
          .doc(dailyId)
          .collection('messages')
          .add(message.toJson());

      return true;
    } catch (e) {
      return false;
    }
  }

  Stream<List<Message>> getDailyMessages(String dailyId) {
    return _firestore
        .collection('dailies')
        .doc(dailyId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Message.fromFirestore(doc)).toList();
    });
  }

  Future<void> markDailyMessagesAsRead(String dailyId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return;
      final unreadMessages = await _firestore
          .collection('dailies')
          .doc(dailyId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUid)
          .where('read', isEqualTo: false)
          .get();

      for (var doc in unreadMessages.docs) {
        await doc.reference.update({'read': true});
      }
    } catch (e) {
      print(e);
    }
  }

  Future<bool> deleteMessage({
    required String messageId,
    required String conversationId,
    required MessageType type,
  }) async {
    try {
      final collection = type == MessageType.daily ? 'dailies' : 'chats';
      await _firestore
          .collection(collection)
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<int> getUnreadCount({
    required String conversationId,
    required MessageType type,
  }) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return 0;
      final collection = type == MessageType.daily ? 'dailies' : 'chats';

      final unreadMessages = await _firestore
          .collection(collection)
          .doc(conversationId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUid)
          .where('read', isEqualTo: false)
          .get();

      return unreadMessages.docs.length;
    } catch (e) {
      return 0;
    }
  }
}