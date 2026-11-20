import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Weekly skips for Daily entry prompts.
///
/// How it works (unchanged): everyone gets 3 skips a week, plus 1 for every
/// 2 Dailies they're in, up to 6. A "week" is counted from the day you
/// first used Kaidose's prompts, so it resets on your own schedule.
///
/// Stored at users/{uid}/skip_data/current:
///   userStartDate      – midnight (your time) of the day your weeks start
///   lastResetDate      – midnight (your time) the current week started
///   skipsUsedThisWeek  – skips used since then
///
/// The app only reads this. Using a skip goes through the useDailySkip
/// Cloud Function, which starts a new week when it's due and only counts
/// the skip if one is left, all in one step. So the count can't be edited
/// from a phone, and two quick taps can't both get through on the last skip.
class SkipCount {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static const int _baseSkips = 3;
  static const int _maxSkips = 6;

  static String? get _currentUserId => _auth.currentUser?.uid;

  static DocumentReference<Map<String, dynamic>> _doc(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('skip_data')
      .doc('current');

  /// Total skips a week for someone in [numDailies] Dailies: 3, plus 1 per
  /// 2 Dailies, up to 6.
  static int calculateTotalSkips(int numDailies) {
    final total = _baseSkips + (numDailies ~/ 2);
    return total.clamp(_baseSkips, _maxSkips);
  }

  /// Skips left this week.
  static Future<int> getRemainingSkips(int numDailies) async {
    final total = calculateTotalSkips(numDailies);
    final used = await getSkipsUsed();
    return (total - used).clamp(0, total);
  }

  /// Uses one skip. True if it was used, false if none were left (or it
  /// couldn't reach the server; check [getRemainingSkips] to tell which).
  static Future<bool> useSkip(int numDailies) async {
    if (_currentUserId == null) return false;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('useDailySkip')
          .call(<String, dynamic>{
        'dailyCount': numDailies,
        'tzOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      });
      final data = result.data;
      return data is Map && data['ok'] == true;
    } catch (e) {
      print('SkipCount: useSkip error: $e');
      return false;
    }
  }

  /// Kept so existing callers (Dailies) still work. New weeks are now
  /// started by the server the next time a skip is used, and every read
  /// here already treats a finished week as reset, so there's nothing to
  /// write from the phone.
  static Future<void> checkAndResetIfNewWeek() async {}

  /// Skips used this week (0 if a new week has started since the last one).
  static Future<int> getSkipsUsed() async {
    final uid = _currentUserId;
    if (uid == null) return 0;
    try {
      final doc = await _doc(uid).get();
      final data = doc.data();
      if (data == null) return 0;
      final start = _date(data['userStartDate']);
      final lastReset = _date(data['lastResetDate']);
      final used = (data['skipsUsedThisWeek'] as num?)?.toInt() ?? 0;
      if (start == null) return 0;
      final weekStart = _weekStart(_today(), start);
      if (lastReset == null || weekStart.isAfter(lastReset)) return 0;
      return used;
    } catch (e) {
      print('SkipCount: getSkipsUsed error: $e');
      return 0;
    }
  }

  /// Days until skips reset (7 if you haven't started yet).
  static Future<int> getDaysUntilReset() async {
    final uid = _currentUserId;
    if (uid == null) return 0;
    try {
      final doc = await _doc(uid).get();
      final start = _date(doc.data()?['userStartDate']);
      if (start == null) return 7;
      final today = _today();
      final next = _weekStart(today, start).add(const Duration(days: 7));
      return _daysBetween(today, next).clamp(0, 7);
    } catch (e) {
      print('SkipCount: getDaysUntilReset error: $e');
      return 0;
    }
  }

  // ─── Dates (calendar days on this phone, so daylight saving can't make a
  // day count as 23 or 25 hours) ─────────────────────────────────────────────

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime? _date(dynamic v) {
    if (v is! Timestamp) return null;
    final d = v.toDate();
    return DateTime(d.year, d.month, d.day);
  }

  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;

  /// The first day of the week [day] falls in, counting 7-day weeks from
  /// [start].
  static DateTime _weekStart(DateTime day, DateTime start) {
    final days = _daysBetween(start, day);
    final week = days < 0 ? 0 : days ~/ 7;
    return DateTime(start.year, start.month, start.day + week * 7);
  }
}