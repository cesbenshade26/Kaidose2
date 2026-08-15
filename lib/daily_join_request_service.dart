import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum JoinRequestStatus {
  pending,
  accepted,
  rejected,
}

class DailyJoinRequest {
  final String id;
  final String dailyId;
  final String dailyTitle;
  final String fromUserId;
  final String fromUsername;
  final String toUserId; // the owner who must approve
  final JoinRequestStatus status;
  final DateTime timestamp;

  DailyJoinRequest({
    required this.id,
    required this.dailyId,
    required this.dailyTitle,
    required this.fromUserId,
    required this.fromUsername,
    required this.toUserId,
    required this.status,
    required this.timestamp,
  });

  factory DailyJoinRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DailyJoinRequest(
      id: doc.id,
      dailyId: data['dailyId'] ?? '',
      dailyTitle: data['dailyTitle'] ?? '',
      fromUserId: data['fromUserId'] ?? '',
      fromUsername: data['fromUsername'] ?? '',
      toUserId: data['toUserId'] ?? '',
      status: JoinRequestStatus.values.firstWhere(
            (e) => e.toString().split('.').last == data['status'],
        orElse: () => JoinRequestStatus.pending,
      ),
      timestamp:
      (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dailyId': dailyId,
      'dailyTitle': dailyTitle,
      'fromUserId': fromUserId,
      'fromUsername': fromUsername,
      'toUserId': toUserId,
      'status': status.toString().split('.').last,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}

class DailyJoinRequestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Send a request to join a private Daily.
  /// [ownerUid] must be the creator's UID (DailyData.creatorUid).
  Future<Map<String, dynamic>> sendJoinRequest({
    required String dailyId,
    required String dailyTitle,
    required String ownerUid,
    required String fromUsername,
  }) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      if (currentUid == ownerUid) {
        return {'success': false, 'error': 'You already own this Daily'};
      }

      // Avoid duplicate pending requests
      final existing = await _firestore
          .collection('daily_join_requests')
          .where('dailyId', isEqualTo: dailyId)
          .where('fromUserId', isEqualTo: currentUid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existing.docs.isNotEmpty) {
        return {'success': false, 'error': 'Request already sent'};
      }

      final request = DailyJoinRequest(
        id: '',
        dailyId: dailyId,
        dailyTitle: dailyTitle,
        fromUserId: currentUid,
        fromUsername: fromUsername,
        toUserId: ownerUid,
        status: JoinRequestStatus.pending,
        timestamp: DateTime.now(),
      );

      await _firestore
          .collection('daily_join_requests')
          .add(request.toJson());

      return {'success': true};
    } catch (e) {
      print('Error sending join request: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Pending join requests where the current user is the owner being asked.
  Stream<List<DailyJoinRequest>> getPendingJoinRequests() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value([]);

    return _firestore
        .collection('daily_join_requests')
        .where('toUserId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => DailyJoinRequest.fromFirestore(doc))
        .toList());
  }

  /// Accept a join request — caller is responsible for then copying
  /// the Daily into the requester's account (see DailyJoinRequestService
  /// usage in NotificationsScreen, mirroring acceptDailyInvitation).
  Future<Map<String, dynamic>> acceptJoinRequest(String requestId) async {
    try {
      await _firestore
          .collection('daily_join_requests')
          .doc(requestId)
          .update({'status': 'accepted'});
      return {'success': true};
    } catch (e) {
      print('Error accepting join request: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> rejectJoinRequest(String requestId) async {
    try {
      await _firestore
          .collection('daily_join_requests')
          .doc(requestId)
          .update({'status': 'rejected'});
      return {'success': true};
    } catch (e) {
      print('Error rejecting join request: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<DailyJoinRequest?> getJoinRequestById(String requestId) async {
    try {
      final doc = await _firestore
          .collection('daily_join_requests')
          .doc(requestId)
          .get();
      if (!doc.exists) return null;
      return DailyJoinRequest.fromFirestore(doc);
    } catch (e) {
      print('Error getting join request: $e');
      return null;
    }
  }

  /// Check if the current user already has a pending request for a Daily.
  Future<bool> hasPendingRequest(String dailyId) async {
    final currentUid = currentUserId;
    if (currentUid == null) return false;
    try {
      final snap = await _firestore
          .collection('daily_join_requests')
          .where('dailyId', isEqualTo: dailyId)
          .where('fromUserId', isEqualTo: currentUid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (e) {
      print('Error checking pending request: $e');
      return false;
    }
  }
}