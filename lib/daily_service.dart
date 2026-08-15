import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';

class DailyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

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
      final pinned = dailies.where((d) => d.isPinned).toList();
      final unpinned = dailies.where((d) => !d.isPinned).toList();
      return [...pinned, ...unpinned];
    });
  }

  Future<Map<String, dynamic>> addDaily(DailyData daily) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      // Always stamp creatorUid when adding
      final dataWithCreator = {
        ...daily.toFirestoreJson(),
        'creatorUid': currentUid,
      };

      await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('dailies')
          .doc(daily.id)
          .set(dataWithCreator);

      return {'success': true};
    } catch (e) {
      print('Error adding daily: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> updateDaily(DailyData daily) async {
    try {
      final currentUid = currentUserId;
      if (currentUid == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      final updatedData = daily.toFirestoreJson();

      // Update owner's copy
      await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('dailies')
          .doc(daily.id)
          .update(updatedData);

      // Find all accepted members and propagate
      final invitations = await _firestore
          .collection('daily_invitations')
          .where('dailyId', isEqualTo: daily.id)
          .where('status', isEqualTo: 'accepted')
          .get();

      if (invitations.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final invDoc in invitations.docs) {
          final memberUid = invDoc.data()['toUserId'] as String?;
          if (memberUid == null || memberUid == currentUid) continue;

          final memberDocRef = _firestore
              .collection('users')
              .doc(memberUid)
              .collection('dailies')
              .doc(daily.id);

          // Preserve creatorUid when propagating so member copy
          // always knows who the creator is
          batch.update(memberDocRef, {
            ...updatedData,
            'creatorUid': currentUid,
          });
        }
        await batch.commit();
        print(
            'DailyService: Propagated update to ${invitations.docs.length} members');
      }

      return {'success': true};
    } catch (e) {
      print('Error updating daily: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

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

  /// Owner-initiated copy: push one of MY dailies into someone else's
  /// subcollection (used when accepting a private-Daily join request).
  /// Always preserves creatorUid as the actual creator.
  static Future<void> copyDailyToUser({
    required DailyData daily,
    required String targetUid,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final data = {
        ...daily.toFirestoreJson(),
        'creatorUid': daily.creatorUid,
      };

      await firestore
          .collection('users')
          .doc(targetUid)
          .collection('dailies')
          .doc(daily.id)
          .set(data);

      print('DailyService: Copied daily ${daily.id} to $targetUid');
    } catch (e) {
      print('Error copying daily to user $targetUid: $e');
    }
  }

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
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }
}