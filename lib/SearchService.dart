import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'FeedService.dart';
import 'clip_service.dart';
import 'user_service.dart';
import 'SafetyService.dart';
import 'Nearby.dart';

/// A Daily matched by a search, with how well it matched.
class DailySearchResult {
  final DailyData daily;
  final double score;
  const DailySearchResult(this.daily, this.score);
}

/// A person matched by a search (or suggested), with why they ranked.
class PersonResult {
  final KaidoseUser user;
  final bool isFriend;
  final int mutualCount; // friends you have in common
  final bool isVerified;
  final double score;

  /// Usernames of your friends who know them (A–Z).
  final List<String> knownBy;

  /// Found through "Near you".
  final bool nearby;

  const PersonResult({
    required this.user,
    required this.isFriend,
    required this.mutualCount,
    required this.isVerified,
    required this.score,
    this.knownBy = const [],
    this.nearby = false,
  });

  /// "Alex knows them" / "Alex and Sam know them" /
  /// "Alex, Sam and 10 others know them". Null with no mutual friends.
  String? get knownByLabel {
    final n = mutualCount;
    if (n <= 0) return null;
    final names = knownBy.take(2).toList();
    if (names.isEmpty) {
      return n == 1 ? '1 mutual friend' : '$n mutual friends';
    }
    if (n == 1) return '${names[0]} knows them';
    if (n == 2 && names.length == 2) return '${names[0]} and ${names[1]} know them';
    final rest = n - names.length;
    if (names.length == 1) {
      return '${names[0]} and $rest ${rest == 1 ? 'other' : 'others'} know them';
    }
    return rest == 1
        ? '${names[0]}, ${names[1]} and 1 other know them'
        : '${names[0]}, ${names[1]} and $rest others know them';
  }
}

class _DailyEntry {
  final DailyData daily;
  final List<String> terms;
  final double feedScore; // 0..1 from FeedService (taste, quality, social…)
  const _DailyEntry(this.daily, this.terms, this.feedScore);
}

class _PeopleContext {
  final List<KaidoseUser> users;
  final Set<String> friends;
  final Map<String, int> mutuals; // uid → friends in common
  final Set<String> verified;
  final FriendsOfFriends? fof; // who knows whom, for "Alex knows them"
  const _PeopleContext(this.users, this.friends, this.mutuals, this.verified,
      [this.fof]);
}

/// Ranking for the Search tab. Dailies are scored on how well they match the
/// text AND how well they fit this user's feed profile; people are scored on
/// the match AND how close they are (friends, then friends-of-friends, then
/// verified accounts) so results aren't "everyone in the world".
class SearchService {
  static const Duration _cacheFor = Duration(minutes: 2);

  // ─── Dailies ────────────────────────────────────────────────────────────────

  static Future<List<ScoredDaily>>? _poolFuture;
  static DateTime? _poolAt;

  static Future<List<ScoredDaily>> _pool() {
    final fresh = _poolAt != null &&
        DateTime.now().difference(_poolAt!) < _cacheFor &&
        _poolFuture != null;
    if (!fresh) {
      _poolAt = DateTime.now();
      _poolFuture = FeedService.getRankedFeed().catchError((e) {
        print('SearchService: pool error: $e');
        _poolAt = null;
        return <ScoredDaily>[];
      });
    }
    return _poolFuture!;
  }

  /// Forget cached results (call after the user joins/leaves something).
  static void invalidate() {
    FeedService.clearFriendsOfFriends();
    _poolFuture = null;
    _poolAt = null;
    _peopleFuture = null;
    _peopleAt = null;
    _clipPoolFuture = null;
    _clipPoolAt = null;
  }

  /// Dailies worth showing before the user types: the top of their feed,
  /// excluding ones they're already in.
  static Future<List<DailySearchResult>> suggestedDailies(
      {int limit = 8}) async {
    final pool = await _pool();
    final mine = DailyList.dailies.map((d) => d.id).toSet();
    return pool
        .where((s) => !mine.contains(s.daily.id))
        .take(limit)
        .map((s) => DailySearchResult(s.daily, s.score))
        .toList();
  }

  static Future<List<DailySearchResult>> searchDailies(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return suggestedDailies();

    final qTerms = FeedService.queryTerms(q);
    final pool = await _pool();

    final entries = <String, _DailyEntry>{
      for (final s in pool) s.daily.id: _DailyEntry(s.daily, s.terms, s.score),
    };
    // My own copy wins (it has local icon paths etc.), keeping feed data.
    for (final d in DailyList.dailies) {
      final old = entries[d.id];
      entries[d.id] = _DailyEntry(d, old?.terms ?? const [], old?.feedScore ?? 0.3);
    }
    // Anything the ranked pool didn't reach: ask Firestore directly.
    for (final hit in await _serverSearch(q, qTerms)) {
      entries.putIfAbsent(hit.daily.id, () => hit);
    }

    final out = <DailySearchResult>[];
    for (final e in entries.values) {
      final rel = _relevance(e, q, qTerms);
      if (rel <= 0) continue;
      out.add(DailySearchResult(e.daily, 0.65 * rel + 0.35 * e.feedScore));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  static Future<List<_DailyEntry>> _serverSearch(
      String q, List<String> qTerms) async {
    final col = FirebaseFirestore.instance.collection('public_dailies');
    final titleCase = q
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> safe(
        Future<QuerySnapshot<Map<String, dynamic>>> Function() run) async {
      try {
        return (await run()).docs;
      } catch (e) {
        print('SearchService: server query failed: $e');
        return [];
      }
    }

    final lists = await Future.wait([
      if (qTerms.isNotEmpty)
        safe(() => col
            .where('terms', arrayContainsAny: qTerms.take(10).toList())
            .limit(20)
            .get()),
      for (final v in {q, titleCase})
        safe(() => col
            .orderBy('title')
            .startAt([v])
            .endAt(['$v'])
            .limit(20)
            .get()),
    ]);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final out = <_DailyEntry>[];
    final seen = <String>{};
    for (final d in lists.expand((l) => l)) {
      if (!seen.add(d.id)) continue;
      try {
        final daily = DailyData.fromFirestore(d);
        if (uid != null && daily.creatorUid == uid) continue;
        final raw = d.data()['terms'];
        out.add(_DailyEntry(
            daily, raw is List ? raw.whereType<String>().toList() : const [], 0.1));
      } catch (_) {}
    }
    return out;
  }

  /// 0..1: how well a Daily matches the typed text.
  static double _relevance(_DailyEntry e, String q, List<String> qTerms) {
    final title = e.daily.title.toLowerCase();
    final desc = e.daily.description.toLowerCase();
    final tags = e.daily.keywords.map((t) => t.toLowerCase()).toList();
    final terms = e.terms;

    double best = 0;
    void hit(double v) {
      if (v > best) best = v;
    }

    if (title == q) hit(1.0);
    if (title.startsWith(q)) hit(0.95);
    if (title.contains(' $q')) hit(0.88);
    if (title.contains(q)) hit(0.8);
    if (tags.any((t) => t == q)) hit(0.7);
    if (tags.any((t) => t.contains(q))) hit(0.6);
    if (terms.any((t) => t == q || qTerms.contains(t))) hit(0.7);
    if (terms.any((t) => t.startsWith(q))) hit(0.55);
    if (desc.contains(q)) hit(0.4);

    // Multi-word: reward Dailies where every word shows up somewhere.
    if (qTerms.length > 1) {
      final haystack = '$title $desc ${tags.join(' ')} ${terms.join(' ')}';
      final found = qTerms.where(haystack.contains).length;
      if (found == qTerms.length) hit(0.65);
      else if (found > 0) hit(0.25 * found / qTerms.length);
    }
    return best;
  }

  // ─── People ─────────────────────────────────────────────────────────────────

  static Future<_PeopleContext>? _peopleFuture;
  static DateTime? _peopleAt;

  static Future<_PeopleContext> _people() {
    final fresh = _peopleAt != null &&
        DateTime.now().difference(_peopleAt!) < _cacheFor &&
        _peopleFuture != null;
    if (!fresh) {
      _peopleAt = DateTime.now();
      _peopleFuture = _loadPeople().catchError((e) {
        print('SearchService: people error: $e');
        _peopleAt = null;
        return const _PeopleContext([], {}, {}, {});
      });
    }
    return _peopleFuture!;
  }

  /// Only the people this user has a connection to are loaded: friends,
  /// friends of friends, and verified accounts. Nobody else's profile is
  /// downloaded until a typed search finds them by name (see [searchPeople]).
  static Future<_PeopleContext> _loadPeople() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final results = await Future.wait([
      FeedService.getFriendUids(),
      _verifiedUsers(),
    ]);
    final friends = (results[0] as List<String>).toSet();
    final verifiedUsers = results[1] as List<KaidoseUser>;
    final verified = verifiedUsers.map((u) => u.uid).toSet();
    final fof = await FeedService.friendsOfFriends();
    final mutuals = {for (final e in fof.via.entries) e.key: e.value.length};

    // Friends, plus the friends-of-friends with the most mutuals.
    final topMutuals = (mutuals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)))
        .take(60)
        .map((e) => e.key);
    final known = <String, KaidoseUser>{
      for (final u in verifiedUsers) u.uid: u,
    };
    final toFetch = {...friends, ...topMutuals}
        .where((id) => !known.containsKey(id))
        .toList();
    for (final u in await _usersByIds(toFetch)) {
      known[u.uid] = u;
    }
    known.remove(me);
    return _PeopleContext(
        known.values.toList(), friends, mutuals, verified, fof);
  }

  /// User profiles by uid, 30 per query.
  static Future<List<KaidoseUser>> _usersByIds(List<String> ids) async {
    final out = <KaidoseUser>[];
    final col = FirebaseFirestore.instance.collection('users');
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      try {
        final snap = await col.where(FieldPath.documentId, whereIn: chunk).get();
        for (final d in snap.docs) {
          final data = Map<String, dynamic>.from(d.data());
          data['uid'] ??= d.id;
          out.add(KaidoseUser.fromFirestore(data));
        }
      } catch (e) {
        print('SearchService: user lookup failed: $e');
      }
    }
    return out;
  }

  /// Accounts flagged `verified: true` on their user doc. (The verification
  /// system itself comes later; this just reads the flag.)
  static Future<List<KaidoseUser>> _verifiedUsers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('verified', isEqualTo: true)
          .limit(100)
          .get();
      return snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['uid'] ??= d.id;
        return KaidoseUser.fromFirestore(data);
      }).toList();
    } catch (e) {
      print('SearchService: verified lookup failed: $e');
      return [];
    }
  }

  /// Uids of anyone whose username starts with [q], looked up on the
  /// server (usernames/{lowercased name}), at most 25.
  static Future<List<String>> _uidsByNamePrefix(String q) async {
    final key = Uri.encodeComponent(q.toLowerCase()).toLowerCase();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usernames')
          .orderBy(FieldPath.documentId)
          .startAt([key])
          .endAt(['$key\uf8ff'])
          .limit(25)
          .get();
      return snap.docs
          .map((d) => d.data()['uid'] as String?)
          .whereType<String>()
          .toList();
    } catch (e) {
      print('SearchService: username lookup failed: $e');
      return [];
    }
  }

  static double _closeness(bool friend, int mutual, bool verified) {
    if (friend) return 1.0;
    final m = mutual > 0 ? 0.4 + 0.12 * mutual.clamp(0, 5) : 0.0;
    final v = verified ? 0.5 : 0.0;
    return m > v ? m : v;
  }

  static PersonResult _person(_PeopleContext c, KaidoseUser u, double match) {
    final friend = c.friends.contains(u.uid);
    final mutual = c.mutuals[u.uid] ?? 0;
    final verified = c.verified.contains(u.uid);
    return PersonResult(
      user: u,
      isFriend: friend,
      mutualCount: mutual,
      isVerified: verified,
      score: 0.55 * match + 0.45 * _closeness(friend, mutual, verified),
      knownBy: friend ? const [] : (c.fof?.namesFor(u.uid) ?? const []),
    );
  }

  /// People near you (same area, roughly a city) who also turned on
  /// "Near you" in Search. Most mutual friends first. Empty if you haven't
  /// turned it on.
  static Future<List<PersonResult>> nearbyPeople({int limit = 15}) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return [];
    final cell = await NearbyService.myCell();
    if (cell == null) return [];
    final c = await _people();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('geoCell', isEqualTo: cell)
          .where('nearbyVisible', isEqualTo: true)
          .limit(60)
          .get();
      final out = <PersonResult>[];
      for (final d in snap.docs) {
        if (d.id == me || c.friends.contains(d.id)) continue;
        if (SafetyService.instance.isHidden(d.id)) continue;
        final data = Map<String, dynamic>.from(d.data());
        data['uid'] ??= d.id;
        final u = KaidoseUser.fromFirestore(data);
        final p = _person(c, u, 1);
        out.add(PersonResult(
          user: p.user,
          isFriend: false,
          mutualCount: p.mutualCount,
          isVerified: p.isVerified,
          score: p.score,
          knownBy: p.knownBy,
          nearby: true,
        ));
      }
      out.sort((a, b) => b.mutualCount != a.mutualCount
          ? b.mutualCount.compareTo(a.mutualCount)
          : b.score.compareTo(a.score));
      return out.take(limit).toList();
    } catch (e) {
      print('SearchService: nearby error: $e');
      return [];
    }
  }

  /// Your accepted friends, A–Z.
  static Future<List<PersonResult>> myFriends() async {
    final c = await _people();
    final out = c.users
        .where((u) => c.friends.contains(u.uid))
        .map((u) => _person(c, u, 1))
        .toList()
      ..sort((a, b) => a.user.username
          .toLowerCase()
          .compareTo(b.user.username.toLowerCase()));
    return out;
  }

  /// People you may know: friends-of-friends (most mutuals first), then
  /// verified accounts. Never strangers with no connection.
  static Future<List<PersonResult>> suggestedPeople({int limit = 10}) async {
    final c = await _people();
    final out = c.users
        .where((u) =>
    !c.friends.contains(u.uid) &&
        !SafetyService.instance.isHidden(u.uid) &&
        ((c.mutuals[u.uid] ?? 0) > 0 || c.verified.contains(u.uid)))
        .map((u) => _person(c, u, 1))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return out.take(limit).toList();
  }

  /// Typed search. Anyone whose name STARTS with what's typed can be found
  /// (looked up on the server, never by downloading everyone); people you're
  /// connected to also match anywhere in their name. Friends,
  /// friends-of-friends and verified accounts sort above strangers.
  static Future<List<PersonResult>> searchPeople(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return suggestedPeople();
    final me = FirebaseAuth.instance.currentUser?.uid;
    final c = await _people();

    final pool = <String, KaidoseUser>{for (final u in c.users) u.uid: u};
    final newIds = (await _uidsByNamePrefix(q))
        .where((id) => id != me && !pool.containsKey(id))
        .toList();
    for (final u in await _usersByIds(newIds)) {
      pool[u.uid] = u;
    }

    final out = <PersonResult>[];
    for (final u in pool.values) {
      // Blocked either way: they can't find each other.
      if (SafetyService.instance.isHidden(u.uid)) continue;
      final name = u.username.toLowerCase();
      double match = 0;
      if (name == q) {
        match = 1.0;
      } else if (name.startsWith(q)) {
        match = 0.9;
      } else if (name.contains(' $q') || name.contains('_$q') || name.contains('.$q')) {
        match = 0.75;
      } else if (name.contains(q)) {
        match = 0.55;
      }
      if (match > 0) out.add(_person(c, u, match));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  // ─── Clips ──────────────────────────────────────────────────────────────────

  static Future<List<ClipData>>? _clipPoolFuture;
  static DateTime? _clipPoolAt;
  static Map<String, int> _clipRank = {};

  /// Recent clips from other people, plus how this user's feed would order
  /// them (taste, creators they like, friends, recency).
  static Future<List<ClipData>> _clipPool() {
    final fresh = _clipPoolAt != null &&
        DateTime.now().difference(_clipPoolAt!) < _cacheFor &&
        _clipPoolFuture != null;
    if (!fresh) {
      _clipPoolAt = DateTime.now();
      _clipPoolFuture = _loadClipPool().catchError((e) {
        print('SearchService: clip pool error: $e');
        _clipPoolAt = null;
        return <ClipData>[];
      });
    }
    // Blocked / muted creators and "Not interested" clips never show.
    return _clipPoolFuture!.then((l) => l.where(_clipOk).toList());
  }

  static bool _clipOk(ClipData c) =>
      !SafetyService.instance.notInterested.contains(c.id) &&
          !SafetyService.instance.hidesCreator(c.creatorUid);

  static Future<List<ClipData>> _loadClipPool() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final snap = await FirebaseFirestore.instance
        .collection('clips')
        .orderBy('createdAt', descending: true)
        .limit(150)
        .get();
    final clips = snap.docs
        .where((d) =>
    d.data()['creatorUid'] != me && d.data()['hidden'] != true)
        .map((d) => ClipData.fromFirestore(d.data(), d.id))
        .toList();
    final order = await FeedService.rankClipIds(clips);
    _clipRank = {for (var i = 0; i < order.length; i++) order[i]: i};
    return clips;
  }

  /// True once the feed has learned anything about this user. Before that,
  /// "suggested" clips are really just the latest ones.
  static Future<bool> hasFeedTaste() async {
    try {
      return (await FeedService.getTopTopics(limit: 1)).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Clips for the empty search box: the top of this user's clip ranking.
  static Future<List<ClipData>> suggestedClips({int limit = 18}) async {
    final pool = await _clipPool();
    final sorted = List<ClipData>.from(pool)
      ..sort((a, b) =>
          (_clipRank[a.id] ?? 1 << 30).compareTo(_clipRank[b.id] ?? 1 << 30));
    return sorted.take(limit).toList();
  }

  /// Clips matching the typed text — caption first, then the generated
  /// keywords — blended with how well each fits the user's feed.
  static Future<List<ClipData>> searchClips(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return suggestedClips();
    final qTerms = FeedService.queryTerms(q);
    final pool = await _clipPool();
    final me = FirebaseAuth.instance.currentUser?.uid;

    final byId = {for (final c in pool) c.id: c};
    // Older clips the recent pool didn't reach, found by keyword.
    if (qTerms.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('clips')
            .where('terms', arrayContainsAny: qTerms.take(10).toList())
            .limit(40)
            .get();
        for (final d in snap.docs) {
          if (d.data()['creatorUid'] == me || d.data()['hidden'] == true) continue;
          final c = ClipData.fromFirestore(d.data(), d.id);
          if (!_clipOk(c)) continue;
          byId.putIfAbsent(d.id, () => c);
        }
      } catch (e) {
        print('SearchService: clip keyword query failed: $e');
      }
    }

    final n = byId.length;
    final scored = <MapEntry<ClipData, double>>[];
    for (final c in byId.values) {
      final rel = _clipRelevance(c, q, qTerms);
      if (rel <= 0) continue;
      final rank = _clipRank[c.id];
      final fit = rank == null ? 0.3 : 1 - rank / (n == 0 ? 1 : n);
      scored.add(MapEntry(c, 0.7 * rel + 0.3 * fit));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  static double _clipRelevance(ClipData c, String q, List<String> qTerms) {
    final caption = c.caption.toLowerCase();
    final terms = c.terms;
    double best = 0;
    void hit(double v) {
      if (v > best) best = v;
    }

    if (caption.contains(q)) {
      hit(RegExp('(^|[^a-z0-9])${RegExp.escape(q)}').hasMatch(caption) ? 1.0 : 0.85);
    }
    if (terms.any((t) => t == q || qTerms.contains(t))) hit(0.75);
    if (terms.any((t) => t.startsWith(q))) hit(0.55);
    if (qTerms.length > 1) {
      final hay = '$caption ${terms.join(' ')}';
      final found = qTerms.where(hay.contains).length;
      if (found == qTerms.length) hit(0.7);
      else if (found > 0) hit(0.3 * found / qTerms.length);
    }
    if (c.creatorUsername.toLowerCase() == q) hit(0.4);
    return best;
  }
}