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
  final DateTime? deleteAfter; // NEW
  final bool hasBeenViewed; // NEW
  final bool isSaved; // NEW

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
  });

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
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

  // Get delete duration for a chat
  Future<Duration?> _getDeleteDuration(String recipientUserId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return null;

      final conversationId = getChatConversationId(currentUid, recipientUserId);
      final chatDoc = await _firestore.collection('chats').doc(conversationId).get();

      if (!chatDoc.exists) return null;

      final data = chatDoc.data();
      final deleteOption = data?['deleteOption'] as String?;

      switch (deleteOption) {
        case '24h':
          return const Duration(hours: 24);
        case '7d':
          return const Duration(days: 7);
        case 'on_close':
          return null; // Handled separately
        default:
          return null; // Permanent
      }
    } catch (e) {
      print('Error getting delete duration: $e');
      return null;
    }
  }

  // Send a chat message with disappearing message support
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
      final deleteDuration = await _getDeleteDuration(recipientUserId);

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
        deleteAfter: deleteDuration != null
            ? DateTime.now().add(deleteDuration)
            : null,
        hasBeenViewed: false,
        isSaved: false,
      );

      await _firestore
          .collection('chats')
          .doc(conversationId)
          .collection('messages')
          .add(message.toJson());

      await _firestore.collection('chats').doc(conversationId).set({
        'participants': [currentUid, recipientUserId],
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': currentUid,
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      print('Error sending chat message: $e');
      return false;
    }
  }

  // Get chat messages (filtered to exclude expired ones)
  Stream<List<Message>> getChatMessages(String recipientUserId) {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value([]);
    final conversationId = getChatConversationId(currentUid, recipientUserId);

    return _firestore
        .collection('chats')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .asyncMap((snapshot) async {
      final messages = snapshot.docs
          .map((doc) => Message.fromFirestore(doc))
          .toList();

      // Filter out expired messages (not saved)
      final now = DateTime.now();
      final validMessages = messages.where((msg) {
        if (msg.isSaved) return true; // Saved messages never delete
        if (msg.deleteAfter == null) return true; // Permanent messages
        return now.isBefore(msg.deleteAfter!); // Not expired yet
      }).toList();

      // Delete expired messages from Firestore
      for (var msg in messages) {
        if (!msg.isSaved &&
            msg.deleteAfter != null &&
            now.isAfter(msg.deleteAfter!)) {
          await _firestore
              .collection('chats')
              .doc(conversationId)
              .collection('messages')
              .doc(msg.id)
              .delete();
        }
      }

      return validMessages;
    });
  }

  // Mark messages as viewed and set delete timers
  Future<void> markChatMessagesAsRead(String recipientUserId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return;
      final conversationId = getChatConversationId(currentUid, recipientUserId);

      final unreadMessages = await _firestore
          .collection('chats')
          .doc(conversationId)
          .collection('messages')
          .where('senderId', isEqualTo: recipientUserId)
          .where('read', isEqualTo: false)
          .get();

      final deleteDuration = await _getDeleteDuration(recipientUserId);

      for (var doc in unreadMessages.docs) {
        final Map<String, dynamic> updateData = {'read': true}; // FIXED: Explicit type

        // If message hasn't been viewed yet and has a delete duration, set timer
        final msgData = doc.data();
        if (msgData['hasBeenViewed'] != true && deleteDuration != null) {
          updateData['hasBeenViewed'] = true;
          updateData['deleteAfter'] = Timestamp.fromDate(
              DateTime.now().add(deleteDuration)
          );
        }

        await doc.reference.update(updateData);
      }
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

  // Save chat settings (delete option)
  Future<void> saveChatSettings({
    required String recipientUserId,
    required String deleteOption,
  }) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return;
      final conversationId = getChatConversationId(currentUid, recipientUserId);

      await _firestore.collection('chats').doc(conversationId).set({
        'deleteOption': deleteOption,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving chat settings: $e');
    }
  }

  // Get chat settings
  Future<String> getChatSettings(String recipientUserId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return 'off';
      final conversationId = getChatConversationId(currentUid, recipientUserId);

      final doc = await _firestore.collection('chats').doc(conversationId).get();
      if (!doc.exists) return 'off';

      final data = doc.data();
      return data?['deleteOption'] as String? ?? 'off';
    } catch (e) {
      print('Error getting chat settings: $e');
      return 'off';
    }
  }

  // Clean up "on close" messages
  Future<void> cleanupOnCloseMessages(String recipientUserId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return;
      final conversationId = getChatConversationId(currentUid, recipientUserId);

      // Check if "on_close" is enabled
      final chatDoc = await _firestore.collection('chats').doc(conversationId).get();
      if (!chatDoc.exists) return;

      final data = chatDoc.data();
      final deleteOption = data?['deleteOption'] as String?;

      if (deleteOption != 'on_close') return;

      // Delete all non-saved messages
      final messages = await _firestore
          .collection('chats')
          .doc(conversationId)
          .collection('messages')
          .where('isSaved', isEqualTo: false)
          .get();

      for (var doc in messages.docs) {
        await doc.reference.delete();
      }

      print('Cleaned up on-close messages for $conversationId');
    } catch (e) {
      print('Error cleaning up on-close messages: $e');
    }
  }

  // Add reaction (unchanged from original)
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