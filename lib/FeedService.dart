import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'clip_service.dart';

/// Things a user can do that tell the feed what they like. Each has a
/// weight (see FeedService._eventWeights); positive ones pull similar
/// Dailies up, negative ones push them down.
enum FeedEvent { open, add, post, react, comment, interested, notInterested, leave }

/// Things a user can do with a clip. Clips have no tags, so these teach the
/// feed which CREATORS the user likes (users/{uid}/creator_affinity).
enum ClipEvent { like, comment, share, watched, skipped }

/// A scored Daily ready for display in a feed.
class ScoredDaily {
  final DailyData daily;
  final double score;         // 0.0 – 1.0 normalized total score
  final double interestScore; // taste profile + onboarding interests
  final double activityScore; // how alive the Daily itself is
  final double socialScore;   // friends who are in it / opened it
  final double recencyScore;  // how new the Daily is
  final bool isExploration;   // placed in an exploration slot
  final List<String> terms;   // free-text keywords (Cloud Function), for search

  const ScoredDaily({
    required this.daily,
    required this.score,
    required this.interestScore,
    required this.activityScore,
    required this.socialScore,
    required this.recencyScore,
    this.isExploration = false,
    this.terms = const [],
  });

  ScoredDaily asExploration() => ScoredDaily(
    daily: daily,
    score: score,
    interestScore: interestScore,
    activityScore: activityScore,
    socialScore: socialScore,
    recencyScore: recencyScore,
    isExploration: true,
    terms: terms,
  );
}

/// Optional per-Daily stats kept on the public_dailies doc (maintained by
/// the Cloud Functions in functions/index.js). All fields may be missing on
/// older Dailies — everything here has a safe default.
class _DailyStats {
  final int memberCount; // accepted members, not counting the owner
  final DateTime? lastPostAt;
  final int postCount;
  final int impressions;

  const _DailyStats({
    this.memberCount = 0,
    this.lastPostAt,
    this.postCount = 0,
    this.impressions = 0,
  });

  factory _DailyStats.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const _DailyStats();
    final ts = m['lastPostAt'];
    return _DailyStats(
      memberCount: (m['memberCount'] as num?)?.toInt() ?? 0,
      lastPostAt: ts is Timestamp ? ts.toDate() : null,
      postCount: (m['postCount'] as num?)?.toInt() ?? 0,
      impressions: (m['impressions'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isUnknown => memberCount == 0 && lastPostAt == null && postCount == 0;
}

class _ClipRow {
  final ClipData clip;
  final double score;
  final double interest;
  final double aff;
  _ClipRow(this.clip, this.score, this.interest, this.aff);
}

class _Candidate {
  final DailyData daily;
  final _DailyStats stats;
  final List<String> terms; // free-text keywords from the Cloud Function
  _Candidate(this.daily, this.stats, this.terms);
}

/// The feed engine behind For You (and, later, search ranking).
///
/// How it works:
///  1. TASTE PROFILE — every weighted event (open, add, post, ...) updates a
///     per-tag score at users/{uid}/taste/{tag}. Scores decay with a
///     [_halfLifeDays]-day half-life, so the feed follows what the user
///     likes NOW. Onboarding interests seed it until behavior takes over.
///  2. CANDIDATES — pulled from several sources (tags the user likes, newest,
///     most popular, Dailies their friends are in), not one random slice.
///  3. SCORING — interest, Daily quality (members + recent posts), friends,
///     and recency, as a transparent weighted sum.
///  4. RE-RANK — a diversity pass (no run of the same tag) and an
///     exploration slot every 5th position so the feed doesn't collapse into
///     a bubble and new Dailies get seen.
class FeedService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  // ─── Weights (sum to 1.0) ───────────────────────────────────────────────────
  static const double _wInterest = 0.35;
  static const double _wQuality  = 0.25;
  static const double _wSocial   = 0.25;
  static const double _wRecency  = 0.15;

  // ─── Tuning ─────────────────────────────────────────────────────────────────
  static const double _halfLifeDays = 21;     // taste decay
  static const double _tasteCap = 8;          // taste score that counts as "max love"
  static const double _onboardingSeed = 0.4;  // affinity for a declared interest
  static const int _candidateLimit = 60;      // per source
  static const int _explorationEvery = 5;     // every Nth slot explores
  static const double _diversityPenalty = 0.06;

  static const Map<FeedEvent, double> _eventWeights = {
    FeedEvent.open: 1,
    FeedEvent.add: 5,
    FeedEvent.post: 3,
    FeedEvent.react: 2,
    FeedEvent.comment: 3,
    FeedEvent.interested: 3,
    FeedEvent.notInterested: -6,
    FeedEvent.leave: -4,
  };

  // ─── Keyword terms ──────────────────────────────────────────────────────────
  // Besides the preset tags, each Daily has free-text `terms` (e.g. "batman",
  // "marvel") extracted by a Cloud Function from its title, description and
  // creator keywords. They live in the same taste profile as tags, prefixed
  // with "t:" so "music" the term never collides with "Music" the tag.

  static const String _termPrefix = 't:';
  static const double _termWeightFactor = 0.8; // terms are noisier than tags
  static const int _maxTermsPerEvent = 8;
  static const int _maxTermsPerQuery = 10;

  static List<String> _readTerms(Map<String, dynamic>? data) {
    final raw = data?['terms'];
    return raw is List ? raw.whereType<String>().toList() : <String>[];
  }

  static String _docKey(String key) => key.replaceAll('/', '\u2215');

  // ─── Main entry point ───────────────────────────────────────────────────────

  /// Candidates from several sources, scored and re-ranked, best-first.
  /// Includes public AND private Dailies (private ones can be found and
  /// requested, never auto-joined) — callers filter by privacy.
  static Future<List<ScoredDaily>> getRankedFeed() async {
    final uid = _uid;
    if (uid == null) return [];

    final results = await Future.wait([
      _getUserInterests(uid),   // List<String>
      _getTaste(uid),           // Map<String, double>  tag → decayed score
      _getFriendUids(uid),      // List<String>
      _getHiddenIds(uid),       // Set<String>
    ]);

    final interests = results[0] as List<String>;
    final taste     = results[1] as Map<String, double>;
    final friends   = results[2] as List<String>;
    final hidden    = results[3] as Set<String>;

    // dailyId → number of friends who are members / have opened it
    final friendCounts = await _getFriendDailyCounts(friends);

    final candidates = await _getCandidates(
      uid: uid,
      interests: interests,
      taste: taste,
      friendDailyIds: friendCounts.keys.toList(),
      hidden: hidden,
    );
    if (candidates.isEmpty) return [];

    final scored = candidates.values.map((c) {
      final daily = c.daily;
      final interest = _scoreInterest(daily, c.terms, interests, taste);
      final quality  = _scoreQuality(c.stats);
      final social   = _scoreSocial(daily, friendCounts);
      final recency  = _scoreRecency(daily);

      var total = interest * _wInterest +
          quality * _wQuality +
          social * _wSocial +
          recency * _wRecency;

      // Tags the user has pushed away drag the whole score down.
      if (_hasStrongNegative(daily, c.terms, taste)) total *= 0.5;

      return ScoredDaily(
        daily: daily,
        score: total.clamp(0.0, 1.0),
        interestScore: interest,
        activityScore: quality,
        socialScore: social,
        recencyScore: recency,
        terms: c.terms,
      );
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return _rerank(scored);
  }

  // ─── Public helpers for Search ──────────────────────────────────────────────

  /// UIDs of the current user's accepted friends.
  static Future<List<String>> getFriendUids() async {
    final uid = _uid;
    if (uid == null) return [];
    return _getFriendUids(uid);
  }

  /// Topics the user currently likes, strongest first: learned tags/terms,
  /// then declared onboarding interests. Used for Search suggestions.
  static Future<List<String>> getTopTopics({int limit = 8}) async {
    final uid = _uid;
    if (uid == null) return [];
    final results = await Future.wait([_getTaste(uid), _getUserInterests(uid)]);
    final taste = results[0] as Map<String, double>;
    final interests = results[1] as List<String>;

    final ranked = taste.entries.where((e) => e.value > 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final seen = <String>{};
    final out = <String>[];
    void add(String t) {
      if (seen.add(t.toLowerCase()) && out.length < limit) out.add(t);
    }

    for (final e in ranked) {
      add(e.key.startsWith(_termPrefix)
          ? e.key.substring(_termPrefix.length)
          : e.key);
    }
    for (final i in interests) {
      add(i);
    }
    return out;
  }

  /// Turn typed text into the same normalized terms the Cloud Function
  /// stores (lowercase, no stop-words, light plural stripping), so a search
  /// for "Superheroes" matches a Daily with the term "superhero".
  static List<String> queryTerms(String text) {
    const stop = {
      'the', 'and', 'for', 'with', 'from', 'that', 'this', 'are', 'you',
      'your', 'our', 'daily', 'dailies'
    };
    final out = <String>[];
    for (var w in text.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
      if (w.length < 2 || stop.contains(w)) continue;
      if (w.length > 4 && w.endsWith('ies')) {
        w = w.substring(0, w.length - 1);
      } else if (w.length > 4 &&
          RegExp(r'(ch|sh|x|ss|o)es$').hasMatch(w)) {
        w = w.substring(0, w.length - 2);
      } else if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
        w = w.substring(0, w.length - 1);
      }
      if (!out.contains(w)) out.add(w);
    }
    return out;
  }

  // ─── Candidate generation ───────────────────────────────────────────────────

  static Future<Map<String, _Candidate>> _getCandidates({
    required String uid,
    required List<String> interests,
    required Map<String, double> taste,
    required List<String> friendDailyIds,
    required Set<String> hidden,
  }) async {
    final col = _firestore.collection('public_dailies');

    // Tags to query for: strongest learned tastes first, then declared ones.
    final byTaste = taste.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final tags = <String>{
      ...byTaste
          .where((e) => !e.key.startsWith(_termPrefix))
          .take(6)
          .map((e) => e.key),
      ...interests,
    }.take(10).toList();

    // Learned free-text terms the user likes, strongest first.
    final topTerms = taste.entries
        .where((e) => e.key.startsWith(_termPrefix) && e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final termQuery = topTerms
        .take(_maxTermsPerQuery)
        .map((e) => e.key.substring(_termPrefix.length))
        .toList();

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> safe(
        String label,
        Future<QuerySnapshot<Map<String, dynamic>>> Function() run) async {
      try {
        return (await run()).docs;
      } catch (e) {
        print('FeedService: candidate source "$label" failed: $e');
        return [];
      }
    }

    final sources = await Future.wait([
      // Newest
      safe('recent', () => col
          .orderBy('createdAt', descending: true)
          .limit(_candidateLimit)
          .get()),
      // Tags the user likes
      if (tags.isNotEmpty)
        safe('interest', () => col
            .where('keywords', arrayContainsAny: tags)
            .limit(_candidateLimit)
            .get())
      else
        Future.value(<QueryDocumentSnapshot<Map<String, dynamic>>>[]),
      // Free-text terms the user likes (finds "more superhero Dailies"
      // even when their preset tags differ)
      if (termQuery.isNotEmpty)
        safe('terms', () => col
            .where('terms', arrayContainsAny: termQuery)
            .limit(_candidateLimit)
            .get())
      else
        Future.value(<QueryDocumentSnapshot<Map<String, dynamic>>>[]),
      // Most popular (only Dailies the stats functions have touched)
      safe('popular', () => col
          .orderBy('memberCount', descending: true)
          .limit(_candidateLimit ~/ 2)
          .get()),
      // Where friends are
      _fetchByIds(friendDailyIds.take(30).toList()),
    ]);

    // Fallback: if everything above came back empty (e.g. a brand-new
    // project), fall back to the old plain read so the feed isn't blank.
    var docs = sources.expand((s) => s).toList();
    if (docs.isEmpty) {
      docs = await safe('fallback', () => col.limit(100).get());
    }

    final out = <String, _Candidate>{};
    for (final d in docs) {
      if (out.containsKey(d.id) || hidden.contains(d.id)) continue;
      try {
        final daily = DailyData.fromFirestore(d);
        if (daily.creatorUid == uid) continue;
        out[d.id] = _Candidate(
            daily, _DailyStats.fromMap(d.data()), _readTerms(d.data()));
      } catch (e) {
        print('FeedService: skipping unreadable daily ${d.id}: $e');
      }
    }
    return out;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchByIds(
      List<String> ids) async {
    if (ids.isEmpty) return [];
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    try {
      for (final chunk in _chunk(ids, 10)) {
        final snap = await _firestore
            .collection('public_dailies')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        out.addAll(snap.docs);
      }
    } catch (e) {
      print('FeedService: friend daily fetch error: $e');
    }
    return out;
  }

  // ─── Data fetchers ──────────────────────────────────────────────────────────

  /// User's onboarding interests e.g. ['Sports', 'Music']
  static Future<List<String>> _getUserInterests(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final raw = doc.data()?['interests'];
      if (raw is List) return List<String>.from(raw);
    } catch (e) {
      print('FeedService: error fetching interests: $e');
    }
    return [];
  }

  /// tag → taste score with time decay already applied.
  /// Stored at users/{uid}/taste/{tag} → { score, updatedAt }.
  static Future<Map<String, double>> _getTaste(String uid) async {
    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('taste')
          .get();
      final now = DateTime.now();
      return {
        for (final doc in snap.docs)
          (doc.data()['label'] as String? ?? doc.id): _decayed(doc.data(), now),
      };
    } catch (e) {
      print('FeedService: error fetching taste: $e');
    }
    return {};
  }

  static double _decayed(Map<String, dynamic>? data, DateTime now) {
    if (data == null) return 0;
    final score = (data['score'] as num?)?.toDouble() ?? 0;
    final ts = data['updatedAt'];
    if (ts is! Timestamp) return score;
    final days = now.difference(ts.toDate()).inMinutes / (60 * 24);
    if (days <= 0) return score;
    return score * math.pow(0.5, days / _halfLifeDays).toDouble();
  }

  /// UIDs of accepted friends — queried by the user's own uid on either
  /// side, never by scanning everyone's friendships.
  static Future<List<String>> _getFriendUids(String uid) async {
    final friends = <String>{};
    try {
      final results = await Future.wait([
        _firestore
            .collection('friend_requests')
            .where('status', isEqualTo: 'accepted')
            .where('fromUserId', isEqualTo: uid)
            .get(),
        _firestore
            .collection('friend_requests')
            .where('status', isEqualTo: 'accepted')
            .where('toUserId', isEqualTo: uid)
            .get(),
      ]);
      for (final d in results[0].docs) {
        final to = d.data()['toUserId'] as String?;
        if (to != null) friends.add(to);
      }
      for (final d in results[1].docs) {
        final from = d.data()['fromUserId'] as String?;
        if (from != null) friends.add(from);
      }
    } catch (e) {
      print('FeedService: error fetching friends: $e');
    }
    return friends.toList();
  }

  /// Dailies the user explicitly said "not interested" to.
  static Future<Set<String>> _getHiddenIds(String uid) async {
    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('feed_hidden')
          .get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (e) {
      print('FeedService: error fetching hidden: $e');
    }
    return {};
  }

  /// dailyId → how many distinct friends are members of it or opened it
  /// recently. Membership (accepted invitations) is the stronger signal;
  /// opens are counted too.
  static Future<Map<String, int>> _getFriendDailyCounts(
      List<String> friendUids) async {
    if (friendUids.isEmpty) return {};
    final friendsByDaily = <String, Set<String>>{};
    final cutoff = DateTime.now().subtract(const Duration(days: 30));

    try {
      for (final chunk in _chunk(friendUids, 30)) {
        final results = await Future.wait([
          _firestore
              .collection('daily_invitations')
              .where('toUserId', whereIn: chunk)
              .where('status', isEqualTo: 'accepted')
              .get(),
          _firestore
              .collection('daily_interactions')
              .where('userId', whereIn: chunk)
              .get(),
        ]);

        for (final doc in results[0].docs) {
          final dailyId = doc.data()['dailyId'] as String?;
          final friend = doc.data()['toUserId'] as String?;
          if (dailyId != null && friend != null) {
            friendsByDaily.putIfAbsent(dailyId, () => {}).add(friend);
          }
        }
        for (final doc in results[1].docs) {
          final data = doc.data();
          final ts = data['timestamp'];
          if (ts is Timestamp && ts.toDate().isBefore(cutoff)) continue;
          final dailyId = data['dailyId'] as String?;
          final friend = data['userId'] as String?;
          if (dailyId != null && friend != null) {
            friendsByDaily.putIfAbsent(dailyId, () => {}).add(friend);
          }
        }
      }
    } catch (e) {
      print('FeedService: error fetching friend activity: $e');
    }
    return {for (final e in friendsByDaily.entries) e.key: e.value.length};
  }

  // ─── Scorers (each returns 0.0 – 1.0) ───────────────────────────────────────

  /// Affinity for one tag, -1..1: learned taste, lifted by a declared
  /// onboarding interest.
  static double _affinity(
      String tag, List<String> interests, Map<String, double> taste) {
    final t = ((taste[tag] ?? 0) / _tasteCap).clamp(-1.0, 1.0);
    if (t < 0) return t;
    final seed = interests.contains(tag) ? _onboardingSeed : 0.0;
    return 1 - (1 - t) * (1 - seed);
  }

  /// Interest from two signals combined: preset tags (broad, reliable) and
  /// free-text terms (specific, e.g. "batman"). Either one matching is
  /// enough to lift a Daily; both matching lifts it more.
  static double _scoreInterest(DailyData daily, List<String> terms,
      List<String> interests, Map<String, double> taste) {
    double tagScore = 0;
    if (daily.keywords.isNotEmpty) {
      final affs = daily.keywords
          .map((t) => math.max(0.0, _affinity(t, interests, taste)))
          .toList();
      final best = affs.reduce(math.max);
      final mean = affs.reduce((a, b) => a + b) / affs.length;
      tagScore = (0.6 * best + 0.4 * mean).clamp(0.0, 1.0);
    }

    final termScore = _termInterest(terms, taste);

    return (1 - (1 - tagScore) * (1 - 0.8 * termScore)).clamp(0.0, 1.0);
  }

  /// 0..1 interest in a set of free-text terms: the best match counts most,
  /// the top three together add a little more.
  static double _termInterest(List<String> terms, Map<String, double> taste) {
    if (terms.isEmpty) return 0;
    final affs = terms
        .map((t) => math.max(
        0.0, ((taste['$_termPrefix$t'] ?? 0) / _tasteCap).clamp(-1.0, 1.0)))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final top = affs.take(3).toList();
    final mean = top.reduce((a, b) => a + b) / top.length;
    return (0.7 * top.first + 0.3 * mean).clamp(0.0, 1.0);
  }

  static bool _hasStrongNegative(
      DailyData daily, List<String> terms, Map<String, double> taste) {
    for (final tag in daily.keywords) {
      if ((taste[tag] ?? 0) / _tasteCap < -0.5) return true;
    }
    return _termsStronglyDisliked(terms, taste);
  }

  static bool _termsStronglyDisliked(
      List<String> terms, Map<String, double> taste) {
    for (final t in terms) {
      if ((taste['$_termPrefix$t'] ?? 0) / _tasteCap < -0.5) return true;
    }
    return false;
  }

  /// How alive the Daily itself is: members and how recently someone posted.
  /// A Daily with no stats yet gets a neutral score so it isn't buried.
  static double _scoreQuality(_DailyStats s) {
    if (s.isUnknown) return 0.3;
    final members =
    (math.log(1 + s.memberCount + 1) / math.log(1 + 50)).clamp(0.0, 1.0);
    double fresh = 0;
    if (s.lastPostAt != null) {
      final days = DateTime.now().difference(s.lastPostAt!).inHours / 24.0;
      fresh = (1 - days / 14).clamp(0.0, 1.0);
    }
    return 0.5 * members + 0.5 * fresh;
  }

  /// Friends in it. One friend counts, three or more is the max.
  static double _scoreSocial(DailyData daily, Map<String, int> friendCounts) {
    final n = friendCounts[daily.id] ?? 0;
    return (n / 3).clamp(0.0, 1.0);
  }

  /// Full score = created today. Zero = created 30+ days ago.
  static double _scoreRecency(DailyData daily) {
    final age = DateTime.now().difference(daily.createdAt).inDays;
    if (age <= 0) return 1.0;
    if (age >= 30) return 0.0;
    return 1.0 - (age / 30.0);
  }

  // ─── Re-ranking: diversity + exploration ────────────────────────────────────

  static List<ScoredDaily> _rerank(List<ScoredDaily> sorted) {
    final remaining = List<ScoredDaily>.from(sorted);
    final out = <ScoredDaily>[];

    String primary(ScoredDaily s) =>
        s.daily.keywords.isEmpty ? '' : s.daily.keywords.first;

    while (remaining.isNotEmpty) {
      final slot = out.length;
      int pick = 0;
      bool exploring = false;

      if (slot % _explorationEvery == _explorationEvery - 1) {
        // Exploration slot: best Daily outside the user's current interests.
        final idx = remaining.indexWhere((s) => s.interestScore < 0.2);
        if (idx != -1) {
          pick = idx;
          exploring = true;
        }
      }

      if (!exploring) {
        // Best adjusted score among the top few, penalizing a tag that
        // already appeared in the last two picks.
        final recentTags = out.reversed.take(2).map(primary).toSet();
        double bestAdj = -double.infinity;
        final window = math.min(12, remaining.length);
        for (var i = 0; i < window; i++) {
          final tag = primary(remaining[i]);
          final penalty =
          (tag.isNotEmpty && recentTags.contains(tag)) ? _diversityPenalty : 0.0;
          final adj = remaining[i].score - penalty;
          if (adj > bestAdj) {
            bestAdj = adj;
            pick = i;
          }
        }
      }

      final chosen = remaining.removeAt(pick);
      out.add(exploring ? chosen.asExploration() : chosen);
    }
    return out;
  }

  // ─── Learning from behavior ─────────────────────────────────────────────────

  /// Back-compat: opening a Daily. Existing callers keep working.
  static Future<void> recordInteraction(DailyData daily) =>
      recordEvent(daily, FeedEvent.open);

  /// Record something the user did with a Daily. Updates the decaying
  /// per-tag taste profile and (for positive events) the interaction log
  /// that feeds friends' social scoring.
  static Future<void> recordEvent(DailyData daily, FeedEvent event) async {
    final uid = _uid;
    if (uid == null) return;
    final weight = _eventWeights[event] ?? 0;

    try {
      final keys = await _keysFor(daily.id, fallbackTags: daily.keywords);
      if (keys.isNotEmpty) await _recordKeys(keys, weight);

      if (weight > 0) {
        await _firestore.collection('daily_interactions').add({
          'userId': uid,
          'dailyId': daily.id,
          'type': event.name,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('FeedService: recordEvent error: $e');
    }
  }

  /// Taste keys for a Daily: its preset tags plus its "t:" terms, with the
  /// term keys damped via [_recordKeys]. Cached per Daily for the session.
  static final Map<String, List<String>> _keyCache = {};

  static Future<List<String>> _keysFor(String dailyId,
      {List<String> fallbackTags = const []}) async {
    final cached = _keyCache[dailyId];
    if (cached != null) return cached;
    var tags = List<String>.from(fallbackTags);
    var terms = <String>[];
    try {
      final doc =
      await _firestore.collection('public_dailies').doc(dailyId).get();
      final data = doc.data();
      final raw = data?['keywords'];
      if (raw is List && tags.isEmpty) tags = List<String>.from(raw);
      terms = _readTerms(data);
    } catch (e) {
      print('FeedService: keys lookup error: $e');
    }
    final keys = [
      ...tags,
      ...terms.take(_maxTermsPerEvent).map((t) => '$_termPrefix$t'),
    ];
    // Only cache a real answer, so a failed lookup is retried next time.
    if (keys.isNotEmpty) _keyCache[dailyId] = keys;
    return keys;
  }

  /// Add [weight] to each key's decaying taste score. Term keys ("t:...")
  /// get a damped weight.
  static Future<void> _recordKeys(List<String> keys, double weight) async {
    final uid = _uid;
    if (uid == null || keys.isEmpty) return;
    final refs = keys
        .map((k) => _firestore
        .collection('users')
        .doc(uid)
        .collection('taste')
        .doc(_docKey(k)))
        .toList();

    await _firestore.runTransaction((tx) async {
      final now = DateTime.now();
      final snaps = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final r in refs) {
        snaps.add(await tx.get(r));
      }
      for (var i = 0; i < refs.length; i++) {
        final w = keys[i].startsWith(_termPrefix)
            ? weight * _termWeightFactor
            : weight;
        final current = _decayed(snaps[i].data(), now);
        tx.set(refs[i], {
          'label': keys[i],
          'score': (current + w).clamp(-20.0, 20.0),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// Same as [recordEvent] for callers that only know the Daily's id (a
  /// message widget, say).
  static Future<void> recordEventForDailyId(
      String dailyId, FeedEvent event) async {
    if (dailyId.isEmpty || dailyId == 'unknown_daily') return;
    try {
      final keys = await _keysFor(dailyId);
      if (keys.isEmpty) return;
      await _recordKeys(keys, _eventWeights[event] ?? 0);
    } catch (e) {
      print('FeedService: recordEventForDailyId error: $e');
    }
  }

  static const Map<ClipEvent, double> _clipWeights = {
    ClipEvent.like: 3,
    ClipEvent.comment: 3,
    ClipEvent.share: 4,
    ClipEvent.watched: 2,
    ClipEvent.skipped: -1,
  };

  static final Map<String, List<String>> _clipTermCache = {};

  /// Record something the user did with a clip. Teaches two things:
  ///  - creator affinity (users/{uid}/creator_affinity/{creatorUid})
  ///  - topic taste from the clip's caption keywords, in the same taste
  ///    profile Dailies use — so liking superhero clips also lifts superhero
  ///    Dailies. Pass [clipId] (or [terms] if already known) to enable it.
  static Future<void> recordClipEvent({
    required String creatorUid,
    required ClipEvent event,
    String? clipId,
    List<String>? terms,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final weight = _clipWeights[event] ?? 0;

    if (creatorUid.isNotEmpty && creatorUid != uid) {
      try {
        final ref = _firestore
            .collection('users')
            .doc(uid)
            .collection('creator_affinity')
            .doc(creatorUid);
        await _firestore.runTransaction((tx) async {
          final snap = await tx.get(ref);
          final current = _decayed(snap.data(), DateTime.now());
          tx.set(ref, {
            'score': (current + weight).clamp(-20.0, 20.0),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      } catch (e) {
        print('FeedService: recordClipEvent creator error: $e');
      }
    }

    try {
      var t = terms;
      if ((t == null || t.isEmpty) && clipId != null && clipId.isNotEmpty) {
        t = _clipTermCache[clipId];
        if (t == null) {
          final doc = await _firestore.collection('clips').doc(clipId).get();
          t = _readTerms(doc.data());
          if (t.isNotEmpty) _clipTermCache[clipId] = t;
        }
      }
      if (t == null || t.isEmpty) return;
      await _recordKeys(
          t.take(_maxTermsPerEvent).map((x) => '$_termPrefix$x').toList(),
          weight);
    } catch (e) {
      print('FeedService: recordClipEvent topic error: $e');
    }
  }

  // ─── Clip ranking ───────────────────────────────────────────────────────────

  /// Best-first order of clip ids for this user. Call once per session and
  /// keep the order (re-ranking mid-scroll would shuffle the clip under the
  /// user's thumb).
  ///
  /// score = topic interest (caption keywords vs taste) .35
  ///       + creator affinity .30 + friend posted it .15 + recency .20,
  /// halved for creators/topics the user keeps skipping; then a small
  /// penalty for the same creator twice in a row and an exploration clip
  /// every 5th slot.
  static Future<List<String>> rankClipIds(List<ClipData> clips) async {
    final uid = _uid;
    if (uid == null || clips.isEmpty) return clips.map((c) => c.id).toList();

    final results = await Future.wait([
      _getTaste(uid),
      _getFriendUids(uid),
      _firestore
          .collection('users')
          .doc(uid)
          .collection('creator_affinity')
          .get()
          .then<Map<String, double>>((snap) {
        final now = DateTime.now();
        return {for (final d in snap.docs) d.id: _decayed(d.data(), now)};
      }).catchError((_) => <String, double>{}),
    ]);
    final taste = results[0] as Map<String, double>;
    final friends = (results[1] as List<String>).toSet();
    final affinity = results[2] as Map<String, double>;

    final rows = clips.map((c) {
      final interest = _termInterest(c.terms, taste);
      final aff = ((affinity[c.creatorUid] ?? 0) / _tasteCap).clamp(-1.0, 1.0);
      final social = friends.contains(c.creatorUid) ? 1.0 : 0.0;
      final ageDays = DateTime.now().difference(c.createdAt).inHours / 24.0;
      final recency = (1 - ageDays / 14).clamp(0.0, 1.0);

      var score = 0.35 * interest +
          0.30 * math.max(0.0, aff) +
          0.15 * social +
          0.20 * recency;
      if (aff < -0.5 || _termsStronglyDisliked(c.terms, taste)) {
        score *= 0.5;
      }
      return _ClipRow(c, score, interest, aff);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final remaining = List.of(rows);
    final out = <String>[];
    String? lastCreator;
    while (remaining.isNotEmpty) {
      var pick = 0;
      if (out.length % _explorationEvery == _explorationEvery - 1) {
        final idx = remaining.indexWhere((r) => r.interest < 0.2 && r.aff <= 0);
        if (idx != -1) pick = idx;
      } else {
        var best = -double.infinity;
        for (var i = 0; i < math.min(8, remaining.length); i++) {
          final adj = remaining[i].score -
              (remaining[i].clip.creatorUid == lastCreator ? 0.1 : 0.0);
          if (adj > best) {
            best = adj;
            pick = i;
          }
        }
      }
      final chosen = remaining.removeAt(pick);
      lastCreator = chosen.clip.creatorUid;
      out.add(chosen.clip.id);
    }
    return out;
  }

  /// "Not interested": hides the Daily from this user's feed for good and
  /// teaches the taste profile to avoid its tags.
  static Future<void> markNotInterested(DailyData daily) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('feed_hidden')
          .doc(daily.id)
          .set({'at': FieldValue.serverTimestamp()});
    } catch (e) {
      print('FeedService: markNotInterested error: $e');
    }
    await recordEvent(daily, FeedEvent.notInterested);
  }

  static final Set<String> _impressionsLogged = {};

  /// Count that these Dailies were shown. Call when cards actually appear
  /// (once per Daily per app session). Lets the feed learn add-rate =
  /// adds ÷ impressions later.
  static Future<void> recordImpressions(List<DailyData> dailies) async {
    final fresh =
    dailies.where((d) => _impressionsLogged.add(d.id)).toList();
    if (fresh.isEmpty) return;
    try {
      final batch = _firestore.batch();
      for (final d in fresh) {
        batch.update(_firestore.collection('public_dailies').doc(d.id),
            {'impressions': FieldValue.increment(1)});
      }
      await batch.commit();
    } catch (e) {
      print('FeedService: recordImpressions error: $e');
    }
  }

  // ─── Public feed mirror ─────────────────────────────────────────────────────

  /// Mirror a newly published Daily into `public_dailies` (the
  /// discover-feed collection — holds both public and private Dailies
  /// so private ones can still be found and requested, just not
  /// auto-joined). Call this from NewDailyFinalScreen right after
  /// DailyList.addDaily().
  ///
  /// Merges, so republishing (e.g. a privacy change) never wipes the stats
  /// the Cloud Functions keep on the doc.
  static Future<void> publishToPublicFeed(DailyData daily) async {
    try {
      await _firestore
          .collection('public_dailies')
          .doc(daily.id)
          .set(daily.toFirestoreJson(), SetOptions(merge: true));
      print('FeedService: mirrored daily ${daily.id} to public_dailies (privacy=${daily.privacy})');
    } catch (e) {
      print('FeedService: publishToPublicFeed error: $e');
    }
  }

  /// Remove a Daily from the public feed mirror (on delete or privacy change).
  static Future<void> removeFromPublicFeed(String dailyId) async {
    try {
      await _firestore.collection('public_dailies').doc(dailyId).delete();
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