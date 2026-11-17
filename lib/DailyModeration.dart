import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'user_service.dart';
import 'MessageStorage.dart';

/// Someone's role in one Daily.
enum DailyRole { owner, moderator, member }

/// What a role is allowed to do in a Daily. One place, so every screen
/// agrees.
///
///   Owner (creator)  everything
///   Moderator        ban / unban members, schedule covers and entry prompts
///   Member           nothing to manage
///
/// Title, icon, font, description, privacy, tags and choosing moderators
/// stay with the owner: they define what the Daily IS, so they shouldn't
/// change under the owner's feet.
class DailyPermissions {
  final DailyRole role;
  const DailyPermissions(this.role);

  static const DailyPermissions none = DailyPermissions(DailyRole.member);

  bool get isOwner => role == DailyRole.owner;
  bool get isModerator => role == DailyRole.moderator;

  /// Ban and unban members.
  bool get canModerate => isOwner || isModerator;

  /// Schedule covers and entry prompts.
  bool get canSchedule => isOwner || isModerator;

  /// Title, icon, font, description, privacy, tags.
  bool get canEditDetails => isOwner;

  /// Make / remove moderators.
  bool get canManageModerators => isOwner;

  String get label => isOwner
      ? "You're the owner"
      : isModerator
      ? "You're a moderator"
      : 'View only';
}

/// One person's ban from one Daily. A ban only ever applies to the Daily
/// it was given in.
class DailyBan {
  final String uid;
  final String username;
  final String bannedBy;
  final String bannedByName;
  final String reason;
  final DateTime? until; // null = permanent
  final DateTime? createdAt;

  const DailyBan({
    required this.uid,
    required this.username,
    required this.bannedBy,
    required this.bannedByName,
    required this.reason,
    required this.until,
    required this.createdAt,
  });

  bool get isPermanent => until == null;

  /// Still in effect (a temporary ban ends on its own).
  bool get isActive => until == null || until!.isAfter(DateTime.now());

  factory DailyBan.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return DailyBan(
      uid: d.id,
      username: m['username'] as String? ?? 'Unknown',
      bannedBy: m['bannedBy'] as String? ?? '',
      bannedByName: m['bannedByName'] as String? ?? '',
      reason: m['reason'] as String? ?? '',
      until: (m['until'] as Timestamp?)?.toDate(),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// "Permanent", "3 days left", "5 hours left", "Ended".
  String get timeLeft {
    if (until == null) return 'Permanent';
    final left = until!.difference(DateTime.now());
    if (left.isNegative) return 'Ended';
    if (left.inDays >= 1) {
      return '${left.inDays} day${left.inDays == 1 ? '' : 's'} left';
    }
    if (left.inHours >= 1) {
      return '${left.inHours} hour${left.inHours == 1 ? '' : 's'} left';
    }
    final m = left.inMinutes < 1 ? 1 : left.inMinutes;
    return '$m minute${m == 1 ? '' : 's'} left';
  }
}

/// Moderators and bans for Dailies.
///
/// Firestore:
///   dailies/{dailyId}.moderatorUids        [uid, ...]   (owner sets)
///   dailies/{dailyId}/daily_bans/{uid}     {username, bannedBy,
///                                           bannedByName, reason, until
///                                           (null = permanent), createdAt}
///
/// Banning someone removes them from the Daily (their invitation is marked
/// 'banned'), and while the ban lasts they can't post, re-add it, or be
/// invited back. Unbanning (or a temporary ban running out) doesn't put
/// them back: they rejoin like anyone else.
class DailyModeration {
  DailyModeration._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String? get _me => FirebaseAuth.instance.currentUser?.uid;

  static DocumentReference<Map<String, dynamic>> _daily(String id) =>
      _db.collection('dailies').doc(id);

  static CollectionReference<Map<String, dynamic>> _bans(String id) =>
      _daily(id).collection('daily_bans');

  // ─── Roles ────────────────────────────────────────────────────────────────

  /// Live list of this Daily's moderators.
  static Stream<List<String>> watchModerators(String dailyId) =>
      _daily(dailyId).snapshots().map((s) =>
      List<String>.from(s.data()?['moderatorUids'] as List? ?? const []));

  /// Live permissions for the signed-in person in [daily].
  static Stream<DailyPermissions> watchPermissions(DailyData daily) async* {
    final me = _me;
    if (me == null) {
      yield DailyPermissions.none;
      return;
    }
    if (await _isOwner(daily, me)) {
      yield const DailyPermissions(DailyRole.owner);
      return;
    }
    yield* watchModerators(daily.id).map((mods) => DailyPermissions(
        mods.contains(me) ? DailyRole.moderator : DailyRole.member));
  }

  /// The creator. Older Dailies without a saved creator fall back to the
  /// old check (no accepted invitation = you made it).
  static Future<bool> _isOwner(DailyData daily, String uid) async {
    final creator = daily.creatorUid;
    if (creator != null && creator.isNotEmpty) return creator == uid;
    try {
      final invite = await _db
          .collection('daily_invitations')
          .where('dailyId', isEqualTo: daily.id)
          .where('toUserId', isEqualTo: uid)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();
      return invite.docs.isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Owner only: make [uid] a moderator, or stop them being one.
  static Future<void> setModerator(DailyData daily, String uid, bool on) {
    return _daily(daily.id).set({
      // Saved alongside so security rules can tell who the owner is.
      'ownerUid': _me,
      'moderatorUids':
      on ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
    }, SetOptions(merge: true));
  }

  // ─── Bans ─────────────────────────────────────────────────────────────────

  /// Everyone banned from this Daily, newest first (ended temporary bans
  /// included; check [DailyBan.isActive]).
  static Stream<List<DailyBan>> watchBans(String dailyId) => _bans(dailyId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(DailyBan.fromDoc).toList());

  /// The signed-in person's ban from this Daily, if any is in effect.
  static Stream<DailyBan?> watchMyBan(String dailyId) {
    final me = _me;
    if (me == null) return Stream.value(null);
    return _bans(dailyId).doc(me).snapshots().map((d) {
      if (!d.exists) return null;
      final ban = DailyBan.fromDoc(d);
      return ban.isActive ? ban : null;
    }).handleError((_) => null);
  }

  /// One-time check (before joining or posting).
  static Future<DailyBan?> myBan(String dailyId) async {
    final me = _me;
    if (me == null) return null;
    try {
      final d = await _bans(dailyId).doc(me).get();
      if (!d.exists) return null;
      final ban = DailyBan.fromDoc(d);
      return ban.isActive ? ban : null;
    } catch (_) {
      return null;
    }
  }

  /// Bans [uid] from the Daily for [duration] (null = permanent).
  static Future<void> ban({
    required String dailyId,
    required String uid,
    required String username,
    Duration? duration,
    String reason = '',
  }) async {
    final me = _me;
    if (me == null || uid == me) return;
    final myName = (await UserService().getUserById(me))?.username ?? '';

    final batch = _db.batch();
    batch.set(_bans(dailyId).doc(uid), {
      'username': username,
      'bannedBy': me,
      'bannedByName': myName,
      'reason': reason.trim(),
      'until': duration == null
          ? null
          : Timestamp.fromDate(DateTime.now().add(duration)),
      'createdAt': FieldValue.serverTimestamp(),
    });
    // A banned moderator stops being one (only the owner can ban a
    // moderator, so moderators never touch this list).
    final mods = List<String>.from(
        (await _daily(dailyId).get()).data()?['moderatorUids'] as List? ??
            const []);
    if (mods.contains(uid)) {
      batch.set(
          _daily(dailyId),
          {'moderatorUids': FieldValue.arrayRemove([uid])},
          SetOptions(merge: true));
    }

    // Out of the Daily: their membership / pending invite ends.
    final invites = await _db
        .collection('daily_invitations')
        .where('dailyId', isEqualTo: dailyId)
        .where('toUserId', isEqualTo: uid)
        .get();
    for (final d in invites.docs) {
      final status = d.data()['status'];
      if (status == 'accepted' || status == 'pending') {
        batch.update(d.reference, {'status': 'banned'});
      }
    }
    await batch.commit();
  }

  /// Owner / moderator removing someone else's post. Gone for everyone,
  /// files included.
  static Future<bool> deleteMessage(String dailyId, String messageId) =>
      MessageStorage.deleteMessage(dailyId, messageId);

  /// Lifts a ban. They aren't put back in the Daily; they can rejoin.
  static Future<void> unban(String dailyId, String uid) async {
    final batch = _db.batch();
    batch.delete(_bans(dailyId).doc(uid));
    final invites = await _db
        .collection('daily_invitations')
        .where('dailyId', isEqualTo: dailyId)
        .where('toUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'banned')
        .get();
    for (final d in invites.docs) {
      batch.update(d.reference, {'status': 'removed'});
    }
    await batch.commit();
  }
}