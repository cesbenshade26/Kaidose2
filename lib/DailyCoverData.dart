import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyCoverHook.dart';
import 'DailyCoverThumbnail.dart';
import 'daily_service.dart';
import 'MessageStorage.dart';
import 'SendDailyMessage.dart';

/// The 24-hour window a cover is picked from, plus the key its shared
/// Firestore doc lives under.
///
/// "Day" here follows the same rule the rest of the app uses for "viewed
/// today" (the device's local calendar date), so covers roll over at each
/// viewer's own midnight. The UTC offset is part of the key so people in
/// the same time zone share one cover (and one hook generation), while
/// people in different zones each get a cover picked from their own
/// previous local day. Daylight saving needs no special handling because
/// the offset is part of the key, and the window is built from calendar
/// dates rather than by subtracting 24 hours.
/// TEMPORARY, for testing only. When true, the window becomes the last 7
/// days plus today, so a message you just sent can win without waiting
/// until tomorrow. Uses its own doc key so it never mixes with real
/// covers. Set back to false (or delete) before shipping.
const bool kCoverDebugIncludeToday = false;

class CoverWindow {
  final String key; // e.g. 2026-09-26_-0400
  final DateTime start; // local midnight that began the previous day
  final DateTime end; // local midnight that began today

  const CoverWindow({required this.key, required this.start, required this.end});

  factory CoverWindow.forNow([DateTime? now]) {
    final n = now ?? DateTime.now();
    final todayStart = DateTime(n.year, n.month, n.day);
    final yesterdayStart = DateTime(n.year, n.month, n.day - 1);

    final month = n.month.toString().padLeft(2, '0');
    final day = n.day.toString().padLeft(2, '0');
    final key = '${n.year}-$month-${day}_${_formatOffset(n.timeZoneOffset)}';

    if (kCoverDebugIncludeToday) {
      return CoverWindow(
        key: '${key}_debug',
        start: DateTime(n.year, n.month, n.day - 7),
        end: DateTime(n.year, n.month, n.day + 1),
      );
    }

    return CoverWindow(key: key, start: yesterdayStart, end: todayStart);
  }

  /// Plain local date, e.g. 2026-10-08. Scheduled covers/prompts are keyed
  /// by this (no UTC offset), so "Oct 8" means Oct 8 on each member's own
  /// calendar.
  static String dateKey(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  static String _formatOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final h = abs.inHours.toString().padLeft(2, '0');
    final m = (abs.inMinutes % 60).toString().padLeft(2, '0');
    return '$sign$h$m';
  }
}

/// Lifecycle of one cover doc.
///   generating — someone has claimed it and is working on it
///   ready      — a winning photo/video was found
///   empty      — nothing eligible was posted in the window; the card
///                falls back to its icon/color template
class CoverStatus {
  static const String generating = 'generating';
  static const String ready = 'ready';
  static const String empty = 'empty';
}

/// One Daily's cover for one time-zone-day. Lives in a single shared doc
/// (dailies/{dailyId}/daily_covers/{key}) rather than on DailyData,
/// because every member holds their own copy of DailyData and a cover
/// that changes daily would mean rewriting all of them every day.
class DailyCoverData {
  final String dailyId;
  final String key;
  final String status;

  // The winning media: the FIRST item of the winning message.
  final String? mediaUrl;
  final bool isVideo;
  final String? thumbnailUrl; // still frame for a video (filled in a later stage)
  final String? sourceMessageId;
  final int reactorCount;

  // Filled in by the hook stage. Null until then; the card shows a
  // template line instead.
  final String? hook;

  // Manual override slots. Not wired to any UI yet; when set, they win
  // over everything picked automatically.
  final String? manualMediaUrl;
  // True when the scheduled cover image is a still frame taken from a
  // video — only used to show the play badge, nothing plays from a card.
  final bool manualIsVideo;
  final String? manualHook;

  final DateTime? windowStart;
  final DateTime? windowEnd;
  final DateTime? generatedAt;
  final String? claimedBy;
  final DateTime? claimedAt;

  const DailyCoverData({
    required this.dailyId,
    required this.key,
    required this.status,
    this.mediaUrl,
    this.isVideo = false,
    this.thumbnailUrl,
    this.sourceMessageId,
    this.reactorCount = 0,
    this.hook,
    this.manualMediaUrl,
    this.manualIsVideo = false,
    this.manualHook,
    this.windowStart,
    this.windowEnd,
    this.generatedAt,
    this.claimedBy,
    this.claimedAt,
  });

  /// What the card should actually show: a manual override if one exists,
  /// otherwise the automatic pick.
  String? get effectiveMediaUrl => manualMediaUrl ?? mediaUrl;

  /// With a manual photo, the automatic hook is dropped: it was written
  /// about a different image, so showing it under the owner's photo would
  /// read as nonsense. Only a manual hook (or the card's placeholder) goes
  /// with a manual photo. Without a manual photo, a manual hook still wins
  /// over the automatic one.
  String? get effectiveHook =>
      manualMediaUrl != null ? manualHook : (manualHook ?? hook);

  /// Whether the image on the card should carry a play badge: follows the
  /// image actually shown, so a scheduled photo never inherits the badge
  /// from an automatically picked video, and a scheduled video frame
  /// gets one.
  bool get showsVideoBadge => manualMediaUrl != null ? manualIsVideo : isVideo;

  bool get hasImage => effectiveMediaUrl != null;

  /// Copy with the owner's scheduled cover for today layered on top. A
  /// manual photo makes the cover displayable even when the automatic pick
  /// is still generating or came up empty.
  DailyCoverData withManual({String? mediaUrl, bool isVideo = false, String? hook}) {
    return DailyCoverData(
      dailyId: dailyId,
      key: key,
      status: mediaUrl != null ? CoverStatus.ready : status,
      mediaUrl: this.mediaUrl,
      isVideo: isVideo,
      thumbnailUrl: thumbnailUrl,
      sourceMessageId: sourceMessageId,
      reactorCount: reactorCount,
      hook: this.hook,
      manualMediaUrl: mediaUrl,
      manualIsVideo: isVideo,
      manualHook: hook,
      windowStart: windowStart,
      windowEnd: windowEnd,
      generatedAt: generatedAt,
      claimedBy: claimedBy,
      claimedAt: claimedAt,
    );
  }

  /// A video's card image is its thumbnail, never the video file itself.
  String? get effectiveImageUrl {
    if (manualMediaUrl != null) return manualMediaUrl;
    return isVideo ? thumbnailUrl : mediaUrl;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'dailyId': dailyId,
      'key': key,
      'status': status,
      'mediaUrl': mediaUrl,
      'isVideo': isVideo,
      'thumbnailUrl': thumbnailUrl,
      'sourceMessageId': sourceMessageId,
      'reactorCount': reactorCount,
      'hook': hook,
      'manualMediaUrl': manualMediaUrl,
      'manualHook': manualHook,
      'windowStart': windowStart != null ? Timestamp.fromDate(windowStart!) : null,
      'windowEnd': windowEnd != null ? Timestamp.fromDate(windowEnd!) : null,
      'generatedAt': generatedAt != null ? Timestamp.fromDate(generatedAt!) : null,
      'claimedBy': claimedBy,
      'claimedAt': claimedAt != null ? Timestamp.fromDate(claimedAt!) : null,
    };
  }

  factory DailyCoverData.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    DateTime? ts(String field) => (d[field] as Timestamp?)?.toDate();

    return DailyCoverData(
      dailyId: d['dailyId'] ?? '',
      key: d['key'] ?? doc.id,
      status: d['status'] ?? CoverStatus.empty,
      mediaUrl: d['mediaUrl'] as String?,
      isVideo: d['isVideo'] ?? false,
      thumbnailUrl: d['thumbnailUrl'] as String?,
      sourceMessageId: d['sourceMessageId'] as String?,
      reactorCount: d['reactorCount'] ?? 0,
      hook: d['hook'] as String?,
      manualMediaUrl: d['manualMediaUrl'] as String?,
      manualHook: d['manualHook'] as String?,
      windowStart: ts('windowStart'),
      windowEnd: ts('windowEnd'),
      generatedAt: ts('generatedAt'),
      claimedBy: d['claimedBy'] as String?,
      claimedAt: ts('claimedAt'),
    );
  }
}

/// The winning message for a window, before it's written anywhere.
class CoverCandidate {
  final DailyMessage message;
  final int reactorCount;

  const CoverCandidate({required this.message, required this.reactorCount});

  /// First item of the message: people tend to lead a carousel with the
  /// headline photo and follow it with the detail.
  DailyMediaItem get coverItem => message.media.first;
}

/// Picks and stores each Daily's cover. Nothing here runs on a schedule:
/// the first member to open the app after their local midnight triggers
/// generation for their time zone, and everyone else just reads the
/// result.
class DailyCoverService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // A claim older than this is assumed abandoned (app closed mid-generation)
  // and can be taken over.
  static const Duration _claimTimeout = Duration(minutes: 2);

  // Dedupes overlapping requests within a session, e.g. several cards or
  // rebuilds asking for the same Daily's cover at once.
  static final Map<String, Future<DailyCoverData?>> _inFlight = {};

  static DocumentReference<Map<String, dynamic>> _coverRef(
      String dailyId, String key) {
    return _firestore
        .collection('dailies')
        .doc(dailyId)
        .collection('daily_covers')
        .doc(key);
  }

  /// Owner-scheduled prompts and covers, one doc per calendar day:
  /// dailies/{dailyId}/daily_schedule/{yyyy-MM-dd}
  static CollectionReference<Map<String, dynamic>> scheduleCollection(
      String dailyId) {
    return _firestore
        .collection('dailies')
        .doc(dailyId)
        .collection('daily_schedule');
  }

  static DocumentReference<Map<String, dynamic>> scheduleRef(
      String dailyId, String dateKey) {
    return scheduleCollection(dailyId).doc(dateKey);
  }

  /// Live view of today's cover for this viewer: the automatic cover doc
  /// for their time zone, with the owner's scheduled cover for today's
  /// date (if any) layered on top. A scheduled cover lives in a doc keyed
  /// by its own date, so it can only ever show on that date, regardless of
  /// what the automatic pick does.
  static Stream<DailyCoverData?> watchCover(String dailyId) {
    final window = CoverWindow.forNow();
    final todayKey = CoverWindow.dateKey(DateTime.now());

    final coverStream = _coverRef(dailyId, window.key).snapshots();
    final scheduleStream = scheduleRef(dailyId, todayKey).snapshots();

    DocumentSnapshot<Map<String, dynamic>>? latestCover;
    DocumentSnapshot<Map<String, dynamic>>? latestSchedule;
    StreamSubscription? coverSub;
    StreamSubscription? scheduleSub;

    late StreamController<DailyCoverData?> controller;

    // Wait until both have reported once so the card never flashes the
    // automatic cover and then swaps to the scheduled one.
    void emit() {
      if (latestCover == null || latestSchedule == null) return;
      controller.add(_merge(dailyId, window.key, latestCover!, latestSchedule!));
    }

    controller = StreamController<DailyCoverData?>(
      onListen: () {
        coverSub = coverStream.listen((snap) {
          latestCover = snap;
          emit();
        }, onError: controller.addError);
        scheduleSub = scheduleStream.listen((snap) {
          latestSchedule = snap;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await coverSub?.cancel();
        await scheduleSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// One-time read of today's cover for a Daily the viewer is NOT in (the
  /// For You feed). Unlike [ensureCover] this never generates anything — a
  /// cover only exists if a member's app already made one — so browsing the
  /// feed can't trigger AI calls. Null/empty means "show the classic card".
  static Future<DailyCoverData?> getCoverOnce(String dailyId) async {
    try {
      return await watchCover(dailyId)
          .first
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      print('DailyCoverService: getCoverOnce error: $e');
      return null;
    }
  }

  static DailyCoverData? _merge(
      String dailyId,
      String key,
      DocumentSnapshot<Map<String, dynamic>> coverSnap,
      DocumentSnapshot<Map<String, dynamic>> scheduleSnap,
      ) {
    final base = coverSnap.exists ? DailyCoverData.fromFirestore(coverSnap) : null;

    String? manualMedia;
    String? manualHook;
    bool manualIsVideo = false;
    if (scheduleSnap.exists) {
      final data = scheduleSnap.data() ?? {};
      final media = (data['coverMediaUrl'] as String?)?.trim() ?? '';
      final hook = (data['coverHook'] as String?)?.trim() ?? '';
      manualMedia = media.isEmpty ? null : media;
      manualHook = hook.isEmpty ? null : hook;
      manualIsVideo = manualMedia != null && (data['coverIsVideo'] as bool? ?? false);
    }

    if (manualMedia == null && manualHook == null) return base;

    final underlying = base ??
        DailyCoverData(dailyId: dailyId, key: key, status: CoverStatus.empty);
    return underlying.withManual(
      mediaUrl: manualMedia,
      isVideo: manualIsVideo,
      hook: manualHook,
    );
  }

  /// Returns the current cover, generating it first if this is the first
  /// request since the viewer's local midnight. Safe to call from every
  /// card on every build: after the first call it costs one doc read.
  static Future<DailyCoverData?> ensureCover(String dailyId) {
    final window = CoverWindow.forNow();
    final inFlightKey = '$dailyId|${window.key}';

    return _inFlight.putIfAbsent(inFlightKey, () async {
      try {
        return await _ensureCover(dailyId, window);
      } catch (e) {
        print('DailyCoverService: ensureCover error for $dailyId: $e');
        return null;
      } finally {
        // Keep the entry only while the work is running; a finished
        // result is served from Firestore on the next call.
        _inFlight.remove(inFlightKey);
      }
    });
  }

  static Future<DailyCoverData?> _ensureCover(
      String dailyId, CoverWindow window) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    final ref = _coverRef(dailyId, window.key);

    // Fast path: already generated (or being generated) for this zone-day.
    final existing = await ref.get();
    if (existing.exists) {
      final cover = DailyCoverData.fromFirestore(existing);
      if (cover.status != CoverStatus.generating || !_isStale(cover)) {
        return cover;
      }
    }

    // Try to claim it. The transaction makes sure only one of several
    // simultaneous openers actually does the work.
    final won = await _firestore.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        final cover = DailyCoverData.fromFirestore(snap);
        final done = cover.status == CoverStatus.ready ||
            cover.status == CoverStatus.empty;
        if (done) return false;
        if (cover.status == CoverStatus.generating && !_isStale(cover)) {
          return false;
        }
      }

      tx.set(
        ref,
        DailyCoverData(
          dailyId: dailyId,
          key: window.key,
          status: CoverStatus.generating,
          windowStart: window.start,
          windowEnd: window.end,
          claimedBy: uid,
          claimedAt: DateTime.now(),
        ).toFirestore(),
      );
      return true;
    });

    if (!won) {
      // Someone else is (or just finished) generating it.
      final snap = await ref.get();
      return snap.exists ? DailyCoverData.fromFirestore(snap) : null;
    }

    return _generateAndStore(dailyId, window, ref, uid);
  }

  static bool _isStale(DailyCoverData cover) {
    final claimedAt = cover.claimedAt;
    if (claimedAt == null) return true;
    return DateTime.now().difference(claimedAt) > _claimTimeout;
  }

  static Future<DailyCoverData> _generateAndStore(
      String dailyId,
      CoverWindow window,
      DocumentReference<Map<String, dynamic>> ref,
      String uid,
      ) async {
    DailyCoverData result;

    try {
      final messages = await MessageStorage.loadMessages(dailyId);
      final winner = pickWinner(messages, window);

      if (winner == null) {
        result = DailyCoverData(
          dailyId: dailyId,
          key: window.key,
          status: CoverStatus.empty,
          windowStart: window.start,
          windowEnd: window.end,
          generatedAt: DateTime.now(),
          claimedBy: uid,
        );
        print('DailyCoverService: no eligible media for $dailyId (${window.key})');
      } else {
        // Video winners need a still frame before anyone — the card or
        // the hook generator — can show/see anything. A failure here
        // just means no thumbnail; the card falls back to the classic
        // layout and the hook falls back to its no-visual-information
        // branch, same as before this existed.
        String? thumbnailUrl;
        if (winner.coverItem.isVideo) {
          thumbnailUrl = await DailyCoverThumbnail.generateAndUpload(
            dailyId: dailyId,
            key: window.key,
            videoUrl: winner.coverItem.path,
          );
        }

        // Ask Gemini for the teaser line. A failure just means no hook,
        // and the card falls back to its placeholder. The thumbnail (if
        // we got one) gives a video cover real visual grounding instead
        // of generating blind.
        final daily = await DailyService().getDailyById(dailyId);
        final hook = await DailyCoverHookService.generateHook(
          dailyTitle: daily?.title ?? 'this Daily',
          dailyDescription: daily?.description,
          coverCaption: winner.message.text,
          contextTexts: _contextTexts(messages, window, winner.message.messageId),
          imageUrl: winner.coverItem.isVideo ? thumbnailUrl : winner.coverItem.path,
          coverIsVideo: winner.coverItem.isVideo,
        );

        result = DailyCoverData(
          dailyId: dailyId,
          key: window.key,
          status: CoverStatus.ready,
          mediaUrl: winner.coverItem.path,
          isVideo: winner.coverItem.isVideo,
          thumbnailUrl: thumbnailUrl,
          sourceMessageId: winner.message.messageId,
          reactorCount: winner.reactorCount,
          hook: hook,
          windowStart: window.start,
          windowEnd: window.end,
          generatedAt: DateTime.now(),
          claimedBy: uid,
        );
        print('DailyCoverService: cover for $dailyId (${window.key}) is message '
            '${winner.message.messageId} with ${winner.reactorCount} reactor(s)');
      }
    } catch (e) {
      // Don't leave the doc stuck on "generating" if selection fails;
      // record an empty cover so the card falls back cleanly.
      print('DailyCoverService: generation failed for $dailyId: $e');
      result = DailyCoverData(
        dailyId: dailyId,
        key: window.key,
        status: CoverStatus.empty,
        windowStart: window.start,
        windowEnd: window.end,
        generatedAt: DateTime.now(),
        claimedBy: uid,
      );
    }

    // merge so a manual override written in the meantime isn't wiped.
    await ref.set(result.toFirestore(), SetOptions(merge: true));
    return result;
  }

  /// Picks the winning message for [window], or null if nothing qualifies.
  ///
  /// A message is eligible if it was sent inside the window, carries
  /// media, and its first media item has been uploaded (a local file path
  /// is useless to everyone but the sender). Ranking is by how many
  /// DISTINCT people reacted, so one person dropping five emoji doesn't
  /// outrank a photo three friends reacted to. Ties, including the
  /// everything-has-zero case, go to the most recent message.
  static CoverCandidate? pickWinner(
      List<DailyMessage> messages, CoverWindow window) {
    final candidates = <CoverCandidate>[];

    for (final m in messages) {
      if (m.media.isEmpty) continue;
      if (m.timestamp.isBefore(window.start) || !m.timestamp.isBefore(window.end)) {
        continue;
      }
      if (!_isNetworkUrl(m.media.first.path)) continue;

      final reactors = m.reactions.map((r) => r.userId).toSet().length;
      candidates.add(CoverCandidate(message: m, reactorCount: reactors));
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final byReactors = b.reactorCount.compareTo(a.reactorCount);
      if (byReactors != 0) return byReactors;
      return b.message.timestamp.compareTo(a.message.timestamp);
    });

    return candidates.first;
  }

  /// The most recent text messages inside the window, oldest first, as
  /// extra context for the hook. Skips the winning message (its caption is
  /// passed separately) and keeps each one short.
  static List<String> _contextTexts(
      List<DailyMessage> messages,
      CoverWindow window,
      String winnerMessageId,
      ) {
    final inWindow = messages.where((m) {
      if (m.messageId == winnerMessageId) return false;
      if (m.timestamp.isBefore(window.start) || !m.timestamp.isBefore(window.end)) {
        return false;
      }
      return (m.text ?? '').trim().isNotEmpty;
    }).toList();

    inWindow.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final recent = inWindow.length > 8 ? inWindow.sublist(inWindow.length - 8) : inWindow;
    return recent.map((m) {
      final t = m.text!.trim();
      return t.length > 200 ? '${t.substring(0, 200)}…' : t;
    }).toList();
  }

  static bool _isNetworkUrl(String path) =>
      path.startsWith('http://') || path.startsWith('https://');
}