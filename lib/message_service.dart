import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final Map<String, dynamic>? metadata; // For extra data like daily info, attachments, etc.

  Message({
    required this.id,
    required this.senderId,
    required this.senderUsername,
    required this.text,
    required this.timestamp,
    this.read = false,
    required this.type,
    this.metadata,
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
    };
  }
}

class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // ==================== CHAT MESSAGES (1-on-1) ====================

  // Generate conversation ID for 1-on-1 chat (alphabetically sorted)
  String getChatConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  // Send a chat message (1-on-1)
  Future<bool> sendChatMessage({
    required String recipientUserId,
    required String text,
    required String senderUsername,
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
      );

      await _firestore
          .collection('chats')
          .doc(conversationId)
          .collection('messages')
          .add(message.toJson());

      // Update conversation metadata (last message, timestamp)
      await _firestore.collection('chats').doc(conversationId).set({
        'participants': [currentUid, recipientUserId],
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': currentUid,
      }, SetOptions(merge: true));

      print('Chat message sent to $recipientUserId');
      return true;
    } catch (e) {
      print('Error sending chat message: $e');
      return false;
    }
  }

  // Get chat messages stream (1-on-1)
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

  // Mark chat messages as read
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
      print('Error marking chat messages as read: $e');
    }
  }

  // ==================== DAILY MESSAGES ====================

  // Send a daily message
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

      // Update daily metadata
      await _firestore.collection('dailies').doc(dailyId).set({
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSender': currentUid,
      }, SetOptions(merge: true));

      print('Daily message sent to daily $dailyId');
      return true;
    } catch (e) {
      print('Error sending daily message: $e');
      return false;
    }
  }

  // Get daily messages stream
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

  // Mark daily messages as read
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
      print('Error marking daily messages as read: $e');
    }
  }

  // ==================== UTILITY METHODS ====================

  // Delete a message (works for both chat and daily)
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
      print('Error deleting message: $e');
      return false;
    }
  }

  // Get unread message count for a conversation
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
      print('Error getting unread count: $e');
      return 0;
    }
  }
}