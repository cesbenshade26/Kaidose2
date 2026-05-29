import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SkipCount {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static const int _baseSkips = 3;
  static const int _maxSkips = 6;

  static String? get _currentUserId => _auth.currentUser?.uid;

  // Calculate total available skips based on number of dailies
  static int calculateTotalSkips(int numDailies) {
    int baseSkips = _baseSkips;
    int bonusSkips = (numDailies ~/ 2); // 1 bonus per 2 dailies
    int totalSkips = baseSkips + bonusSkips;
    return totalSkips.clamp(_baseSkips, _maxSkips); // Min 3, max 6
  }

  // Get remaining skips for the week
  static Future<int> getRemainingSkips(int numDailies) async {
    int totalSkips = calculateTotalSkips(numDailies);
    int used = await getSkipsUsed();
    int remaining = totalSkips - used;
    return remaining.clamp(0, totalSkips);
  }

  // Use a skip
  static Future<bool> useSkip(int numDailies) async {
    try {
      final userId = _currentUserId;
      if (userId == null) return false;

      await checkAndResetIfNewWeek();

      int remaining = await getRemainingSkips(numDailies);

      if (remaining <= 0) {
        return false; // No skips available
      }

      // Increment skips used
      final docRef = _firestore.collection('users').doc(userId).collection('skip_data').doc('current');

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        int currentUsed = snapshot.data()?['skipsUsedThisWeek'] ?? 0;
        transaction.set(docRef, {
          'skipsUsedThisWeek': currentUsed + 1,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      return true;
    } catch (e) {
      print('Error using skip: $e');
      return false;
    }
  }

  // Check if a new week has started and reset if needed
  static Future<void> checkAndResetIfNewWeek() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return;

      final docRef = _firestore.collection('users').doc(userId).collection('skip_data').doc('current');
      final doc = await docRef.get();

      final now = DateTime.now();
      DateTime? userStartDate;
      DateTime? lastResetDate;

      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          if (data['userStartDate'] != null) {
            userStartDate = (data['userStartDate'] as Timestamp).toDate();
          }
          if (data['lastResetDate'] != null) {
            lastResetDate = (data['lastResetDate'] as Timestamp).toDate();
          }
        }
      }

      // Initialize user start date if not set
      if (userStartDate == null) {
        userStartDate = DateTime(now.year, now.month, now.day);
        await docRef.set({
          'userStartDate': Timestamp.fromDate(userStartDate),
          'lastResetDate': Timestamp.fromDate(userStartDate),
          'skipsUsedThisWeek': 0,
        });
        print('Initialized skip system for user');
        return;
      }

      final currentWeekStart = _getWeekStartDate(now, userStartDate);

      // Check if we need to reset
      if (lastResetDate == null || currentWeekStart.isAfter(lastResetDate)) {
        // New week! Reset skips
        await docRef.update({
          'skipsUsedThisWeek': 0,
          'lastResetDate': Timestamp.fromDate(currentWeekStart),
        });
        print('New week detected. Skips reset to 0 used. Next reset: ${_getNextResetDate(userStartDate, now)}');
      }
    } catch (e) {
      print('Error checking/resetting skip week: $e');
    }
  }

  // Get the week start date based on user's join date
  static DateTime _getWeekStartDate(DateTime now, DateTime userStart) {
    // Calculate days since user started
    int daysSinceStart = now.difference(userStart).inDays;

    // Calculate which week we're in (0-indexed)
    int weekNumber = daysSinceStart ~/ 7;

    // Calculate the start of the current week
    DateTime weekStart = userStart.add(Duration(days: weekNumber * 7));

    return DateTime(weekStart.year, weekStart.month, weekStart.day);
  }

  // Get next reset date (for display)
  static DateTime _getNextResetDate(DateTime userStart, DateTime now) {
    final currentWeekStart = _getWeekStartDate(now, userStart);
    return currentWeekStart.add(const Duration(days: 7));
  }

  // Get current skips used (for debugging/display)
  static Future<int> getSkipsUsed() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return 0;

      final docRef = _firestore.collection('users').doc(userId).collection('skip_data').doc('current');
      final doc = await docRef.get();

      if (!doc.exists) return 0;

      return doc.data()?['skipsUsedThisWeek'] ?? 0;
    } catch (e) {
      print('Error getting skips used: $e');
      return 0;
    }
  }

  // Reset skips (for testing purposes)
  static Future<void> resetSkips() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return;

      final docRef = _firestore.collection('users').doc(userId).collection('skip_data').doc('current');
      await docRef.update({'skipsUsedThisWeek': 0});
    } catch (e) {
      print('Error resetting skips: $e');
    }
  }

  // Get days until next reset (for UI display)
  static Future<int> getDaysUntilReset() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return 0;

      final docRef = _firestore.collection('users').doc(userId).collection('skip_data').doc('current');
      final doc = await docRef.get();

      if (!doc.exists) return 0;

      final data = doc.data();
      if (data == null || data['userStartDate'] == null) return 0;

      final userStartDate = (data['userStartDate'] as Timestamp).toDate();
      final now = DateTime.now();
      final nextReset = _getNextResetDate(userStartDate, now);
      final diff = nextReset.difference(now).inDays;
      return diff.clamp(0, 7);
    } catch (e) {
      print('Error getting days until reset: $e');
      return 0;
    }
  }
}