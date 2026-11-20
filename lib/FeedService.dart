import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'clip_service.dart';
import 'GroupChatService.dart';
import 'SafetyService.dart';

/// Things a user can do that tell the feed what they like. Each has a
/// weight (see FeedService._eventWeights); positive ones pull similar
/// Dailies up, negative ones push them down.
enum FeedEvent { open, add, post, react, comment, interested, notInterested, leave }

/// Things a user can do with a clip. Clips teach the feed which CREATORS the
/// user likes (users/{uid}/creator_affinity) and which TOPICS (taste).
/// Watching is reported through [FeedService.recordClipView] instead, which
/// knows how much of the clip was watched.
enum ClipEvent { like, comment, share, watched, skipped, notInterested }

/// A scored Daily ready for display in a feed.
class ScoredDaily {
  final DailyData daily;
  final double score;         // 0.0 – 1.0 normalized total score
  final double interestScore; // taste profile + onboarding interests
  final double activityScore; // how good / converting the Daily is
  final double socialScore;   // friends who are in it / opened it
  final double recencyScore;  // how alive it is right now
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

/// Per-Daily stats kept on the public_dailies doc (Cloud Functions keep
/// memberCount/lastPostAt/postCount; the app counts impressions). All may be
/// missing on older Dailies.
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

class _Candidate {
  final DailyData daily;
  final _DailyStats stats;
  final List<String> terms; // free-text keywords from the Cloud Function
  _Candidate(this.daily, this.stats, this.terms);
}

class _ClipRow {
  final ClipData clip;
  final double score;
  final double interest;
  final double aff;
  _ClipRow(this.clip, this.score, this.interest, this.aff);
}

/// Everything the clip scorer needs about the viewer, loaded once.
class _ClipViewer {
  final Map<String, double> taste;
  final Set<String> friends;
  final Map<String, double> affinity; // creatorUid -> decayed score
  final Map<String, double> seen;     // clipId -> how much of it they watched
  final Map<String, String> friendNames; // uid -> username
  final Map<String, int> fof; // friend-of-friend uid -> friends in common
  const _ClipViewer(this.taste, this.friends, this.affinity, this.seen,
      this.friendNames, [this.fof = const {}]);
}

/// People your friends are friends with (not you, not your friends yet).
class FriendsOfFriends {
  /// uid -> which of YOUR friends know them
  final Map<String, Set<String>> via;

  /// your friends: uid -> username
  final Map<String, String> friendNames;

  const FriendsOfFriends(this.via, this.friendNames);

  int count(String uid) => via[uid]?.length ?? 0;

  /// Usernames of your friends who know [uid], most familiar order kept.
  List<String> namesFor(String uid) => (via[uid] ?? const <String>{})
      .map((f) => friendNames[f] ?? '')
      .where((n) => n.isNotEmpty)
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Most-connected first.
  List<String> top(int n) => (via.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length)))
      .take(n)
      .map((e) => e.key)
      .toList();
}

/// A clip found through a group (friends, a Daily, a group chat).
class _LensHit {
  final ClipData clip;
  final Set<String> likers = {}; // group members who liked it
  DateTime? lastLikeAt;
  _LensHit(this.clip);
}

/// A way to watch Clips: For You, Friends, one Daily, or one group chat.
class ClipLens {
  final String kind; // 'forYou' | 'friends' | 'daily' | 'chat'
  final String id;   // the Daily's or group chat's id ('' otherwise)
  final String label;
  const ClipLens(this.kind, this.id, this.label);

  static const ClipLens forYou = ClipLens('forYou', '', 'For You');
  static const ClipLens friends = ClipLens('friends', '', 'Friends');

  bool get isForYou => kind == 'forYou';
  String get key => '$kind:$id';

  @override
  bool operator ==(Object other) => other is ClipLens && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

/// Who among the viewer's people liked a clip, for the label on it:
/// "Sam and 2 others in Hiking Crew liked this".
class ClipProof {
  final List<String> names; // usernames we know, in no special order
  final int count;          // how many liked it in total
  final String? place;      // the Daily / group chat name, or null

  const ClipProof({required this.names, required this.count, this.place});

  String get label {
    final where = place == null ? '' : ' in $place';
    if (names.isEmpty) {
      return count == 1 ? '1 person$where liked this' : '$count people$where liked this';
    }
    final first = names.first;
    final others = count - 1;
    if (others <= 0) return '$first$where liked this';
    return '$first and $others ${others == 1 ? 'other' : 'others'}$where liked this';
  }
}

/// One page of clips plus the "liked by" labels for them. [firstMoreId] is
/// the first "More like this" clip (after a group's own clips ran out).
class ClipFeedPage {
  final List<ClipData> clips;
  final Map<String, ClipProof> proof; // clipId -> label
  final String? firstMoreId;
  const ClipFeedPage(this.clips, this.proof, {this.firstMoreId});
}

/// The feed engine behind For You Dailies, the Clips feed and Search ranking.
///
/// DAILIES (getRankedFeed)
///  1. Taste profile: every weighted event updates a per-tag/keyword score at
///     users/{uid}/taste/{key}, fading with a [_halfLifeDays]-day half-life.
///     Keys that have faded to nothing are deleted, so it stays small.
///  2. Candidates from several sources: newest, matching tags, matching
///     keywords, most members, and Dailies friends are in.
///  3. Score = interest .35 + quality .20 + friends .25 + alive-now .20,
///     where quality includes how often people who SEE it ADD it, and
///     Dailies this viewer keeps scrolling past fade out (fatigue).
///  4. A little randomness each load, a variety pass (no same tag twice in a
///     row) and an exploration slot every 5th, picked at random from good
///     Dailies outside the viewer's interests.
///
/// CLIPS (getClipFeedPage)
///  1. Candidates from: newest, most liked, creators the viewer likes,
///     friends, and topics the viewer likes. Clips they've already seen are
///     left out (users/{uid}/clip_views doubles as the seen list).
///  2. Score = quality .30 (how much of it people watch, completions,
///     likes/comments/shares/rewatches per view, smoothed so a clip with 3
///     views isn't over- or under-rated) + topic .25 + creator .20 +
///     recency .15 + friend .10.
///  3. Same randomness, no same creator back to back, and exploration every
///     5th clip. Clips friends liked get a boost and a "liked by" label.
///  4. Lenses (getClipLenses): Friends, the user's top Dailies and group
///     chats. Each shows what people there liked or posted, then "More like
///     this" from For You once those run out.
class FeedService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final math.Random _rng = math.Random();

  static String? get _uid => _auth.currentUser?.uid;

  // ─── Daily weights (sum to 1.0) ─────────────────────────────────────────────
  static const double _wInterest = 0.35;
  static const double _wQuality  = 0.20;
  static const double _wSocial   = 0.25;
  static const double _wAlive    = 0.20;

  // ─── Clip weights (sum to 1.0) ──────────────────────────────────────────────
  static const double _cQuality  = 0.30;
  static const double _cInterest = 0.25;
  static const double _cCreator  = 0.20;
  static const double _cRecency  = 0.15;
  static const double _cFriend   = 0.10;

  // ─── Tuning ─────────────────────────────────────────────────────────────────
  static const double _halfLifeDays = 21;     // taste decay
  static const double _tasteCap = 8;          // taste score that counts as "max love"
  static const double _onboardingSeed = 0.4;  // affinity for a declared interest
  static const int _candidateLimit = 60;      // per Daily source
  static const int _clipSourceLimit = 40;     // per clip source (newest gets more)
  static const int _explorationEvery = 5;     // every Nth slot explores
  static const double _diversityPenalty = 0.06;
  static const double _jitter = 0.05;         // +-2.5% so refreshes differ
  static const double _pruneBelow = 0.05;     // taste keys this faded get deleted

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

  static const Map<ClipEvent, double> _clipWeights = {
    ClipEvent.like: 3,
    ClipEvent.comment: 3,
    ClipEvent.share: 4,
    ClipEvent.watched: 2,
    ClipEvent.skipped: -1,
    // "Not interested": a strong push away from its topics and creator.
    ClipEvent.notInterested: -8,
  };

  // ─── Keyword terms ──────────────────────────────────────────────────────────
  // Besides the preset tags, each Daily and clip has free-text `terms` (e.g.
  // "batman", "marvel") made by a Cloud Function. They live in the same taste
  // profile as tags, prefixed with "t:" so "music" the term never collides
  // with "Music" the tag.

  static const String _termPrefix = 't:';

  /// Everyday words for each preset tag (the 16 Daily tags, which are also
  /// the onboarding interests), written the way topic terms are stored
  /// (lowercase, singular). Clips only have terms, never tags, so these let
  /// "Gaming" Dailies and a "Gaming" interest lift gaming clips too. Kept in
  /// sync with TAG_TERMS in functions/index.js.
  static const Map<String, List<String>> tagTerms = {
    'Sports': ['sport', 'basketball', 'football', 'soccer'],
    'Music': ['music', 'song', 'concert'],
    'Gaming': ['gaming', 'game', 'videogame'],
    'Fitness': ['fitness', 'gym', 'workout'],
    'Food': ['food', 'cooking', 'recipe'],
    'Travel': ['travel', 'trip', 'vacation'],
    'Art': ['art', 'drawing', 'painting'],
    'Fashion': ['fashion', 'outfit', 'style'],
    'Nature': ['nature', 'outdoor', 'hiking'],
    'Tech': ['tech', 'technology', 'coding'],
    'Movies / TV': ['movie', 'film', 'show'],
    'Books': ['book', 'reading'],
    'Health': ['health', 'wellness', 'yoga'],
    'Finance': ['finance', 'money', 'investing'],
    'Science': ['science', 'astronomy'],
    'Comedy': ['comedy', 'funny', 'meme'],
  };

  /// Terms per tag added to a Daily's taste keys (kept small: each key is a
  /// read in the taste update).
  static const int _termsPerTag = 2;
  static const double _termWeightFactor = 0.8; // terms are noisier than tags
  static const int _maxTermsPerEvent = 8;
  static const int _maxTermsPerQuery = 10;

  static List<String> _readTerms(Map<String, dynamic>? data) {
    final raw = data?['terms'];
    return raw is List ? raw.whereType<String>().toList() : <String>[];
  }

  static String _docKey(String key) => key.replaceAll('/', '∕');

  static double _noise() => (_rng.nextDouble() - 0.5) * _jitter;

  // ═══════════════════════════════════════════════════════════════════════════
  // DAILIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Candidates from several sources, scored and re-ranked, best-first.
  /// Includes public AND private Dailies (private ones can be found and
  /// requested, never auto-joined) — callers filter by privacy.
  static Future<List<ScoredDaily>> getRankedFeed() async {
    final uid = _uid;
    if (uid == null) return [];

    final results = await Future.wait([
      _getUserInterests(uid),   // List<String>
      _getTaste(uid),           // Map<String, double>  key -> decayed score
      _getFriendUids(uid),      // List<String>
      _getHiddenIds(uid),       // Set<String>
      _getShownCounts(uid),     // Map<String, int>     dailyId -> times shown
    ]);

    final interests = results[0] as List<String>;
    final taste     = results[1] as Map<String, double>;
    final friends   = results[2] as List<String>;
    final hidden    = results[3] as Set<String>;
    final shown     = results[4] as Map<String, int>;

    // dailyId -> number of friends who are members / were active in it
    final friendCounts = await _getFriendDailyCounts(friends);
    // Same for people your friends know (mutual friends), weighted lower.
    final fof = await friendsOfFriends();
    final fofCounts = await _getFriendDailyCounts(fof.top(60));

    final candidates = await _getCandidates(
      uid: uid,
      interests: interests,
      taste: taste,
      friendDailyIds: {...friendCounts.keys, ...fofCounts.keys}.toList(),
      hidden: hidden,
    );
    if (candidates.isEmpty) return [];

    final scored = candidates.values.map((c) {
      final daily = c.daily;
      final interest = _scoreInterest(daily, c.terms, interests, taste);
      final quality  = _scoreQuality(c.stats);
      final social   = math.max(
          _scoreSocial(daily, friendCounts),
          math.max(
              0.5 * _scoreSocial(daily, fofCounts),
              fof.count(daily.creatorUid ?? '') > 0 ? 0.4 : 0.0));
      final alive    = _scoreAlive(daily, c.stats);

      var total = interest * _wInterest +
          quality * _wQuality +
          social * _wSocial +
          alive * _wAlive;

      // Topics the user has pushed away drag the whole score down.
      if (_hasStrongNegative(daily, c.terms, taste)) total *= 0.5;

      // Shown here again and again without the user doing anything with it:
      // let it fade so the feed doesn't keep pushing the same cards.
      total *= _fatigue(shown[daily.id] ?? 0);

      total += _noise();

      return ScoredDaily(
        daily: daily,
        score: total.clamp(0.0, 1.0),
        interestScore: interest,
        activityScore: quality,
        socialScore: social,
        recencyScore: alive,
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

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _safe(
      String label,
      Future<QuerySnapshot<Map<String, dynamic>>> Function() run) async {
    try {
      return (await run()).docs;
    } catch (e) {
      print('FeedService: source "$label" failed: $e');
      return [];
    }
  }

  static List<String> _topTags(
      Map<String, double> taste, List<String> interests) {
    final byTaste = taste.entries
        .where((e) => e.value > 0 && !e.key.startsWith(_termPrefix))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return <String>{
      ...byTaste.take(6).map((e) => e.key),
      ...interests,
    }.take(10).toList();
  }

  static List<String> _topTerms(Map<String, double> taste) {
    final topTerms = taste.entries
        .where((e) => e.key.startsWith(_termPrefix) && e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return topTerms
        .take(_maxTermsPerQuery)
        .map((e) => e.key.substring(_termPrefix.length))
        .toList();
  }

  static Future<Map<String, _Candidate>> _getCandidates({
    required String uid,
    required List<String> interests,
    required Map<String, double> taste,
    required List<String> friendDailyIds,
    required Set<String> hidden,
  }) async {
    final col = _firestore.collection('public_dailies');
    final tags = _topTags(taste, interests);
    final termQuery = _topTerms(taste);

    final sources = await Future.wait([
      _safe('recent', () => col
          .orderBy('createdAt', descending: true)
          .limit(_candidateLimit)
          .get()),
      if (tags.isNotEmpty)
        _safe('interest', () => col
            .where('keywords', arrayContainsAny: tags)
            .limit(_candidateLimit)
            .get()),
      if (termQuery.isNotEmpty)
        _safe('terms', () => col
            .where('terms', arrayContainsAny: termQuery)
            .limit(_candidateLimit)
            .get()),
      // Alive right now: posted in most recently.
      _safe('active', () => col
          .orderBy('lastPostAt', descending: true)
          .limit(_candidateLimit ~/ 2)
          .get()),
      _safe('popular', () => col
          .orderBy('memberCount', descending: true)
          .limit(_candidateLimit ~/ 2)
          .get()),
      _fetchByIds(friendDailyIds.take(30).toList()),
    ]);

    var docs = sources.expand((s) => s).toList();
    if (docs.isEmpty) {
      docs = await _safe('fallback', () => col.limit(100).get());
    }

    final out = <String, _Candidate>{};
    for (final d in docs) {
      if (out.containsKey(d.id) || hidden.contains(d.id)) continue;
      if (d.data()['hidden'] == true) continue; // removed after reports
      try {
        final daily = DailyData.fromFirestore(d);
        if (daily.creatorUid == uid) continue;
        final creator = daily.creatorUid;
        if (creator != null && SafetyService.instance.isHidden(creator)) continue;
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
      for (final chunk in _chunk(ids, 30)) {
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

  /// key -> taste score with time decay applied. Keys that have faded to
  /// almost nothing (things the user stopped engaging with) are deleted on
  /// the way out, so the profile keeps growing with new interests but never
  /// piles up old ones.
  static Future<Map<String, double>> _getTaste(String uid) async {
    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('taste')
          .get();
      final now = DateTime.now();
      final out = <String, double>{};
      final faded = <DocumentReference>[];
      for (final doc in snap.docs) {
        final v = _decayed(doc.data(), now);
        if (v.abs() < _pruneBelow) {
          faded.add(doc.reference);
          continue;
        }
        out[(doc.data()['label'] as String?) ?? doc.id] = v;
      }
      if (faded.isNotEmpty) _deleteAll(faded.take(200).toList());
      return out;
    } catch (e) {
      print('FeedService: error fetching taste: $e');
    }
    return {};
  }

  static Future<void> _deleteAll(List<DocumentReference> refs) async {
    try {
      final batch = _firestore.batch();
      for (final r in refs) {
        batch.delete(r);
      }
      await batch.commit();
    } catch (e) {
      print('FeedService: taste prune error: $e');
    }
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
  static Future<List<String>> _getFriendUids(String uid) async =>
      (await _getFriendNames(uid)).keys.toList();

  /// uid -> username of every accepted friend (names come off the friend
  /// request docs, so no extra reads).
  static Future<Map<String, String>> _getFriendNames(String uid) async {
    final friends = <String, String>{};
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
        if (to != null) friends[to] = (d.data()['toUsername'] as String?) ?? '';
      }
      for (final d in results[1].docs) {
        final from = d.data()['fromUserId'] as String?;
        if (from != null) {
          friends[from] = (d.data()['fromUsername'] as String?) ?? '';
        }
      }
    } catch (e) {
      print('FeedService: error fetching friends: $e');
    }
    return friends;
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

  /// dailyId -> how many times For You has shown it to this user without
  /// them engaging (reset whenever they open or add it).
  static Future<Map<String, int>> _getShownCounts(String uid) async {
    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('feed_seen')
          .orderBy('lastAt', descending: true)
          .limit(300)
          .get();
      return {
        for (final d in snap.docs)
          d.id: (d.data()['count'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      print('FeedService: error fetching shown counts: $e');
    }
    return {};
  }

  /// dailyId -> how many distinct friends are members of it or were active
  /// in it in the last 30 days. daily_interactions holds ONE doc per person
  /// per Daily (and a daily Cloud Function clears anything older than 30
  /// days), so this read stays small no matter how much friends use the app.
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

  // ─── Daily scorers (each returns 0.0 – 1.0) ─────────────────────────────────

  /// Affinity for one tag, -1..1: learned taste, lifted by a declared
  /// onboarding interest.
  static double _affinity(
      String tag, List<String> interests, Map<String, double> taste) {
    final t = ((taste[tag] ?? 0) / _tasteCap).clamp(-1.0, 1.0);
    if (t < 0) return t;
    final seed = interests.contains(tag) ? _onboardingSeed : 0.0;
    return 1 - (1 - t) * (1 - seed);
  }

  /// Interest from preset tags (broad, reliable) and free-text terms
  /// (specific, e.g. "batman"). Either one matching lifts a Daily; both
  /// matching lifts it more.
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

  /// How good the Daily is: how many members it has, and how often people
  /// who are SHOWN it end up joining (members per impression, smoothed so a
  /// Daily shown twice isn't judged on two data points). Unknown = neutral.
  static double _scoreQuality(_DailyStats s) {
    if (s.isUnknown && s.impressions == 0) return 0.3;
    final members =
    (math.log(2 + s.memberCount) / math.log(52)).clamp(0.0, 1.0);
    // Prior: ~1 join per 12 impressions until there's real data.
    final joinRate = (s.memberCount + 1) / (s.impressions + 12);
    final conversion = (joinRate / 0.25).clamp(0.0, 1.0);
    return 0.5 * members + 0.5 * conversion;
  }

  /// How alive it is right now: mostly how recently someone posted, plus a
  /// little for being new (so brand-new Dailies get a first look).
  static double _scoreAlive(DailyData daily, _DailyStats s) {
    final ageDays = DateTime.now().difference(daily.createdAt).inHours / 24.0;
    final newness = (1 - ageDays / 14).clamp(0.0, 1.0);
    if (s.lastPostAt == null) return 0.6 * newness;
    final quietDays =
        DateTime.now().difference(s.lastPostAt!).inHours / 24.0;
    final active = math.exp(-quietDays / 3); // halves about every 2 days
    return (0.75 * active + 0.25 * newness).clamp(0.0, 1.0);
  }

  /// Friends in it. One friend counts, three or more is the max.
  static double _scoreSocial(DailyData daily, Map<String, int> friendCounts) {
    final n = friendCounts[daily.id] ?? 0;
    return (n / 3).clamp(0.0, 1.0);
  }

  /// 1.0 for the first few times a card is shown, then fading: shown 10
  /// times with no interest = about half the score.
  static double _fatigue(int shownCount) {
    final extra = math.max(0, shownCount - 3);
    return 1 / (1 + 0.15 * extra);
  }

  // ─── Daily re-ranking: variety + exploration ────────────────────────────────

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
        // Exploration: a random one of the best few outside the user's
        // interests, so it isn't the same "exploration" Daily every time.
        final pool = <int>[];
        for (var i = 0; i < remaining.length && pool.length < 6; i++) {
          if (remaining[i].interestScore < 0.25) pool.add(i);
        }
        if (pool.isNotEmpty) {
          pick = pool[_rng.nextInt(pool.length)];
          exploring = true;
        }
      }

      if (!exploring) {
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

  // ─── Learning from Daily behavior ───────────────────────────────────────────

  /// Back-compat: opening a Daily. Existing callers keep working.
  static Future<void> recordInteraction(DailyData daily) =>
      recordEvent(daily, FeedEvent.open);

  static bool _isMine(String dailyId) =>
      DailyList.dailies.any((d) => d.id == dailyId);

  /// Record something the user did with a Daily. Updates the taste profile
  /// and (for positive events) the user's activity record that friends'
  /// feeds read.
  ///
  /// Opening a Daily you're already in doesn't teach taste: people open
  /// their own Dailies every day, and that would drown out everything else.
  static Future<void> recordEvent(DailyData daily, FeedEvent event) async {
    final uid = _uid;
    if (uid == null) return;
    var weight = _eventWeights[event] ?? 0;
    if (event == FeedEvent.open && _isMine(daily.id)) weight = 0;

    try {
      if (weight != 0) {
        final keys = await _keysFor(daily.id, fallbackTags: daily.keywords);
        if (keys.isNotEmpty) await _recordKeys(keys, weight);
      }

      if ((_eventWeights[event] ?? 0) > 0) {
        // One doc per person per Daily, overwritten, never piling up.
        await _firestore
            .collection('daily_interactions')
            .doc('${uid}_${daily.id}')
            .set({
          'userId': uid,
          'dailyId': daily.id,
          'type': event.name,
          'timestamp': FieldValue.serverTimestamp(),
        });
        // They engaged with it: stop counting it as "shown and ignored".
        _firestore
            .collection('users')
            .doc(uid)
            .collection('feed_seen')
            .doc(daily.id)
            .set({'count': 0, 'lastAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true))
            .catchError((_) {});
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
    // The Daily's own words first, then everyday words for its tags, so a
    // Daily tagged "Gaming" with a plain title still teaches "gaming" (what
    // the Clips feed matches on).
    final termSet = <String>{
      ...terms.take(_maxTermsPerEvent),
      for (final tag in tags) ...?tagTerms[tag]?.take(_termsPerTag),
    };
    final keys = [
      ...tags,
      ...termSet.map((t) => '$_termPrefix$t'),
    ];
    if (keys.isNotEmpty) _keyCache[dailyId] = keys;
    return keys;
  }

  /// Add [weight] to each key's decaying taste score. Term keys ("t:...")
  /// get a damped weight.
  static Future<void> _recordKeys(List<String> keys, double weight) async {
    final uid = _uid;
    if (uid == null || keys.isEmpty || weight == 0) return;
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

  /// How long you spent in a Daily (screen open, app in the foreground).
  /// Lingering is a quiet signal of interest, on top of the "open" event:
  /// it updates the same taste profile both For You and Clips read.
  /// Under 15 seconds counts for nothing (a quick peek).
  static Future<void> recordDailyTime(DailyData daily, Duration spent) async {
    if (_uid == null || _isMine(daily.id)) return;
    final secs = spent.inSeconds;
    final double weight = secs >= 180
        ? 3
        : secs >= 60
        ? 2
        : secs >= 15
        ? 1
        : 0;
    if (weight == 0) return;
    try {
      final keys = await _keysFor(daily.id, fallbackTags: daily.keywords);
      if (keys.isNotEmpty) await _recordKeys(keys, weight);
    } catch (e) {
      print('FeedService: recordDailyTime error: $e');
    }
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

  /// Count that these Dailies were shown (once per Daily per app session):
  /// a global count on the Daily (for its join rate) and a per-user count
  /// (so cards this user keeps ignoring fade out of their feed).
  static Future<void> recordImpressions(List<DailyData> dailies) async {
    final uid = _uid;
    final fresh =
    dailies.where((d) => _impressionsLogged.add(d.id)).toList();
    if (fresh.isEmpty) return;
    try {
      final batch = _firestore.batch();
      for (final d in fresh) {
        batch.update(_firestore.collection('public_dailies').doc(d.id),
            {'impressions': FieldValue.increment(1)});
        if (uid != null) {
          batch.set(
            _firestore
                .collection('users')
                .doc(uid)
                .collection('feed_seen')
                .doc(d.id),
            {
              'count': FieldValue.increment(1),
              'lastAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
      await batch.commit();
    } catch (e) {
      print('FeedService: recordImpressions error: $e');
    }
  }

  // ─── Public feed mirror ─────────────────────────────────────────────────────

  /// Mirror a newly published Daily into `public_dailies` (the
  /// discover-feed collection — holds both public and private Dailies so
  /// private ones can still be found and requested, just not auto-joined).
  /// Merges, so republishing never wipes the stats kept on the doc.
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

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIPS
  // ═══════════════════════════════════════════════════════════════════════════

  /// 0..1: how good a clip is, from how people who saw it reacted.
  ///  - how much of it people watch on average, and how many finish it
  ///  - likes, comments (x2), shares (x3) and rewatches (x1.5) per view
  /// Smoothed toward an average clip until it has real views, so 2 views
  /// and 2 likes doesn't beat 2,000 views and 900 likes.
  static double clipQuality(ClipData c) {
    const k = 8.0; // "pretend" views at average performance
    final v = c.viewCount.toDouble();
    final avgWatch = (c.watchSum + 0.45 * k) / (v + k);
    final completion = (c.completeCount + 0.25 * k) / (v + k);
    final actions = c.likeCount +
        2.0 * c.commentCount +
        3.0 * c.shareCount +
        1.5 * c.rewatchCount;
    // Likes from before views were counted can outnumber views; the cap
    // keeps that from going wild.
    final engage = ((actions + 0.08 * k) / (v + k) / 0.35).clamp(0.0, 1.0);
    return (0.4 * avgWatch + 0.2 * completion + 0.4 * engage).clamp(0.0, 1.0);
  }

  /// How long a photo clip takes to "fully" view: 3s, plus 2s per extra photo.
  static double photoViewSeconds(ClipData c) =>
      3.0 + 2.0 * math.max(0, c.allPhotos.length - 1);

  static Future<_ClipViewer> _loadClipViewer(String uid) async {
    final results = await Future.wait([
      _getTaste(uid),
      _getFriendNames(uid),
      _firestore
          .collection('users')
          .doc(uid)
          .collection('creator_affinity')
          .get()
          .then<Map<String, double>>((snap) {
        final now = DateTime.now();
        return {for (final d in snap.docs) d.id: _decayed(d.data(), now)};
      }).catchError((_) => <String, double>{}),
      _firestore
          .collection('users')
          .doc(uid)
          .collection('clip_views')
          .orderBy('at', descending: true)
          .limit(500)
          .get()
          .then<Map<String, double>>((snap) => {
        for (final d in snap.docs)
          d.id: ((d.data()['best'] ?? d.data()['fraction']) as num?)
              ?.toDouble() ??
              0,
      })
          .catchError((_) => <String, double>{}),
    ]);
    final friendNames = results[1] as Map<String, String>;
    final fof = await friendsOfFriends();
    return _ClipViewer(
      results[0] as Map<String, double>,
      friendNames.keys.toSet(),
      results[2] as Map<String, double>,
      results[3] as Map<String, double>,
      friendNames,
      {for (final e in fof.via.entries) e.key: e.value.length},
    );
  }

  static FriendsOfFriends? _fof;
  static String? _fofFor;
  static DateTime? _fofAt;
  static Future<FriendsOfFriends>? _fofLoading;

  /// Friends of your friends (mutual friends), cached for 10 minutes.
  /// Used by Search ("Alex knows them"), and by both feeds: their clips and
  /// the Dailies they're in get a social boost, a little under your own
  /// friends'.
  static Future<FriendsOfFriends> friendsOfFriends() {
    final uid = _uid;
    if (uid == null) return Future.value(const FriendsOfFriends({}, {}));
    final fresh = _fof != null &&
        _fofFor == uid &&
        _fofAt != null &&
        DateTime.now().difference(_fofAt!) < const Duration(minutes: 10);
    if (fresh) return Future.value(_fof!);
    return _fofLoading ??= _loadFriendsOfFriends(uid).then((v) {
      _fof = v;
      _fofFor = uid;
      _fofAt = DateTime.now();
      _fofLoading = null;
      return v;
    }).catchError((e) {
      _fofLoading = null;
      print('FeedService: friends of friends error: $e');
      return const FriendsOfFriends({}, {});
    });
  }

  /// Forget the cached mutual friends (after adding/removing a friend).
  static void clearFriendsOfFriends() {
    _fof = null;
    _fofAt = null;
  }

  static Future<FriendsOfFriends> _loadFriendsOfFriends(String uid) async {
    final names = await _getFriendNames(uid);
    final friends = names.keys.toList();
    final via = <String, Set<String>>{};
    final col = _firestore.collection('friend_requests');
    // Up to 90 friends looked at (3 rounds of 2 queries).
    for (final chunk in _chunk(friends.take(90).toList(), 30)) {
      final res = await Future.wait([
        col
            .where('status', isEqualTo: 'accepted')
            .where('fromUserId', whereIn: chunk)
            .get(),
        col
            .where('status', isEqualTo: 'accepted')
            .where('toUserId', whereIn: chunk)
            .get(),
      ]);
      for (final d in res[0].docs) {
        final friend = d.data()['fromUserId'] as String?;
        final other = d.data()['toUserId'] as String?;
        if (friend != null && other != null) {
          via.putIfAbsent(other, () => {}).add(friend);
        }
      }
      for (final d in res[1].docs) {
        final friend = d.data()['toUserId'] as String?;
        final other = d.data()['fromUserId'] as String?;
        if (friend != null && other != null) {
          via.putIfAbsent(other, () => {}).add(friend);
        }
      }
    }
    via.remove(uid);
    for (final f in friends) {
      via.remove(f);
    }
    via.removeWhere((k, _) => SafetyService.instance.isHidden(k));
    return FriendsOfFriends(via, names);
  }

  /// The For You clips feed (no labels). Kept for older callers; the Clips
  /// tab uses [getClipFeedPage].
  static Future<List<ClipData>> getClipFeed({
    Set<String> exclude = const {},
    int limit = 40,
  }) async {
    return (await getClipFeedPage(exclude: exclude, limit: limit)).clips;
  }

  /// One page of the Clips feed for [lens], skipping anything in [exclude]
  /// (what's already on screen). Call again with everything shown so far in
  /// [exclude] to load more.
  ///
  /// For You: the main ranked feed, where clips friends liked get a boost
  /// and a "liked by" label.
  ///
  /// Friends / a Daily / a group chat: clips people there liked or posted,
  /// most-liked-by-the-group first. Once those run out the page continues
  /// with For You clips like them ([ClipFeedPage.firstMoreId] marks where).
  static Future<ClipFeedPage> getClipFeedPage({
    ClipLens lens = ClipLens.forYou,
    Set<String> exclude = const {},
    int limit = 40,
  }) async {
    final uid = _uid;
    if (uid == null) return const ClipFeedPage([], {});
    final viewer = await _loadClipViewer(uid);
    if (lens.isForYou) return _forYouPage(uid, viewer, exclude, limit);

    final members = await _lensMembers(uid, lens);
    final hits = await _lensHits(uid, members);
    final place = lens.kind == 'friends' ? null : lens.label;

    final rows = <_ClipRow>[];
    final proof = <String, ClipProof>{};
    final now = DateTime.now();
    for (final h in hits.values) {
      if (exclude.contains(h.clip.id) || h.clip.creatorUid == uid) continue;
      if (_safetySkips(h.clip.id, h.clip.creatorUid, null)) continue;
      final likers = h.likers.toList();
      final lastAt = h.lastLikeAt ?? h.clip.createdAt;
      final recency = math.exp(-now.difference(lastAt).inHours / 24.0 / 5);
      var score = 0.40 * math.min(1.0, likers.length / 3) +
          0.15 * (members.containsKey(h.clip.creatorUid) ? 1.0 : 0.0) +
          0.25 * clipQuality(h.clip) +
          0.20 * recency +
          _noise();
      // Already watched: still show it (small groups run out fast), later.
      if (viewer.seen.containsKey(h.clip.id)) score *= 0.6;
      rows.add(_ClipRow(h.clip, score, 1, 1)); // 1s: never "exploration"
      if (likers.isNotEmpty) {
        proof[h.clip.id] = ClipProof(
          names: likers.map((u) => members[u] ?? '').where((n) => n.isNotEmpty).toList(),
          count: likers.length,
          place: place,
        );
      }
    }
    rows.sort((a, b) => b.score.compareTo(a.score));
    final lensClips = _orderClips(rows).take(limit).toList();
    if (lensClips.length >= limit) return ClipFeedPage(lensClips, proof);

    // "More like this": For You clips on the same topics / by the same
    // creators as everything this group liked or posted.
    final termCounts = <String, int>{};
    final creators = <String>{};
    for (final h in hits.values) {
      creators.add(h.clip.creatorUid);
      for (final t in h.clip.terms.take(8)) {
        termCounts[t] = (termCounts[t] ?? 0) + 1;
      }
    }
    final boostTerms = (termCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)))
        .take(10)
        .map((e) => e.key)
        .toSet();
    creators.remove(uid);
    final more = await _forYouPage(
      uid,
      viewer,
      {...exclude, ...lensClips.map((c) => c.id)},
      limit - lensClips.length,
      boostTerms: boostTerms,
      boostCreators: creators,
    );
    return ClipFeedPage(
      [...lensClips, ...more.clips],
      {...more.proof, ...proof},
      firstMoreId: more.clips.isEmpty ? null : more.clips.first.id,
    );
  }

  /// Clips nobody should see here: taken down (moderation / reports),
  /// "not promoted" by moderation (still on the creator's profile, never
  /// recommended), "Not interested", or from someone blocked (either way)
  /// or muted.
  static bool _safetySkips(
      String clipId, String creatorUid, Map<String, dynamic>? data) {
    final s = SafetyService.instance;
    if (data != null && (data['hidden'] == true || data['limited'] == true)) {
      return true;
    }
    if (s.notInterested.contains(clipId)) return true;
    return creatorUid.isNotEmpty && s.hidesCreator(creatorUid);
  }

  static Future<ClipFeedPage> _forYouPage(
      String uid,
      _ClipViewer viewer,
      Set<String> exclude,
      int limit, {
        Set<String> boostTerms = const {},
        Set<String> boostCreators = const {},
      }) async {
    final col = _firestore.collection('clips');

    final likedCreators = (viewer.affinity.entries
        .where((e) => e.value > 0 && e.key != uid)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value)))
        .take(10)
        .map((e) => e.key)
        .toList();
    final friends = viewer.friends.take(30).toList();
    final terms = _topTerms(viewer.taste);
    final moreTerms = boostTerms.take(10).toList();
    final moreCreators = boostCreators.take(30).toList();
    // People your friends know (most mutual friends first).
    final fofCreators = (viewer.fof.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)))
        .take(10)
        .map((e) => e.key)
        .toList();

    final results = await Future.wait([
      _friendLikes(friends), // clipId -> friend uids who liked it
      _safe('clips-recent', () => col
          .orderBy('createdAt', descending: true)
          .limit(120)
          .get()),
      _safe('clips-popular', () => col
          .orderBy('likeCount', descending: true)
          .limit(_clipSourceLimit)
          .get()),
      if (likedCreators.isNotEmpty)
        _safe('clips-creators', () => col
            .where('creatorUid', whereIn: likedCreators)
            .orderBy('createdAt', descending: true)
            .limit(_clipSourceLimit)
            .get()),
      if (friends.isNotEmpty)
        _safe('clips-friends', () => col
            .where('creatorUid', whereIn: friends)
            .orderBy('createdAt', descending: true)
            .limit(_clipSourceLimit)
            .get()),
      if (terms.isNotEmpty)
        _safe('clips-topics', () => col
            .where('terms', arrayContainsAny: terms)
            .limit(_clipSourceLimit)
            .get()),
      if (moreTerms.isNotEmpty)
        _safe('clips-like-these', () => col
            .where('terms', arrayContainsAny: moreTerms)
            .limit(_clipSourceLimit)
            .get()),
      if (moreCreators.isNotEmpty)
        _safe('clips-same-creators', () => col
            .where('creatorUid', whereIn: moreCreators)
            .orderBy('createdAt', descending: true)
            .limit(_clipSourceLimit)
            .get()),
      if (fofCreators.isNotEmpty)
        _safe('clips-friends-of-friends', () => col
            .where('creatorUid', whereIn: fofCreators)
            .orderBy('createdAt', descending: true)
            .limit(_clipSourceLimit)
            .get()),
    ]);

    final friendLikes = results[0] as Map<String, Set<String>>;
    final byId = <String, ClipData>{};
    void addDoc(DocumentSnapshot<Map<String, dynamic>> d) {
      final data = d.data();
      if (data == null || byId.containsKey(d.id) || exclude.contains(d.id)) {
        return;
      }
      if (data['creatorUid'] == uid) return;
      if (_safetySkips(d.id, data['creatorUid'] as String? ?? '', data)) return;
      try {
        byId[d.id] = ClipData.fromFirestore(data, d.id);
      } catch (e) {
        print('FeedService: skipping unreadable clip ${d.id}: $e');
      }
    }

    for (final list in results.skip(1)) {
      for (final d in list as List<QueryDocumentSnapshot<Map<String, dynamic>>>) {
        addDoc(d);
      }
    }
    // Clips friends liked that no other source found.
    final missing = friendLikes.keys
        .where((id) => !byId.containsKey(id) && !exclude.contains(id))
        .take(30)
        .toList();
    for (final d in await _clipsByIds(missing)) {
      addDoc(d);
    }

    final fresh = <ClipData>[];
    final seen = <ClipData>[];
    for (final c in byId.values) {
      (viewer.seen.containsKey(c.id) ? seen : fresh).add(c);
    }

    final ordered = _orderClips(_scoreClips(fresh, viewer,
        friendLikes: friendLikes,
        boostTerms: boostTerms,
        boostCreators: boostCreators));
    if (ordered.length < limit && seen.isNotEmpty) {
      // Least-watched first: the ones they barely got to see.
      seen.sort((a, b) =>
          (viewer.seen[a.id] ?? 0).compareTo(viewer.seen[b.id] ?? 0));
      ordered.addAll(seen.take(limit - ordered.length));
    }
    final page = ordered.take(limit).toList();

    final proof = <String, ClipProof>{};
    for (final c in page) {
      final likers = friendLikes[c.id];
      if (likers == null || likers.isEmpty) continue;
      proof[c.id] = ClipProof(
        names: likers
            .map((u) => viewer.friendNames[u] ?? '')
            .where((n) => n.isNotEmpty)
            .toList(),
        count: likers.length,
      );
    }
    return ClipFeedPage(page, proof);
  }

  /// Best-first order of the given clips for this user (Search uses this).
  static Future<List<String>> rankClipIds(List<ClipData> clips) async {
    final uid = _uid;
    if (uid == null || clips.isEmpty) return clips.map((c) => c.id).toList();
    final viewer = await _loadClipViewer(uid);
    return _orderClips(_scoreClips(clips, viewer)).map((c) => c.id).toList();
  }

  static List<_ClipRow> _scoreClips(
      List<ClipData> clips,
      _ClipViewer v, {
        Map<String, Set<String>> friendLikes = const {},
        Set<String> boostTerms = const {},
        Set<String> boostCreators = const {},
      }) {
    final now = DateTime.now();
    return clips.map((c) {
      final interest = _termInterest(c.terms, v.taste);
      final aff = ((v.affinity[c.creatorUid] ?? 0) / _tasteCap).clamp(-1.0, 1.0);
      // Friend posted it, or friends liked it (2+ likes = full).
      final likedBy = friendLikes[c.id]?.length ?? 0;
      // Someone your friends know: a smaller boost (more mutuals = more).
      final mutual = v.fof[c.creatorUid] ?? 0;
      final mutualBoost = mutual > 0 ? math.min(0.6, 0.3 + 0.1 * mutual) : 0.0;
      final social = math.max(
          math.max(v.friends.contains(c.creatorUid) ? 1.0 : 0.0,
              math.min(1.0, likedBy / 2)),
          mutualBoost);
      final ageDays = now.difference(c.createdAt).inHours / 24.0;
      final recency = math.exp(-ageDays / 4); // about half after 3 days
      final quality = clipQuality(c);

      var score = _cQuality * quality +
          _cInterest * interest +
          _cCreator * math.max(0.0, aff) +
          _cRecency * recency +
          _cFriend * social;
      // "More like this" after a group's clips: lean toward what they liked.
      if (boostTerms.isNotEmpty || boostCreators.isNotEmpty) {
        final overlap = c.terms.where(boostTerms.contains).length;
        score += 0.15 * math.min(1.0, overlap / 3) +
            (boostCreators.contains(c.creatorUid) ? 0.10 : 0.0);
      }
      if (aff < -0.5 || _termsStronglyDisliked(c.terms, v.taste)) {
        score *= 0.5;
      }
      score += _noise();
      return _ClipRow(c, score, interest, aff);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  /// No same creator twice in a row; every 5th slot explores (a random one
  /// of the best few clips outside the viewer's topics and creators).
  static List<ClipData> _orderClips(List<_ClipRow> rows) {
    final remaining = List.of(rows);
    final out = <ClipData>[];
    final recentCreators = <String>[];
    while (remaining.isNotEmpty) {
      var pick = 0;
      var explored = false;
      if (out.length % _explorationEvery == _explorationEvery - 1) {
        final pool = <int>[];
        for (var i = 0; i < remaining.length && pool.length < 8; i++) {
          if (remaining[i].interest < 0.2 && remaining[i].aff <= 0) pool.add(i);
        }
        if (pool.isNotEmpty) {
          pick = pool[_rng.nextInt(pool.length)];
          explored = true;
        }
      }
      if (!explored) {
        var best = -double.infinity;
        for (var i = 0; i < math.min(8, remaining.length); i++) {
          final adj = remaining[i].score -
              (recentCreators.contains(remaining[i].clip.creatorUid) ? 0.12 : 0.0);
          if (adj > best) {
            best = adj;
            pick = i;
          }
        }
      }
      final chosen = remaining.removeAt(pick);
      recentCreators.add(chosen.clip.creatorUid);
      if (recentCreators.length > 2) recentCreators.removeAt(0);
      out.add(chosen.clip);
    }
    return out;
  }

  // ─── Lenses: Friends, a Daily, a group chat ─────────────────────────────────

  /// The Clips switcher: For You, Friends, then the user's 3 most recently
  /// used Dailies and 3 most active group chats (only ones with other
  /// people in them).
  static Future<List<ClipLens>> getClipLenses() async {
    final uid = _uid;
    final out = <ClipLens>[ClipLens.forYou, ClipLens.friends];
    if (uid == null) return out;

    final results = await Future.wait([
      _firestore
          .collection('daily_interactions')
          .where('userId', isEqualTo: uid)
          .get()
          .then<Map<String, DateTime>>((snap) => {
        for (final d in snap.docs)
          if (d.data()['dailyId'] is String &&
              d.data()['timestamp'] is Timestamp)
            d.data()['dailyId'] as String:
            (d.data()['timestamp'] as Timestamp).toDate(),
      })
          .catchError((_) => <String, DateTime>{}),
      _firestore
          .collection('groupChats')
          .where('memberIds', arrayContains: uid)
          .get()
          .then<List<GroupChat>>(
              (snap) => snap.docs.map(GroupChat.fromDoc).toList())
          .catchError((_) => <GroupChat>[]),
    ]);

    final lastUsed = results[0] as Map<String, DateTime>;
    final dailies = List<DailyData>.from(DailyList.dailies)
      ..sort((a, b) => (lastUsed[b.id] ?? b.createdAt)
          .compareTo(lastUsed[a.id] ?? a.createdAt));
    for (final d in dailies.take(3)) {
      out.add(ClipLens('daily', d.id, d.title));
    }

    final chats = (results[1] as List<GroupChat>)
        .where((g) => g.memberIds.where((m) => m != uid).isNotEmpty)
        .toList()
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    for (final g in chats.take(3)) {
      out.add(ClipLens('chat', g.id, g.displayName(uid)));
    }
    return out;
  }

  static final Map<String, Map<String, String>> _memberCache = {};
  static final Map<String, DateTime> _memberCacheAt = {};

  /// uid -> username of the people in a lens (never including the viewer),
  /// at most 60: friends; everyone in a group chat; a Daily's members and
  /// recent posters, most active first. Cached for 5 minutes.
  static Future<Map<String, String>> _lensMembers(
      String uid, ClipLens lens) async {
    final at = _memberCacheAt[lens.key];
    if (at != null && DateTime.now().difference(at).inMinutes < 5) {
      return _memberCache[lens.key]!;
    }
    var members = <String, String>{};
    try {
      if (lens.kind == 'friends') {
        members = await _getFriendNames(uid);
      } else if (lens.kind == 'chat') {
        final doc = await _firestore.collection('groupChats').doc(lens.id).get();
        if (doc.exists) members = Map.of(GroupChat.fromDoc(doc).memberUsernames);
      } else if (lens.kind == 'daily') {
        members = await _dailyMembers(lens.id);
      }
    } catch (e) {
      print('FeedService: lens members error: $e');
    }
    members.remove(uid);
    final capped = Map.fromEntries(members.entries.take(60));
    _memberCache[lens.key] = capped;
    _memberCacheAt[lens.key] = DateTime.now();
    return capped;
  }

  /// A Daily's people: recent posters (most posts first), then accepted
  /// members, then the creator.
  static Future<Map<String, String>> _dailyMembers(String dailyId) async {
    final postCounts = <String, int>{};
    final names = <String, String>{};
    final results = await Future.wait([
      _safe('daily-posters', () => _firestore
          .collection('dailies')
          .doc(dailyId)
          .collection('daily_messages')
          .orderBy('timestamp', descending: true)
          .limit(150)
          .get()),
      _safe('daily-members', () => _firestore
          .collection('daily_invitations')
          .where('dailyId', isEqualTo: dailyId)
          .limit(150)
          .get()),
    ]);
    for (final d in results[0]) {
      final u = d.data()['user_id'] as String?;
      if (u == null) continue;
      postCounts[u] = (postCounts[u] ?? 0) + 1;
      final n = d.data()['username'] as String?;
      if (n != null && n.isNotEmpty && n != 'You') names[u] = n;
    }
    for (final d in results[1]) {
      if (d.data()['status'] != 'accepted') continue;
      final u = d.data()['toUserId'] as String?;
      if (u == null) continue;
      postCounts.putIfAbsent(u, () => 0);
      final n = d.data()['toUsername'] as String?;
      if (n != null && n.isNotEmpty) names.putIfAbsent(u, () => n);
    }
    for (final d in DailyList.dailies) {
      if (d.id == dailyId && d.creatorUid != null) {
        postCounts.putIfAbsent(d.creatorUid!, () => 0);
      }
    }
    final ranked = postCounts.keys.toList()
      ..sort((a, b) => postCounts[b]!.compareTo(postCounts[a]!));
    return {for (final u in ranked) u: names[u] ?? ''};
  }

  /// Every clip the [members] liked lately or posted lately.
  static Future<Map<String, _LensHit>> _lensHits(
      String uid, Map<String, String> members) async {
    final ids = members.keys.toList();
    if (ids.isEmpty) return {};
    final hits = <String, _LensHit>{};
    final likers = <String, Set<String>>{};
    final lastLike = <String, DateTime>{};

    final futures = <Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>[];
    final chunks = _chunk(ids, 30);
    for (final chunk in chunks) {
      futures.add(_safe('lens-likes', () => _firestore
          .collection('clip_likes')
          .where('uid', whereIn: chunk)
          .orderBy('likedAt', descending: true)
          .limit(80)
          .get()));
    }
    for (final chunk in chunks) {
      futures.add(_safe('lens-posted', () => _firestore
          .collection('clips')
          .where('creatorUid', whereIn: chunk)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get()));
    }
    final results = await Future.wait(futures);

    for (final d in results.take(chunks.length).expand((l) => l)) {
      final clipId = d.data()['clipId'] as String?;
      final who = d.data()['uid'] as String?;
      if (clipId == null || who == null) continue;
      likers.putIfAbsent(clipId, () => {}).add(who);
      final ts = d.data()['likedAt'];
      if (ts is Timestamp) {
        final t = ts.toDate();
        if (lastLike[clipId] == null || t.isAfter(lastLike[clipId]!)) {
          lastLike[clipId] = t;
        }
      }
    }
    for (final d in results.skip(chunks.length).expand((l) => l)) {
      if (d.data()['hidden'] == true) continue;
      try {
        hits[d.id] = _LensHit(ClipData.fromFirestore(d.data(), d.id));
      } catch (_) {}
    }
    final missing =
    likers.keys.where((id) => !hits.containsKey(id)).take(90).toList();
    for (final d in await _clipsByIds(missing)) {
      final data = d.data();
      if (data == null || data['hidden'] == true) continue;
      try {
        hits[d.id] = _LensHit(ClipData.fromFirestore(data, d.id));
      } catch (_) {}
    }
    for (final e in likers.entries) {
      final h = hits[e.key];
      if (h == null) continue;
      h.likers.addAll(e.value);
      h.lastLikeAt = lastLike[e.key];
    }
    return hits;
  }

  /// clipId -> which of these friends liked it (their latest 100 likes).
  static Future<Map<String, Set<String>>> _friendLikes(
      List<String> friends) async {
    if (friends.isEmpty) return {};
    final out = <String, Set<String>>{};
    final docs = await _safe('friend-likes', () => _firestore
        .collection('clip_likes')
        .where('uid', whereIn: friends.take(30).toList())
        .orderBy('likedAt', descending: true)
        .limit(100)
        .get());
    for (final d in docs) {
      final clipId = d.data()['clipId'] as String?;
      final who = d.data()['uid'] as String?;
      if (clipId != null && who != null) {
        out.putIfAbsent(clipId, () => {}).add(who);
      }
    }
    return out;
  }

  static Future<List<DocumentSnapshot<Map<String, dynamic>>>> _clipsByIds(
      List<String> ids) async {
    final out = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final chunk in _chunk(ids, 30)) {
      out.addAll(await _safe('clips-by-id', () => _firestore
          .collection('clips')
          .where(FieldPath.documentId, whereIn: chunk)
          .get()));
    }
    return out;
  }

  // ─── Learning from clip behavior ────────────────────────────────────────────

  static final Map<String, List<String>> _clipTermCache = {};

  /// A clip stopped being on screen. [watched] is how much of it they saw:
  /// 1.0 = once through, 2.0 = watched it twice (for photos, time spent
  /// compared to [photoViewSeconds]). [seconds] is time on screen.
  ///
  /// Saves the view (it counts toward the clip's quality and marks it as
  /// seen) and teaches taste: a quick swipe away pushes the creator and
  /// topic down, watching most of it pulls them up, rewatching even more.
  static Future<void> recordClipView({
    required ClipData clip,
    required double watched,
    required double seconds,
  }) async {
    final uid = _uid;
    if (uid == null || clip.creatorUid == uid) return;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('clip_views')
          .doc(clip.id)
          .set({
        'clipId': clip.id,
        'creatorUid': clip.creatorUid,
        'fraction': watched.clamp(0.0, 1.0),
        'at': FieldValue.serverTimestamp(),
        'views': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      print('FeedService: recordClipView save error: $e');
    }

    double weight;
    if (seconds < 2) {
      weight = _clipWeights[ClipEvent.skipped]!;
    } else if (watched >= 1.8) {
      weight = 3; // rewatched
    } else if (watched >= 0.8) {
      weight = _clipWeights[ClipEvent.watched]!;
    } else if (watched >= 0.4) {
      weight = 0.75;
    } else {
      weight = 0;
    }
    if (weight != 0) {
      await _recordClipSignal(
          creatorUid: clip.creatorUid,
          weight: weight,
          clipId: clip.id,
          terms: clip.terms);
    }
  }

  /// Record a like, comment, share (or, from older code, watched/skipped).
  static Future<void> recordClipEvent({
    required String creatorUid,
    required ClipEvent event,
    String? clipId,
    List<String>? terms,
  }) {
    return _recordClipSignal(
      creatorUid: creatorUid,
      weight: _clipWeights[event] ?? 0,
      clipId: clipId,
      terms: terms,
    );
  }

  /// Teaches creator affinity (users/{uid}/creator_affinity/{creatorUid})
  /// and topic taste from the clip's keywords, in the same taste profile
  /// Dailies use, so liking superhero clips also lifts superhero Dailies.
  static Future<void> _recordClipSignal({
    required String creatorUid,
    required double weight,
    String? clipId,
    List<String>? terms,
  }) async {
    final uid = _uid;
    if (uid == null || weight == 0) return;

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
        print('FeedService: clip creator signal error: $e');
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
      print('FeedService: clip topic signal error: $e');
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