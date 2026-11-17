import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'FeedService.dart';

/// Why someone is reporting something. Shown in this order.
enum ReportReason {
  spam,
  harassment,
  hate,
  nudity,
  violence,
  selfHarm,
  scam,
  impersonation,
  underage,
  intellectualProperty,
  other,
}

extension ReportReasonText on ReportReason {
  String get label {
    switch (this) {
      case ReportReason.spam:
        return 'Spam';
      case ReportReason.harassment:
        return 'Bullying or harassment';
      case ReportReason.hate:
        return 'Hate speech or symbols';
      case ReportReason.nudity:
        return 'Nudity or sexual content';
      case ReportReason.violence:
        return 'Violence or dangerous acts';
      case ReportReason.selfHarm:
        return 'Suicide or self-harm';
      case ReportReason.scam:
        return 'Scam or fraud';
      case ReportReason.impersonation:
        return 'Pretending to be someone else';
      case ReportReason.underage:
        return 'Account may belong to someone under 13';
      case ReportReason.intellectualProperty:
        return 'Copyright or trademark';
      case ReportReason.other:
        return 'Something else';
    }
  }
}

/// What is being reported. `user` is the person themselves.
enum ReportTarget { user, clip, dailyMessage, comment, chatMessage, story, daily, groupChat }

/// Everything about keeping people safe: blocking, muting, hiding your
/// story, removing friends, "Not interested", and reports.
///
/// Firestore:
///   blocks/{blocker}_{blocked}          {blocker, blocked, createdAt}
///   users/{me}/muted/{uid}              hides their stories + clips for me
///   users/{me}/story_hidden/{uid}       they can't see my story
///   users/{me}/not_interested/{clipId}  never show me this clip again
///   reports/{id}                        reviewed by an admin
///
/// The lists are kept live in memory (call [start] once at launch), so
/// checks like [isHidden] are instant anywhere in the app.
class SafetyService {
  SafetyService._();
  static final SafetyService instance = SafetyService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Bumps whenever any of the lists below change.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Set<String> blocked = {};
  Set<String> blockedBy = {};
  Set<String> muted = {};
  Set<String> storyHiddenFrom = {};
  Set<String> notInterested = {};

  final List<StreamSubscription> _subs = [];
  StreamSubscription<User?>? _auth;
  String? _uid;

  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  // ─── Live lists ───────────────────────────────────────────────────────────

  void start() {
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid == _uid) return;
      _uid = user?.uid;
      _stopListening();
      if (user != null) _listen(user.uid);
    });
  }

  void _stopListening() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    blocked = {};
    blockedBy = {};
    muted = {};
    storyHiddenFrom = {};
    notInterested = {};
    changes.value++;
  }

  void _listen(String me) {
    void onError(Object e) => print('SafetyService: listen error: $e');
    _subs.add(_db
        .collection('blocks')
        .where('blocker', isEqualTo: me)
        .snapshots()
        .listen((s) {
      blocked = s.docs.map((d) => d.data()['blocked'] as String? ?? '').toSet()
        ..remove('');
      changes.value++;
    }, onError: onError));
    _subs.add(_db
        .collection('blocks')
        .where('blocked', isEqualTo: me)
        .snapshots()
        .listen((s) {
      blockedBy = s.docs.map((d) => d.data()['blocker'] as String? ?? '').toSet()
        ..remove('');
      changes.value++;
    }, onError: onError));
    _subs.add(_users(me).collection('muted').snapshots().listen((s) {
      muted = s.docs.map((d) => d.id).toSet();
      changes.value++;
    }, onError: onError));
    _subs.add(_users(me).collection('story_hidden').snapshots().listen((s) {
      storyHiddenFrom = s.docs.map((d) => d.id).toSet();
      changes.value++;
    }, onError: onError));
    _subs.add(_users(me)
        .collection('not_interested')
        .orderBy('at', descending: true)
        .limit(500)
        .snapshots()
        .listen((s) {
      notInterested = s.docs.map((d) => d.id).toSet();
      changes.value++;
    }, onError: onError));
  }

  DocumentReference<Map<String, dynamic>> _users(String id) =>
      _db.collection('users').doc(id);

  // ─── Checks ───────────────────────────────────────────────────────────────

  bool isBlocked(String uid) => blocked.contains(uid);
  bool blocksMe(String uid) => blockedBy.contains(uid);

  /// Blocked either way: don't show them to me or me to them.
  bool isHidden(String uid) => blocked.contains(uid) || blockedBy.contains(uid);

  bool isMuted(String uid) => muted.contains(uid);

  /// Their clips/stories shouldn't appear in my feeds.
  bool hidesCreator(String uid) => isHidden(uid) || muted.contains(uid);

  bool isStoryHiddenFrom(String uid) => storyHiddenFrom.contains(uid);

  // ─── Friends ──────────────────────────────────────────────────────────────

  Future<bool> areFriends(String other) async {
    final me = uid;
    if (me == null) return false;
    final a = await _db
        .collection('friend_requests')
        .where('fromUserId', isEqualTo: me)
        .where('toUserId', isEqualTo: other)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    if (a.docs.isNotEmpty) return true;
    final b = await _db
        .collection('friend_requests')
        .where('fromUserId', isEqualTo: other)
        .where('toUserId', isEqualTo: me)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();
    return b.docs.isNotEmpty;
  }

  /// Ends the friendship (and any pending requests either way). Becoming
  /// friends again takes a brand-new request, so the friendship "starts
  /// over" with a new date.
  Future<void> removeFriend(String other) async {
    final me = uid;
    if (me == null) return;
    final results = await Future.wait([
      _db
          .collection('friend_requests')
          .where('fromUserId', isEqualTo: me)
          .where('toUserId', isEqualTo: other)
          .get(),
      _db
          .collection('friend_requests')
          .where('fromUserId', isEqualTo: other)
          .where('toUserId', isEqualTo: me)
          .get(),
    ]);
    final batch = _db.batch();
    for (final snap in results) {
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
    }
    await batch.commit();
  }

  // ─── Block ────────────────────────────────────────────────────────────────

  /// Blocks [other]: they're removed from your friends, can't find you,
  /// see your profile, clips or story, or message you, and their stuff
  /// disappears from your feeds. They aren't told.
  Future<void> block(String other) async {
    final me = uid;
    if (me == null || other == me) return;
    blocked = {...blocked, other};
    changes.value++;
    await _db.collection('blocks').doc('${me}_$other').set({
      'blocker': me,
      'blocked': other,
      'createdAt': FieldValue.serverTimestamp(),
    });
    try {
      await removeFriend(other);
    } catch (e) {
      print('SafetyService: unfriend on block failed: $e');
    }
  }

  Future<void> unblock(String other) async {
    final me = uid;
    if (me == null) return;
    blocked = {...blocked}..remove(other);
    changes.value++;
    await _db.collection('blocks').doc('${me}_$other').delete();
  }

  // ─── Mute / story ─────────────────────────────────────────────────────────

  Future<void> setMuted(String other, bool mute) async {
    final me = uid;
    if (me == null) return;
    muted = mute ? {...muted, other} : ({...muted}..remove(other));
    changes.value++;
    final ref = _users(me).collection('muted').doc(other);
    mute
        ? await ref.set({'at': FieldValue.serverTimestamp()})
        : await ref.delete();
  }

  Future<void> setStoryHidden(String other, bool hide) async {
    final me = uid;
    if (me == null) return;
    storyHiddenFrom =
    hide ? {...storyHiddenFrom, other} : ({...storyHiddenFrom}..remove(other));
    changes.value++;
    final ref = _users(me).collection('story_hidden').doc(other);
    hide
        ? await ref.set({'at': FieldValue.serverTimestamp()})
        : await ref.delete();
  }

  /// Whether [owner] hid their story from me (or blocked me). Viewers can
  /// read only their own doc in the owner's story_hidden list.
  Future<bool> isStoryHiddenFromMe(String owner) async {
    final me = uid;
    if (me == null) return true;
    if (blockedBy.contains(owner) || blocked.contains(owner)) return true;
    // The story bar re-checks every 30s; one read per person per 2 minutes.
    final cached = _hiddenFromMe[owner];
    if (cached != null &&
        DateTime.now().difference(cached.$2) < const Duration(minutes: 2)) {
      return cached.$1;
    }
    try {
      final d = await _users(owner).collection('story_hidden').doc(me).get();
      _hiddenFromMe[owner] = (d.exists, DateTime.now());
      return d.exists;
    } catch (_) {
      return false;
    }
  }

  final Map<String, (bool, DateTime)> _hiddenFromMe = {};

  // ─── Clips ────────────────────────────────────────────────────────────────

  /// "Not interested": never show this clip again, and show less like it
  /// (its topics and its creator count against it in the feed).
  Future<void> notInterestedIn({
    required String clipId,
    required String creatorUid,
    List<String>? terms,
  }) async {
    final me = uid;
    if (me == null) return;
    notInterested = {...notInterested, clipId};
    changes.value++;
    await _users(me).collection('not_interested').doc(clipId).set({
      'at': FieldValue.serverTimestamp(),
      'creatorUid': creatorUid,
    });
    await FeedService.recordClipEvent(
      creatorUid: creatorUid,
      event: ClipEvent.notInterested,
      clipId: clipId,
      terms: terms,
    );
  }

  // ─── Reports ──────────────────────────────────────────────────────────────

  /// Files a report for an admin to review. [path] is the Firestore doc of
  /// the reported thing (lets the admin remove it in one tap); [preview]
  /// is a short copy of the text so they can see it even if it's edited.
  Future<void> report({
    required ReportTarget target,
    required String targetId,
    required String ownerUid,
    required ReportReason reason,
    String note = '',
    String? path,
    String? preview,
    Map<String, dynamic>? extra,
  }) async {
    final me = uid;
    if (me == null) return;
    await _db.collection('reports').add({
      'reporterUid': me,
      'target': target.name,
      'targetId': targetId,
      'ownerUid': ownerUid,
      'reason': reason.name,
      'reasonLabel': reason.label,
      'note': note.trim(),
      if (path != null) 'path': path,
      if (preview != null && preview.isNotEmpty)
        'preview': preview.length > 500 ? preview.substring(0, 500) : preview,
      if (extra != null) 'extra': extra,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}