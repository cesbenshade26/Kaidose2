import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum DailyInvitationStatus {
  pending,
  accepted,
  rejected,
}

class DailyInvitation {
  final String id;
  final String dailyId;
  final String dailyTitle;
  final String fromUserId;
  final String fromUsername;
  final String toUserId;
  final String toUsername;
  final DailyInvitationStatus status;
  final DateTime timestamp;

  DailyInvitation({
    required this.id,
    required this.dailyId,
    required this.dailyTitle,
    required this.fromUserId,
    required this.fromUsername,
    required this.toUserId,
    required this.toUsername,
    required this.status,
    required this.timestamp,
  });

  factory DailyInvitation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DailyInvitation(
      id: doc.id,
      dailyId: data['dailyId'] ?? '',
      dailyTitle: data['dailyTitle'] ?? '',
      fromUserId: data['fromUserId'] ?? '',
      fromUsername: data['fromUsername'] ?? '',
      toUserId: data['toUserId'] ?? '',
      toUsername: data['toUsername'] ?? '',
      status: DailyInvitationStatus.values.firstWhere(
            (e) => e.toString().split('.').last == data['status'],
        orElse: () => DailyInvitationStatus.pending,
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
      'toUsername': toUsername,
      'status': status.toString().split('.').last,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}

class DailyInvitationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // Send a daily invitation
  Future<Map<String, dynamic>> sendDailyInvitation({
    required String dailyId,
    required String dailyTitle,
    required String toUserId,
    required String toUsername,
    required String fromUsername,
  }) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      // Check if invitation already exists
      final existingInvitation = await _firestore
          .collection('daily_invitations')
          .where('dailyId', isEqualTo: dailyId)
          .where('toUserId', isEqualTo: toUserId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingInvitation.docs.isNotEmpty) {
        return {'success': false, 'error': 'Invitation already sent'};
      }

      final invitation = DailyInvitation(
        id: '',
        dailyId: dailyId,
        dailyTitle: dailyTitle,
        fromUserId: currentUid,
        fromUsername: fromUsername,
        toUserId: toUserId,
        toUsername: toUsername,
        status: DailyInvitationStatus.pending,
        timestamp: DateTime.now(),
      );

      await _firestore
          .collection('daily_invitations')
          .add(invitation.toJson());

      return {'success': true};
    } catch (e) {
      print('Error sending daily invitation: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get pending invitations for current user
  Stream<List<DailyInvitation>> getPendingInvitations() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value([]);

    return _firestore
        .collection('daily_invitations')
        .where('toUserId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => DailyInvitation.fromFirestore(doc))
        .toList());
  }

  // Get accepted invitations (for notifications)
  Stream<List<DailyInvitation>> getAcceptedInvitations() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value([]);

    return _firestore
        .collection('daily_invitations')
        .where('fromUserId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'accepted')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => DailyInvitation.fromFirestore(doc))
        .toList());
  }

  /// Accept a daily invitation.
  /// Copies the daily doc from the owner's subcollection into the
  /// accepter's subcollection, preserving creatorUid as the owner's UID.
  Future<Map<String, dynamic>> acceptDailyInvitation(
      String invitationId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      // 1. Mark invitation accepted
      final invitationRef = _firestore
          .collection('daily_invitations')
          .doc(invitationId);

      await invitationRef.update({'status': 'accepted'});

      // 2. Fetch the invitation to get dailyId + fromUserId (owner)
      final invitationDoc = await invitationRef.get();
      final data = invitationDoc.data() as Map<String, dynamic>?;
      if (data == null) return {'success': true};

      final dailyId = data['dailyId'] as String?;
      final ownerUid = data['fromUserId'] as String?;

      if (dailyId == null || ownerUid == null) return {'success': true};

      // 3. Fetch the daily from the owner's subcollection
      final ownerDailyDoc = await _firestore
          .collection('users')
          .doc(ownerUid)
          .collection('dailies')
          .doc(dailyId)
          .get();

      if (!ownerDailyDoc.exists) return {'success': true};

      final dailyData =
      ownerDailyDoc.data() as Map<String, dynamic>;

      // 4. Copy into accepter's subcollection.
      //    CRITICAL: force creatorUid to ownerUid so the member's
      //    copy always knows who the real creator is, regardless of
      //    what was previously stored on the doc.
      await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('dailies')
          .doc(dailyId)
          .set({
        ...dailyData,
        'ownerUid': ownerUid,
        'isMemberCopy': true,
        'creatorUid': ownerUid, // always the creator, never the member
      });

      print(
          'DailyInvitationService: Copied daily $dailyId to $currentUid');
      return {'success': true};
    } catch (e) {
      print('Error accepting invitation: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Reject daily invitation
  Future<Map<String, dynamic>> rejectDailyInvitation(
      String invitationId) async {
    try {
      await _firestore
          .collection('daily_invitations')
          .doc(invitationId)
          .update({'status': 'rejected'});
      return {'success': true};
    } catch (e) {
      print('Error rejecting invitation: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get daily invitation by ID
  Future<DailyInvitation?> getDailyInvitationById(
      String invitationId) async {
    try {
      final doc = await _firestore
          .collection('daily_invitations')
          .doc(invitationId)
          .get();
      if (!doc.exists) return null;
      return DailyInvitation.fromFirestore(doc);
    } catch (e) {
      print('Error getting invitation: $e');
      return null;
    }
  }
}