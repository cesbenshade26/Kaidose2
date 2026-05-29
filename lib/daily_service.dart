import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';

class DailyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // Get user's dailies as a stream
  Stream<List<DailyData>> getUserDailies() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(currentUid)
        .collection('dailies')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final dailies = snapshot.docs
          .map((doc) => DailyData.fromFirestore(doc))
          .toList();

      // Sort: pinned first, then by creation date
      final pinned = dailies.where((d) => d.isPinned).toList();
      final unpinned = dailies.where((d) => !d.isPinned).toList();

      return [...pinned, ...unpinned];
    });
  }

  // Add a new daily
  Future<Map<String, dynamic>> addDaily(DailyData daily) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('dailies')
          .doc(daily.id)
          .set(daily.toFirestoreJson());

      return {'success': true};
    } catch (e) {
      print('Error adding daily: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Update an existing daily
  Future<Map<String, dynamic>> updateDaily(DailyData daily) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('dailies')
          .doc(daily.id)
          .update(daily.toFirestoreJson());

      return {'success': true};
    } catch (e) {
      print('Error updating daily: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Toggle pin status
  Future<Map<String, dynamic>> togglePin(String dailyId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final docRef = _firestore
          .collection('users')
          .doc(currentUid)
          .collection('dailies')
          .doc(dailyId);

      final doc = await docRef.get();
      if (!doc.exists) {
        return {'success': false, 'error': 'Daily not found'};
      }

      final currentPinned = doc.data()?['isPinned'] ?? false;
      await docRef.update({'isPinned': !currentPinned});

      return {'success': true};
    } catch (e) {
      print('Error toggling pin: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Delete a daily
  Future<Map<String, dynamic>> deleteDaily(String dailyId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('dailies')
          .doc(dailyId)
          .delete();

      return {'success': true};
    } catch (e) {
      print('Error deleting daily: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get a specific daily by ID from current user
  Future<DailyData?> getDailyById(String dailyId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return null;

      final doc = await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('dailies')
          .doc(dailyId)
          .get();

      if (!doc.exists) return null;
      return DailyData.fromFirestore(doc);
    } catch (e) {
      print('Error getting daily: $e');
      return null;
    }
  }

  // NEW: Get a specific daily from another user's account
  Future<DailyData?> getDailyFromUser({
    required String userId,
    required String dailyId,
  }) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('dailies')
          .doc(dailyId)
          .get();

      if (!doc.exists) return null;
      return DailyData.fromFirestore(doc);
    } catch (e) {
      print('Error getting daily from user $userId: $e');
      return null;
    }
  }

  // Mark daily as viewed today
  Future<void> markAsViewedToday(String dailyId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return;

      final today = DateTime.now().toIso8601String().split('T')[0];

      await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('daily_views')
          .doc(dailyId)
          .set({
        'lastViewedDate': today,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error marking as viewed: $e');
    }
  }

  // Unmark daily as viewed
  Future<void> unmarkAsViewedToday(String dailyId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return;

      await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('daily_views')
          .doc(dailyId)
          .delete();
    } catch (e) {
      print('Error unmarking as viewed: $e');
    }
  }

  // Check if daily has been viewed today
  Future<bool> hasBeenViewedToday(String dailyId) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) return false;

      final today = DateTime.now().toIso8601String().split('T')[0];

      final doc = await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('daily_views')
          .doc(dailyId)
          .get();

      if (!doc.exists) return false;

      final lastViewedDate = doc.data()?['lastViewedDate'] as String?;
      return lastViewedDate == today;
    } catch (e) {
      print('Error checking viewed status: $e');
      return false;
    }
  }

  // Get all viewed dailies for today
  Stream<Set<String>> getViewedDailiesToday() {
    final currentUid = currentUserId;
    if (currentUid == null) return Stream.value({});

    final today = DateTime.now().toIso8601String().split('T')[0];

    return _firestore
        .collection('users')
        .doc(currentUid)
        .collection('daily_views')
        .where('lastViewedDate', isEqualTo: today)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => doc.id).toSet();
    });
  }
}