import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum FriendRequestStatus {
  pending,
  accepted,
  rejected,
}

class FriendRequest {
  final String id;
  final String fromUserId;
  final String fromUsername;
  final String toUserId;
  final String toUsername;
  final FriendRequestStatus status;
  final DateTime createdAt;

  FriendRequest({
    required this.id,
    required this.fromUserId,
    required this.fromUsername,
    required this.toUserId,
    required this.toUsername,
    required this.status,
    required this.createdAt,
  });

  factory FriendRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FriendRequest(
      id: doc.id,
      fromUserId: data['fromUserId'] ?? '',
      fromUsername: data['fromUsername'] ?? '',
      toUserId: data['toUserId'] ?? '',
      toUsername: data['toUsername'] ?? '',
      status: FriendRequestStatus.values.firstWhere(
            (e) => e.toString().split('.').last == data['status'],
        orElse: () => FriendRequestStatus.pending,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fromUserId': fromUserId,
      'fromUsername': fromUsername,
      'toUserId': toUserId,
      'toUsername': toUsername,
      'status': status.toString().split('.').last,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class FriendRequestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // Send a friend request
  Future<Map<String, dynamic>> sendFriendRequest({
    required String toUserId,
    required String toUsername,
    required String fromUsername,
  }) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) {
        return {'success': false, 'error': 'Not logged in'};
      }

      // Check if request already exists
      final existing = await _firestore
          .collection('friend_requests')
          .where('fromUserId', isEqualTo: currentUid)
          .where('toUserId', isEqualTo: toUserId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existing.docs.isNotEmpty) {
        return {'success': false, 'error': 'Request already sent'};
      }

      // Check if already friends
      final alreadyFriends = await _firestore
          .collection('friend_requests')
          .where('fromUserId', isEqualTo: currentUid)
          .where('toUserId', isEqualTo: toUserId)
          .where('status', isEqualTo: 'accepted')
          .get();

      if (alreadyFriends.docs.isNotEmpty) {
        return {'success': false, 'error': 'Already friends'};
      }

      // Also check reverse
      final reverseAccepted = await _firestore
          .collection('friend_requests')
          .where('fromUserId', isEqualTo: toUserId)
          .where('toUserId', isEqualTo: currentUid)
          .where('status', isEqualTo: 'accepted')
          .get();

      if (reverseAccepted.docs.isNotEmpty) {
        return {'success': false, 'error': 'Already friends'};
      }

      // Check reverse pending
      final reverseRequest = await _firestore
          .collection('friend_requests')
          .where('fromUserId', isEqualTo: toUserId)
          .where('toUserId', isEqualTo: currentUid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (reverseRequest.docs.isNotEmpty) {
        return {'success': false, 'error': 'They already sent you a request'};
      }

      // Create the friend request
      final request = FriendRequest(
        id: '',
        fromUserId: currentUid,
        fromUsername: fromUsername,
        toUserId: toUserId,
        toUsername: toUsername,
        status: FriendRequestStatus.pending,
        createdAt: DateTime.now(),
      );

      await _firestore.collection('friend_requests').add(request.toJson());

      print('Friend request sent to $toUsername');
      return {'success': true};
    } catch (e) {
      print('Error sending friend request: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Accept a friend request
  Future<Map<String, dynamic>> acceptFriendRequest(String requestId) async {
    try {
      await _firestore.collection('friend_requests').doc(requestId).update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      print('Friend request accepted: $requestId');
      return {'success': true};
    } catch (e) {
      print('Error accepting friend request: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Reject a friend request
  Future<Map<String, dynamic>> rejectFriendRequest(String requestId) async {
    try {
      await _firestore.collection('friend_requests').doc(requestId).update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      print('Friend request rejected: $requestId');
      return {'success': true};
    } catch (e) {
      print('Error rejecting friend request: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get pending requests sent TO current user
  Stream<List<FriendRequest>> getIncomingRequests() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value([]);

    return _firestore
        .collection('friend_requests')
        .where('toUserId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => FriendRequest.fromFirestore(doc))
          .toList();

      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return requests;
    });
  }

  // Get NEWLY ACCEPTED requests for YOUR outgoing requests (for notifications)
  Stream<List<FriendRequest>> getAcceptedOutgoingRequests() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value([]);

    return _firestore
        .collection('friend_requests')
        .where('fromUserId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => FriendRequest.fromFirestore(doc))
          .toList();

      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return requests;
    });
  }

  // Get pending requests sent BY current user
  Stream<List<FriendRequest>> getOutgoingRequests() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value([]);

    return _firestore
        .collection('friend_requests')
        .where('fromUserId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => FriendRequest.fromFirestore(doc))
          .toList();

      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return requests;
    });
  }

  // Get all accepted friends for current user
  Stream<List<FriendRequest>> getAcceptedFriends() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value([]);

    return _firestore
        .collection('friend_requests')
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => FriendRequest.fromFirestore(doc))
          .where((req) => req.fromUserId == currentUid || req.toUserId == currentUid)
          .toList();
    });
  }

  // Check if two users are friends (either direction)
  Future<bool> areFriends(String userId1, String userId2) async {
    try {
      final query1 = await _firestore
          .collection('friend_requests')
          .where('fromUserId', isEqualTo: userId1)
          .where('toUserId', isEqualTo: userId2)
          .where('status', isEqualTo: 'accepted')
          .get();

      if (query1.docs.isNotEmpty) return true;

      final query2 = await _firestore
          .collection('friend_requests')
          .where('fromUserId', isEqualTo: userId2)
          .where('toUserId', isEqualTo: userId1)
          .where('status', isEqualTo: 'accepted')
          .get();

      return query2.docs.isNotEmpty;
    } catch (e) {
      print('Error checking friendship: $e');
      return false;
    }
  }

  // Get count of incoming pending requests
  Stream<int> getIncomingRequestCount() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value(0);

    return _firestore
        .collection('friend_requests')
        .where('toUserId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Get count of ACCEPTED outgoing requests (for "X accepted your request" notifications)
  Stream<int> getAcceptedOutgoingCount() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value(0);

    return _firestore
        .collection('friend_requests')
        .where('fromUserId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}