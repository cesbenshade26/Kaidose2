import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';

/// A scored Daily ready for display in a feed.
class ScoredDaily {
  final DailyData daily;
  final double score;        // 0.0 – 1.0 normalized total score
  final double interestScore;
  final double activityScore;
  final double socialScore;
  final double recencyScore;

  const ScoredDaily({
    required this.daily,
    required this.score,
    required this.interestScore,
    required this.activityScore,
    required this.socialScore,
    required this.recencyScore,
  });
}

class FeedService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  // ─── Weights ────────────────────────────────────────────────────────────────
  static const double _wInterest  = 0.40;
  static const double _wActivity  = 0.30;
  static const double _wSocial    = 0.20;
  static const double _wRecency   = 0.10;

  // ─── Main entry point ───────────────────────────────────────────────────────

  /// Fetch all public Dailies the user doesn't already own/belong to,
  /// score each one, and return them sorted best-first.
  static Future<List<ScoredDaily>> getRankedFeed() async {
    final uid = _uid;
    if (uid == null) return [];

    // Run all data fetches in parallel for speed
    final results = await Future.wait([
      _getUserInterests(uid),       // List<String>
      _getUserActivityMap(uid),     // Map<String, int>  tag → interaction count
      _getFriendUids(uid),          // List<String>
      _getPublicDailies(uid),       // List<DailyData>
    ]);

    final userInterests  = results[0] as List<String>;
    final activityMap    = results[1] as Map<String, int>;
    final friendUids     = results[2] as List<String>;
    final candidates     = results[3] as List<DailyData>;

    if (candidates.isEmpty) return [];

    // Build a set of daily IDs the user's friends are active in
    final friendActiveDailyIds =
    await _getFriendActiveDailyIds(friendUids);

    // Score every candidate
    final scored = candidates.map((daily) {
      final interest = _scoreInterest(daily, userInterests);
      final activity = _scoreActivity(daily, activityMap);
      final social   = _scoreSocial(daily, friendActiveDailyIds);
      final recency  = _scoreRecency(daily);

      final total = interest  * _wInterest
          + activity  * _wActivity
          + social    * _wSocial
          + recency   * _wRecency;

      return ScoredDaily(
        daily:         daily,
        score:         total,
        interestScore: interest,
        activityScore: activity,
        socialScore:   social,
        recencyScore:  recency,
      );
    }).toList();

    // Sort descending
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  // ─── Data fetchers ───────────────────────────────────────────────────────────

  /// User's onboarding interests e.g. ['Sports', 'Music']
  static Future<List<String>> _getUserInterests(String uid) async {
    try {
      final doc =
      await _firestore.collection('users').doc(uid).get();
      final raw = doc.data()?['interests'];
      if (raw is List) return List<String>.from(raw);
    } catch (e) {
      print('FeedService: error fetching interests: $e');
    }
    return [];
  }

  /// Map of tag → how many times the user has interacted with
  /// Dailies carrying that tag.  Stored at:
  ///   users/{uid}/feed_activity/{tag}  →  { count: N }
  static Future<Map<String, int>> _getUserActivityMap(String uid) async {
    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('feed_activity')
          .get();
      return {
        for (final doc in snap.docs)
          doc.id: (doc.data()['count'] as int? ?? 0)
      };
    } catch (e) {
      print('FeedService: error fetching activity map: $e');
    }
    return {};
  }

  /// UIDs of accepted friends
  static Future<List<String>> _getFriendUids(String uid) async {
    try {
      final snap = await _firestore
          .collection('friend_requests')
          .where('status', isEqualTo: 'accepted')
          .get();

      return snap.docs
          .map((d) {
        final from = d.data()['fromUserId'] as String?;
        final to   = d.data()['toUserId']   as String?;
        if (from == uid) return to;
        if (to   == uid) return from;
        return null;
      })
          .whereType<String>()
          .toList();
    } catch (e) {
      print('FeedService: error fetching friends: $e');
    }
    return [];
  }

  /// All discoverable Dailies (public AND private) that the current user
  /// doesn't already own. Private ones still show up so people can see
  /// them and send a join request — they just can't auto-join.
  /// Reads from the `public_dailies` mirror collection (despite the name,
  /// it holds every Daily published via NewDailyFinalScreen, public or
  /// private — see FeedService.publishToPublicFeed).
  static Future<List<DailyData>> _getPublicDailies(String uid) async {
    try {
      final snap = await _firestore
          .collection('public_dailies')
          .limit(200)
          .get();

      print('FeedService: public_dailies query returned ${snap.docs.length} docs');

      final dailies = snap.docs
          .map((d) => DailyData.fromFirestore(d))
          .where((daily) => daily.creatorUid != uid)
          .toList();

      return dailies;
    } catch (e) {
      print('FeedService: public_dailies query error: $e');
    }
    return [];
  }

  /// Set of daily IDs that any of the user's friends have interacted with.
  static Future<Set<String>> _getFriendActiveDailyIds(
      List<String> friendUids) async {
    if (friendUids.isEmpty) return {};
    final Set<String> ids = {};
    try {
      // Firestore `in` queries cap at 30 items; chunk if needed
      final chunks = _chunk(friendUids, 30);
      for (final chunk in chunks) {
        final snap = await _firestore
            .collection('daily_interactions')
            .where('userId', whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final dailyId = doc.data()['dailyId'] as String?;
          if (dailyId != null) ids.add(dailyId);
        }
      }
    } catch (e) {
      print('FeedService: error fetching friend activity: $e');
    }
    return ids;
  }

  // ─── Scorers (each returns 0.0 – 1.0) ────────────────────────────────────

  /// How well the Daily's tags overlap with the user's interests.
  static double _scoreInterest(
      DailyData daily, List<String> userInterests) {
    if (userInterests.isEmpty || daily.keywords.isEmpty) return 0.0;
    final matches = daily.keywords
        .where((tag) => userInterests.contains(tag))
        .length;
    // Normalize: full score if ALL daily tags match an interest
    return (matches / daily.keywords.length).clamp(0.0, 1.0);
  }

  /// How active the user has been in Dailies sharing these tags.
  static double _scoreActivity(
      DailyData daily, Map<String, int> activityMap) {
    if (activityMap.isEmpty || daily.keywords.isEmpty) return 0.0;
    int total = 0;
    int maxPossible = 0;
    // Cap individual tag counts at 50 to avoid one tag dominating
    const int cap = 50;
    for (final tag in daily.keywords) {
      final count = (activityMap[tag] ?? 0).clamp(0, cap);
      total += count;
      maxPossible += cap;
    }
    if (maxPossible == 0) return 0.0;
    return (total / maxPossible).clamp(0.0, 1.0);
  }

  /// Whether any friends are active in this Daily.
  static double _scoreSocial(
      DailyData daily, Set<String> friendActiveDailyIds) {
    return friendActiveDailyIds.contains(daily.id) ? 1.0 : 0.0;
  }

  /// How recently the Daily was created.
  /// Full score = created today. Zero score = created 30+ days ago.
  static double _scoreRecency(DailyData daily) {
    final age = DateTime.now().difference(daily.createdAt).inDays;
    if (age <= 0)  return 1.0;
    if (age >= 30) return 0.0;
    return 1.0 - (age / 30.0);
  }

  // ─── Activity tracking ───────────────────────────────────────────────────

  /// Call this whenever the current user opens or interacts with a Daily.
  /// Increments the per-tag activity counter used by _scoreActivity.
  static Future<void> recordInteraction(DailyData daily) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final batch = _firestore.batch();

      // Increment each tag's counter
      for (final tag in daily.keywords) {
        final ref = _firestore
            .collection('users')
            .doc(uid)
            .collection('feed_activity')
            .doc(tag);
        batch.set(ref, {'count': FieldValue.increment(1)},
            SetOptions(merge: true));
      }

      // Record in global interaction log for social scoring
      final interactionRef =
      _firestore.collection('daily_interactions').doc();
      batch.set(interactionRef, {
        'userId':    uid,
        'dailyId':   daily.id,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (e) {
      print('FeedService: recordInteraction error: $e');
    }
  }

  /// Mirror a newly published Daily into `public_dailies` (the
  /// discover-feed collection — holds both public and private Dailies
  /// so private ones can still be found and requested, just not
  /// auto-joined). Call this from NewDailyFinalScreen right after
  /// DailyList.addDaily().
  static Future<void> publishToPublicFeed(DailyData daily) async {
    try {
      await _firestore
          .collection('public_dailies')
          .doc(daily.id)
          .set(daily.toFirestoreJson());
      print('FeedService: mirrored daily ${daily.id} to public_dailies (privacy=${daily.privacy})');
    } catch (e) {
      print('FeedService: publishToPublicFeed error: $e');
    }
  }

  /// Remove a Daily from the public feed mirror (on delete or privacy change).
  static Future<void> removeFromPublicFeed(String dailyId) async {
    try {
      await _firestore
          .collection('public_dailies')
          .doc(dailyId)
          .delete();
    } catch (e) {
      print('FeedService: removeFromPublicFeed error: $e');
    }
  }

  // ─── Utility ────────────────────────────────────────────────────────────────

  static List<List<T>> _chunk<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(
          i, i + size > list.length ? list.length : i + size));
    }
    return chunks;
  }
}