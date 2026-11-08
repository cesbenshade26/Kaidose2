import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum PinResult { pinned, full, error }

class PinnedRef {
  final String dailyId;
  final String messageId;

  /// When it was pinned (milliseconds). Earlier pins show first.
  final int at;

  const PinnedRef(this.dailyId, this.messageId, this.at);
}

/// Which of your Daily posts are pinned to the top of the Dailies tab on
/// your profile (up to [maxPins]).
///
/// Saved on your own user record (users/{uid}.pinnedPosts) rather than on the
/// message itself: a Daily rewrites its messages whenever anyone saves, which
/// would quietly wipe a pin stored there.
class PinnedPosts {
  static const int maxPins = 3;

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>>? get _myRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid);
  }

  static List<PinnedRef> _parse(dynamic raw) {
    if (raw is! List) return [];
    final out = <PinnedRef>[];
    for (final e in raw) {
      if (e is Map &&
          e['dailyId'] is String &&
          e['messageId'] is String) {
        out.add(PinnedRef(
          e['dailyId'] as String,
          e['messageId'] as String,
          (e['at'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// Someone's pins, earliest pin first.
  static Future<List<PinnedRef>> load(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return _parse(doc.data()?['pinnedPosts']);
    } catch (e) {
      print('PinnedPosts: load error: $e');
      return [];
    }
  }

  static Future<PinResult> pin(String dailyId, String messageId) async {
    final ref = _myRef;
    if (ref == null) return PinResult.error;
    try {
      return await _db.runTransaction<PinResult>((tx) async {
        final snap = await tx.get(ref);
        final raw = snap.data()?['pinnedPosts'];
        final current = raw is List ? List<dynamic>.from(raw) : <dynamic>[];

        final already = current.any((e) => e is Map && e['messageId'] == messageId);
        if (already) return PinResult.pinned;
        if (current.length >= maxPins) return PinResult.full;

        current.add({
          'dailyId': dailyId,
          'messageId': messageId,
          'at': DateTime.now().millisecondsSinceEpoch,
        });
        tx.update(ref, {'pinnedPosts': current});
        return PinResult.pinned;
      });
    } catch (e) {
      print('PinnedPosts: pin error: $e');
      return PinResult.error;
    }
  }

  static Future<bool> unpin(String messageId) async {
    final ref = _myRef;
    if (ref == null) return false;
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final raw = snap.data()?['pinnedPosts'];
        if (raw is! List) return;
        final kept = raw
            .where((e) => !(e is Map && e['messageId'] == messageId))
            .toList();
        if (kept.length != raw.length) {
          tx.update(ref, {'pinnedPosts': kept});
        }
      });
      return true;
    } catch (e) {
      print('PinnedPosts: unpin error: $e');
      return false;
    }
  }
}