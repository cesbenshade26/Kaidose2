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
  final String? parentMessageId; // NEW
  final String? parentText;      // NEW

  Message({
    required this.id,
    required this.senderId,
    required this.senderUsername,
    required this.text,
    required this.timestamp,
    this.read = false,
    required this.type,
    this.metadata,
    this.parentMessageId, // Added to constructor
    this.parentText,      // Added to constructor
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
      parentMessageId: data['parentMessageId'], // Map from Firestore
      parentText: data['parentText'],           // Map from Firestore
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
      'parentMessageId': parentMessageId, // Save to Firestore
      'parentText': parentText,           // Save to Firestore
    };
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

  // UPDATED: Added parent parameters to allow replies
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
        .map((snapshot) {
      return snapshot.docs.map((doc) => Message.fromFirestore(doc)).toList();
    });
  }

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

      for (var doc in unreadMessages.docs) {
        await doc.reference.update({'read': true});
      }
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // UPDATED: Removed change/remove logic. User is now "stuck" with the reaction.
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

  // ==================== DAILY MESSAGES (Included for completeness) ====================

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