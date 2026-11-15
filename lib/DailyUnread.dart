import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'SendDailyMessage.dart';

/// Unread message counts for the Dailies a user is in.
///
/// Each user keeps one tiny marker doc per Daily:
///   users/{uid}/daily_reads/{dailyId}  { lastSeen: <timestamp string> }
///
/// [lastSeen] is the `timestamp` string of the newest message they had
/// loaded the last time they were inside the Daily. Messages store their
/// timestamp as an ISO string, so using the newest *message's own string*
/// (instead of this device's clock) keeps the comparison apples-to-apples.
///
/// Unread = messages from OTHER people with a timestamp after lastSeen.
/// Your own messages never count.
class DailyUnreadService {
  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  /// The most we ever count; the badge shows "99+" past that.
  static const int _cap = 100;

  // Last marker this session wrote per Daily, so reopening a Daily with
  // nothing new doesn't write the same value again.
  static final Map<String, String> _lastWritten = {};

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static DocumentReference<Map<String, dynamic>> _readRef(
      String uid, String dailyId) =>
      _fs.collection('users').doc(uid).collection('daily_reads').doc(dailyId);

  static CollectionReference<Map<String, dynamic>> _messages(String dailyId) =>
      _fs.collection('dailies').doc(dailyId).collection('daily_messages');

  /// Live unread count for one Daily. Listens to the marker doc, and to
  /// messages newer than it, so the number updates the moment someone
  /// posts or the user opens the Daily.
  ///
  /// The first time a Daily is ever seen (no marker yet), everything
  /// already in it counts as read, so existing Dailies don't all light up
  /// with huge numbers the day this ships.
  static Stream<int> watchUnread(String dailyId) {
    final uid = _uid;
    if (uid == null) return Stream.value(0);

    late StreamController<int> controller;
    StreamSubscription? markerSub;
    StreamSubscription? messagesSub;
    String? currentMarker;
    bool seeding = false;

    void listenToMessages(String marker) {
      messagesSub?.cancel();
      messagesSub = _messages(dailyId)
          .where('timestamp', isGreaterThan: marker)
          .orderBy('timestamp')
          .limit(_cap)
          .snapshots()
          .listen((snap) {
        final count =
            snap.docs.where((d) => d.data()['user_id'] != uid).length;
        if (!controller.isClosed) controller.add(count);
      }, onError: (e) {
        print('DailyUnreadService: messages listen error for $dailyId: $e');
      });
    }

    controller = StreamController<int>(
      onListen: () {
        markerSub = _readRef(uid, dailyId).snapshots().listen((snap) async {
          if (!snap.exists) {
            if (seeding) return;
            seeding = true;
            // Writing the seed fires this listener again with the doc.
            await _seed(uid, dailyId);
            return;
          }
          final marker = (snap.data()?['lastSeen'] as String?) ?? '';
          if (marker == currentMarker) return;
          currentMarker = marker;
          listenToMessages(marker);
        }, onError: (e) {
          print('DailyUnreadService: marker listen error for $dailyId: $e');
        });
      },
      onCancel: () async {
        await markerSub?.cancel();
        await messagesSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// First sight of a Daily: mark everything currently in it as seen.
  static Future<void> _seed(String uid, String dailyId) async {
    try {
      final newest = await _messages(dailyId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      final marker = newest.docs.isEmpty
          ? ''
          : (newest.docs.first.data()['timestamp'] as String? ?? '');
      await _readRef(uid, dailyId).set({
        'lastSeen': marker,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _lastWritten[dailyId] = marker;
    } catch (e) {
      print('DailyUnreadService: seed error for $dailyId: $e');
    }
  }

  /// Call with the messages the user just loaded inside a Daily: moves
  /// their marker up to the newest one, which clears the badge.
  static Future<void> markRead(
      String dailyId, List<DailyMessage> messages) async {
    final uid = _uid;
    if (uid == null || messages.isEmpty) return;

    // Same string the message was saved with (see DailyMessage.toJson).
    var newest = '';
    for (final m in messages) {
      final s = m.timestamp.toIso8601String();
      if (s.compareTo(newest) > 0) newest = s;
    }
    if (newest.isEmpty || _lastWritten[dailyId] == newest) return;

    try {
      await _readRef(uid, dailyId).set({
        'lastSeen': newest,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _lastWritten[dailyId] = newest;
    } catch (e) {
      print('DailyUnreadService: markRead error for $dailyId: $e');
    }
  }
}