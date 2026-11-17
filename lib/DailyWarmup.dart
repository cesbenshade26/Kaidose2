import 'DailyPostActivity.dart' show DailyPostVideoCache;
import 'MediaAspect.dart';
import 'MessageStorage.dart';
import 'SendDailyMessage.dart' show DailyMessage;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Gets a Daily ready before it's opened: its messages, and the newest
/// photos/videos (the ones you see first, at the bottom of the thread).
///
///  * A Daily card shows up in For You / My Dailies -> its newest photos
///    (and video still frames) start downloading (8 messages read).
///  * A finger touches the card -> its whole thread and its newest videos
///    start loading too, so they're there by the time the Daily opens.
class DailyWarmup {
  DailyWarmup._();

  static final Map<String, DateTime> _done = {};
  static const Duration _again = Duration(minutes: 3);
  static const int _photos = 4; // newest photos / still frames
  static const int _videos = 2; // newest videos, on touch only

  static Future<void> warm(String dailyId, {bool videos = false}) async {
    final key = '$dailyId|$videos';
    final last = _done[key];
    if (last != null && DateTime.now().difference(last) < _again) return;
    _done[key] = DateTime.now();

    // Touched: the whole thread starts loading (opening uses it).
    if (videos) MessageStorage.prefetch(dailyId);
    try {
      // Only the newest few messages: what's on screen when it opens. Cheap
      // enough to do for every card that shows up.
      final snap = await FirebaseFirestore.instance
          .collection('dailies')
          .doc(dailyId)
          .collection('daily_messages')
          .orderBy('timestamp', descending: true)
          .limit(8)
          .get();
      final messages = snap.docs
          .map((d) => DailyMessage.fromJson(d.data()))
          .toList()
          .reversed
          .toList();
      var photos = 0;
      var vids = 0;
      for (final m in messages.reversed) {
        for (final item in m.media.take(2)) {
          if (!item.path.startsWith('http')) continue;
          // (Videos without a still frame would need opening to measure.)
          if (!item.isVideo || item.thumb != null) {
            MediaAspect.of(item.path, isVideo: item.isVideo, thumb: item.thumb);
          }
          if (item.isVideo) {
            final thumb = item.thumb;
            if (thumb != null && photos < _photos) {
              precacheNetworkImage(thumb);
              photos++;
            }
            if (videos && vids < _videos) {
              DailyPostVideoCache.warm(item.path);
              vids++;
            }
          } else if (photos < _photos) {
            precacheNetworkImage(item.path);
            photos++;
          }
        }
        if (photos >= _photos && (!videos || vids >= _videos)) break;
      }
    } catch (_) {}
  }
}