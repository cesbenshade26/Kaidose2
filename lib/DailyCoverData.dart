import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';

/// Calendar-date helpers. Scheduled covers/prompts are keyed by a plain
/// local date (no UTC offset), so "Oct 8" means Oct 8 on each viewer's own
/// calendar.
class CoverWindow {
  /// Plain local date, e.g. 2026-10-08.
  static String dateKey(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }
}

/// Lifecycle of the shared cover doc.
///   ready — a winning photo/video was picked
///   empty — nothing eligible was posted; the card shows its classic layout
class CoverStatus {
  static const String ready = 'ready';
  static const String empty = 'empty';
}

/// One Daily's current cover, as every viewer sees it.
///
/// The automatic part is picked by the server (Cloud Function
/// refreshDailyCovers) three times a day in the Daily's home time zone and
/// stored at dailies/{dailyId}/daily_covers/current:
///   5 am  -> yesterday's best (phase "yesterday")
///   1 pm / 9 pm -> today's best so far (phase "today")
/// Phones never generate covers anymore; they only read.
///
/// The owner's schedule for today (daily_schedule/{date}) is layered on top
/// and always wins.
class DailyCoverData {
  final String dailyId;
  final String status;
  final String? phase; // 'yesterday' | 'today'

  // The automatic pick.
  final String? mediaUrl; // the photo, or the video file
  final String? imageUrl; // what the card shows (a video's still frame)
  final bool isVideo;
  final String? sourceMessageId;
  final int reactorCount;
  final String? hook;
  final DateTime? generatedAt;

  // A text post as the cover (no photo/video): it only wins when it got at
  // least twice the reactions of the best photo/video, or when there was no
  // photo/video. Shown as a quote card, with no AI hook (the text is the
  // hook).
  final bool isText;
  final String? text;
  final String? authorUid;
  final String? authorName;

  // The owner's scheduled cover for today, if any.
  final String? manualMediaUrl;
  final bool manualIsVideo;
  final String? manualHook;
  // AI hook the server wrote for the owner's photo (when they gave none).
  final String? manualAiHook;

  /// False when the Daily's owner turned AI cover hooks off.
  final bool aiHooksEnabled;

  const DailyCoverData({
    required this.dailyId,
    required this.status,
    this.phase,
    this.mediaUrl,
    this.imageUrl,
    this.isVideo = false,
    this.sourceMessageId,
    this.reactorCount = 0,
    this.hook,
    this.generatedAt,
    this.isText = false,
    this.text,
    this.authorUid,
    this.authorName,
    this.manualMediaUrl,
    this.manualIsVideo = false,
    this.manualHook,
    this.manualAiHook,
    this.aiHooksEnabled = true,
  });

  bool get _hasManualPhoto => manualMediaUrl != null;

  /// The image the card shows: the owner's photo, else the automatic pick.
  String? get effectiveImageUrl => _hasManualPhoto ? manualMediaUrl : imageUrl;

  /// The automatic pick is a text post (and the owner didn't set a photo).
  bool get showsTextCover =>
      !_hasManualPhoto && isText && (text?.isNotEmpty ?? false);

  /// The post this cover came from, to open the Daily right at it. Null for
  /// the owner's own photo (it isn't a post).
  String? get jumpMessageId => _hasManualPhoto ? null : sourceMessageId;

  /// The hook line, or null for no line at all.
  ///  - The owner's own hook always wins.
  ///  - With the owner's photo: the AI hook written for THAT photo.
  ///  - Otherwise: the automatic pick's AI hook.
  ///  AI hooks are dropped when the owner turned them off.
  String? get effectiveHook {
    if (manualHook != null) return manualHook;
    if (!aiHooksEnabled || showsTextCover) return null;
    return _hasManualPhoto ? manualAiHook : hook;
  }

  bool get showsVideoBadge => _hasManualPhoto ? manualIsVideo : isVideo;

  /// Something to show on the card right now.
  bool get isShowable =>
      status == CoverStatus.ready &&
          (effectiveImageUrl != null || showsTextCover);

  factory DailyCoverData.fromCoverDoc(String dailyId, Map<String, dynamic> d) {
    var status = (d['status'] as String?) ?? CoverStatus.empty;
    final generatedAt = (d['generatedAt'] as Timestamp?)?.toDate();
    // A Daily that went quiet stops getting refreshed; don't keep showing a
    // days-old cover as if it were current.
    if (generatedAt != null &&
        DateTime.now().difference(generatedAt) > const Duration(hours: 36)) {
      status = CoverStatus.empty;
    }
    return DailyCoverData(
      dailyId: dailyId,
      status: status,
      phase: d['phase'] as String?,
      mediaUrl: d['mediaUrl'] as String?,
      imageUrl: d['imageUrl'] as String?,
      isVideo: d['isVideo'] == true,
      sourceMessageId: d['sourceMessageId'] as String?,
      reactorCount: (d['reactorCount'] as num?)?.toInt() ?? 0,
      hook: d['hook'] as String?,
      generatedAt: generatedAt,
      isText: d['isText'] == true,
      text: d['text'] as String?,
      authorUid: d['authorUid'] as String?,
      authorName: d['authorName'] as String?,
    );
  }

  DailyCoverData copyWith({
    String? status,
    String? manualMediaUrl,
    bool? manualIsVideo,
    String? manualHook,
    String? manualAiHook,
    bool? aiHooksEnabled,
  }) {
    return DailyCoverData(
      dailyId: dailyId,
      status: status ?? this.status,
      phase: phase,
      mediaUrl: mediaUrl,
      imageUrl: imageUrl,
      isVideo: isVideo,
      sourceMessageId: sourceMessageId,
      reactorCount: reactorCount,
      hook: hook,
      generatedAt: generatedAt,
      isText: isText,
      text: text,
      authorUid: authorUid,
      authorName: authorName,
      manualMediaUrl: manualMediaUrl ?? this.manualMediaUrl,
      manualIsVideo: manualIsVideo ?? this.manualIsVideo,
      manualHook: manualHook ?? this.manualHook,
      manualAiHook: manualAiHook ?? this.manualAiHook,
      aiHooksEnabled: aiHooksEnabled ?? this.aiHooksEnabled,
    );
  }
}

/// Reads covers and schedules. Nothing here generates anything; the Cloud
/// Functions do that.
class DailyCoverService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _dailyRef(String dailyId) =>
      _firestore.collection('dailies').doc(dailyId);

  static DocumentReference<Map<String, dynamic>> _coverRef(String dailyId) =>
      _dailyRef(dailyId).collection('daily_covers').doc('current');

  /// Owner-scheduled prompts and covers, one doc per calendar day:
  /// dailies/{dailyId}/daily_schedule/{yyyy-MM-dd}
  static CollectionReference<Map<String, dynamic>> scheduleCollection(
      String dailyId) {
    return _dailyRef(dailyId).collection('daily_schedule');
  }

  static DocumentReference<Map<String, dynamic>> scheduleRef(
      String dailyId, String dateKey) {
    return scheduleCollection(dailyId).doc(dateKey);
  }

  // Today's scheduled entry prompt per Daily, as last seen by watchCover:
  // dailyId -> (dateKey, prompt).
  static final Map<String, MapEntry<String, String>> _prompts = {};

  /// Today's scheduled entry prompt if watchCover already has it ('' = no
  /// prompt today), or null if not known yet.
  static String? knownPrompt(String dailyId) {
    final p = _prompts[dailyId];
    if (p == null || p.key != CoverWindow.dateKey(DateTime.now())) return null;
    return p.value;
  }

  /// The entry prompt for today, or '' if the owner didn't schedule one.
  /// Prompts are per day, like covers: one set for the 20th shows only on
  /// the 20th.
  static Future<String> todayPrompt(String dailyId) async {
    final known = knownPrompt(dailyId);
    if (known != null) return known;
    final key = CoverWindow.dateKey(DateTime.now());
    try {
      final snap = await scheduleRef(dailyId, key).get();
      final prompt = ((snap.data()?['prompt'] as String?) ?? '').trim();
      _prompts[dailyId] = MapEntry(key, prompt);
      return prompt;
    } catch (e) {
      print('DailyCoverService: todayPrompt error for $dailyId: $e');
      return '';
    }
  }

  // The last cover seen for each Daily this session. A card that's rebuilt
  // (switching tabs, coming back to Dailies, scrolling back to it) starts
  // with this, so it shows its cover right away instead of loading again.
  static final Map<String, DailyCoverData?> _last = {};

  /// The last cover seen for this Daily, or null if none yet.
  static DailyCoverData? lastKnown(String dailyId) => _last[dailyId];

  /// Whether this Daily's cover has been read this session.
  static bool isKnown(String dailyId) => _last.containsKey(dailyId);

  // Dailies whose info this session already synced (see syncDailyInfo).
  static final Set<String> _synced = {};

  /// Owner only, once per app session: keeps dailies/{id} up to date with
  /// what the server needs to pick covers and write hooks: the Daily's home
  /// time zone (the owner's), its title and its description.
  static Future<void> syncDailyInfo(DailyData daily) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || daily.creatorUid != uid) return;
    if (!_synced.add(daily.id)) return;
    try {
      await _dailyRef(daily.id).set({
        'title': daily.title,
        'description': daily.description,
        'ownerUid': uid,
        'homeOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      }, SetOptions(merge: true));
    } catch (e) {
      _synced.remove(daily.id);
      print('DailyCoverService: syncDailyInfo error for ${daily.id}: $e');
    }
  }

  /// Live AI-hooks setting for a Daily (on unless the owner turned it off).
  static Stream<bool> watchAiHooksEnabled(String dailyId) => _dailyRef(dailyId)
      .snapshots()
      .map((s) => s.data()?['aiHooksEnabled'] != false);

  /// Owner only: turn AI cover hooks on or off for this Daily.
  static Future<void> setAiHooksEnabled(String dailyId, bool enabled) {
    return _dailyRef(dailyId)
        .set({'aiHooksEnabled': enabled}, SetOptions(merge: true));
  }

  /// Live view of the cover for this viewer: the shared automatic cover,
  /// the owner's schedule for today's date and the AI-hooks setting,
  /// merged. Emits only once all three have reported, so the card never
  /// flashes the automatic cover and then swaps to the scheduled one.
  static Stream<DailyCoverData?> watchCover(String dailyId) {
    final todayKey = CoverWindow.dateKey(DateTime.now());

    DocumentSnapshot<Map<String, dynamic>>? cover;
    DocumentSnapshot<Map<String, dynamic>>? schedule;
    DocumentSnapshot<Map<String, dynamic>>? daily;
    final subs = <StreamSubscription>[];
    late StreamController<DailyCoverData?> controller;

    void emit() {
      if (cover == null || schedule == null || daily == null) return;
      if (!controller.isClosed) {
        final merged = _merge(dailyId, cover!, schedule!, daily!);
        _last[dailyId] = merged;
        controller.add(merged);
      }
    }

    controller = StreamController<DailyCoverData?>(
      onListen: () {
        subs.add(_coverRef(dailyId).snapshots().listen((s) {
          cover = s;
          emit();
        }, onError: controller.addError));
        subs.add(scheduleRef(dailyId, todayKey).snapshots().listen((s) {
          schedule = s;
          _prompts[dailyId] = MapEntry(
              todayKey, ((s.data()?['prompt'] as String?) ?? '').trim());
          emit();
        }, onError: controller.addError));
        subs.add(_dailyRef(dailyId).snapshots().listen((s) {
          daily = s;
          emit();
        }, onError: controller.addError));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  static DailyCoverData? _merge(
      String dailyId,
      DocumentSnapshot<Map<String, dynamic>> coverSnap,
      DocumentSnapshot<Map<String, dynamic>> scheduleSnap,
      DocumentSnapshot<Map<String, dynamic>> dailySnap,
      ) {
    final aiOn = dailySnap.data()?['aiHooksEnabled'] != false;
    var base = coverSnap.exists
        ? DailyCoverData.fromCoverDoc(dailyId, coverSnap.data() ?? {})
        : DailyCoverData(dailyId: dailyId, status: CoverStatus.empty);
    base = base.copyWith(aiHooksEnabled: aiOn);

    if (!scheduleSnap.exists) return base;
    final s = scheduleSnap.data() ?? {};
    final media = (s['coverMediaUrl'] as String?)?.trim() ?? '';
    final hook = (s['coverHook'] as String?)?.trim() ?? '';
    final aiHook = (s['aiHook'] as String?)?.trim() ?? '';
    final aiHookFor = s['aiHookFor'] as String?;
    if (media.isEmpty && hook.isEmpty) return base;

    return DailyCoverData(
      dailyId: dailyId,
      // An owner's photo makes the cover showable even on a quiet day.
      status: media.isNotEmpty ? CoverStatus.ready : base.status,
      phase: base.phase,
      mediaUrl: base.mediaUrl,
      imageUrl: base.imageUrl,
      isVideo: base.isVideo,
      sourceMessageId: base.sourceMessageId,
      reactorCount: base.reactorCount,
      hook: base.hook,
      generatedAt: base.generatedAt,
      isText: base.isText,
      text: base.text,
      authorUid: base.authorUid,
      authorName: base.authorName,
      manualMediaUrl: media.isEmpty ? null : media,
      manualIsVideo: media.isNotEmpty && s['coverIsVideo'] == true,
      manualHook: hook.isEmpty ? null : hook,
      // Only trust an AI hook written for this exact photo.
      manualAiHook:
      (aiHook.isNotEmpty && aiHookFor == media) ? aiHook : null,
      aiHooksEnabled: aiOn,
    );
  }

  /// Old name, kept so any other screen that still calls it compiles.
  /// Covers are made by the server now, so this only reads.
  @Deprecated('Covers are generated by the server; use watchCover.')
  static Future<DailyCoverData?> ensureCover(String dailyId) =>
      getCoverOnce(dailyId);

  /// One-time read of the current cover. Null means "show the classic card".
  static Future<DailyCoverData?> getCoverOnce(String dailyId) async {
    try {
      return await watchCover(dailyId).first.timeout(const Duration(seconds: 8));
    } catch (e) {
      print('DailyCoverService: getCoverOnce error: $e');
      return null;
    }
  }
}