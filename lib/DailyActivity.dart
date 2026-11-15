import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Live "what's new" numbers for the Daily cards in My Dailies.
///
///  - [watchNewCount]: posts by other people in a Daily since I last opened
///    it (0 until the first time I open it; capped at 12).
///  - [recordView] / [watchViewsToday]: how many different people have opened
///    a Daily so far today (the creator's own opens aren't counted).
class DailyActivityService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static String get _today => DateTime.now().toIso8601String().split('T')[0];

  /// Posts from others since my last open (the `timestamp` that
  /// DailyService.markAsViewedToday writes on every open).
  static Stream<int> watchNewCount(String dailyId) {
    final uid = _uid;
    if (uid == null) return Stream.value(0);

    late StreamController<int> out;
    StreamSubscription? viewSub;
    StreamSubscription? msgSub;

    out = StreamController<int>(
      onListen: () {
        viewSub = _db
            .collection('users')
            .doc(uid)
            .collection('daily_views')
            .doc(dailyId)
            .snapshots()
            .listen((doc) {
          msgSub?.cancel();
          final ts = doc.data()?['timestamp'];
          if (ts is! Timestamp) {
            // Never opened (or the stamp is still being written).
            if (!out.isClosed) out.add(0);
            return;
          }
          msgSub = _db
              .collection('dailies')
              .doc(dailyId)
              .collection('daily_messages')
              .where('timestamp',
              isGreaterThan: ts.toDate().toIso8601String())
              .orderBy('timestamp')
              .limit(12)
              .snapshots()
              .listen((snap) {
            final n =
                snap.docs.where((d) => d.data()['user_id'] != uid).length;
            if (!out.isClosed) out.add(n);
          }, onError: (_) {
            if (!out.isClosed) out.add(0);
          });
        }, onError: (_) {
          if (!out.isClosed) out.add(0);
        });
      },
      onCancel: () {
        viewSub?.cancel();
        msgSub?.cancel();
      },
    );
    return out.stream;
  }

  /// One doc per person per day, so repeat opens don't inflate the count.
  static Future<void> recordView(String dailyId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db
          .collection('dailies')
          .doc(dailyId)
          .collection('daily_viewers')
          .doc('${_today}_$uid')
          .set({
        'uid': uid,
        'date': _today,
        'at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('DailyActivityService: recordView error: $e');
    }
  }

  /// Different people who opened this Daily today (not counting [excludeUid]).
  static Stream<int> watchViewsToday(String dailyId, {String? excludeUid}) {
    if (_uid == null) return Stream.value(0);
    return _db
        .collection('dailies')
        .doc(dailyId)
        .collection('daily_viewers')
        .where('date', isEqualTo: _today)
        .snapshots()
        .handleError((e) {
      print('DailyActivityService: views stream error: $e');
    }).map((s) => s.docs.where((d) => d.data()['uid'] != excludeUid).length);
  }
}