import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Something you saved: a Daily post or a clip. Only a pointer is kept
/// (users/{uid}/saved/{key}); the post or clip itself is read when shown,
/// so edits show up and deleted ones disappear.
///
///   key          post_{dailyId}_{messageId} | clip_{clipId}
///   kind         'post' | 'clip'
///   archiveIds   the Archives folders it's in. A post with none is saved
///                only in its Daily (the Daily's Saved screen).
///   savedAt
class SavedRef {
  final String key;
  final String kind;
  final String? dailyId;
  final String? messageId;
  final String? clipId;
  final List<String> archiveIds;
  final DateTime savedAt;

  const SavedRef({
    required this.key,
    required this.kind,
    this.dailyId,
    this.messageId,
    this.clipId,
    this.archiveIds = const [],
    required this.savedAt,
  });

  bool get isPost => kind == 'post';
  bool get isClip => kind == 'clip';

  factory SavedRef.from(String key, Map<String, dynamic> m) => SavedRef(
    key: key,
    kind: m['kind'] as String? ?? 'post',
    dailyId: m['dailyId'] as String?,
    messageId: m['messageId'] as String?,
    clipId: m['clipId'] as String?,
    archiveIds: List<String>.from(m['archiveIds'] ?? const []),
    savedAt: (m['savedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );
}

/// Everything you've saved, kept live while you're signed in (started in
/// main.dart), so bookmark icons know right away.
class SavedItems {
  SavedItems._();

  static final ValueNotifier<Map<String, SavedRef>> items =
  ValueNotifier<Map<String, SavedRef>>(const {});

  static String postKey(String dailyId, String messageId) =>
      'post_${dailyId}_$messageId';
  static String clipKey(String clipId) => 'clip_$clipId';

  static bool isPostSaved(String dailyId, String messageId) =>
      items.value.containsKey(postKey(dailyId, messageId));
  static bool isClipSaved(String clipId) =>
      items.value.containsKey(clipKey(clipId));
  static SavedRef? get(String key) => items.value[key];

  /// Newest first.
  static List<SavedRef> inFolder(String archiveId) => _sorted(
      items.value.values.where((r) => r.archiveIds.contains(archiveId)));
  static List<SavedRef> inDaily(String dailyId) => _sorted(items.value.values
      .where((r) => r.isPost && r.dailyId == dailyId));
  static int countIn(String archiveId) =>
      items.value.values.where((r) => r.archiveIds.contains(archiveId)).length;

  static List<SavedRef> _sorted(Iterable<SavedRef> it) =>
      it.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid).collection('saved');

  static StreamSubscription<User?>? _auth;
  static StreamSubscription? _sub;

  static void start() {
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      _sub?.cancel();
      _sub = null;
      items.value = const {};
      if (user == null) return;
      _sub = _ref(user.uid).limit(2000).snapshots().listen((snap) {
        items.value = {
          for (final d in snap.docs) d.id: SavedRef.from(d.id, d.data()),
        };
      }, onError: (e) => print('SavedItems: $e'));
      _migrateOld(user.uid);
    });
  }

  static void _setLocal(String key, SavedRef? ref) {
    final next = Map<String, SavedRef>.from(items.value);
    if (ref == null) {
      next.remove(key);
    } else {
      next[key] = ref;
    }
    items.value = next;
  }

  static Future<bool> savePost({
    required String dailyId,
    required String messageId,
    List<String> archiveIds = const [],
  }) =>
      _save(postKey(dailyId, messageId), {
        'kind': 'post',
        'dailyId': dailyId,
        'messageId': messageId,
      }, archiveIds);

  static Future<bool> saveClip(String clipId, List<String> archiveIds) =>
      _save(clipKey(clipId), {'kind': 'clip', 'clipId': clipId}, archiveIds);

  static Future<bool> _save(
      String key, Map<String, dynamic> fields, List<String> archiveIds) async {
    final uid = _uid;
    if (uid == null) return false;
    final old = items.value[key];
    _setLocal(key, SavedRef.from(key, {
      ...fields,
      'archiveIds': archiveIds,
      'savedAt': Timestamp.now(),
    }));
    try {
      await _ref(uid).doc(key).set({
        ...fields,
        'archiveIds': archiveIds,
        'savedAt': old == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(old.savedAt),
      });
      return true;
    } catch (e) {
      print('SavedItems.save: $e');
      _setLocal(key, old);
      return false;
    }
  }

  /// Which folders it's in. A clip in no folders is unsaved.
  static Future<bool> setFolders(String key, List<String> archiveIds) async {
    final uid = _uid;
    final old = items.value[key];
    if (uid == null || old == null) return false;
    if (old.isClip && archiveIds.isEmpty) return unsave(key);
    _setLocal(key, SavedRef(
      key: key, kind: old.kind, dailyId: old.dailyId,
      messageId: old.messageId, clipId: old.clipId,
      archiveIds: archiveIds, savedAt: old.savedAt,
    ));
    try {
      await _ref(uid).doc(key).update({'archiveIds': archiveIds});
      return true;
    } catch (e) {
      print('SavedItems.setFolders: $e');
      _setLocal(key, old);
      return false;
    }
  }

  static Future<bool> removeFromFolder(String key, String archiveId) {
    final old = items.value[key];
    if (old == null) return Future.value(false);
    return setFolders(
        key, old.archiveIds.where((id) => id != archiveId).toList());
  }

  static Future<bool> unsave(String key) async {
    final uid = _uid;
    if (uid == null) return false;
    final old = items.value[key];
    _setLocal(key, null);
    try {
      await _ref(uid).doc(key).delete();
      return true;
    } catch (e) {
      print('SavedItems.unsave: $e');
      _setLocal(key, old);
      return false;
    }
  }

  /// A folder is being deleted: take it off everything in it.
  static Future<void> removeFolderEverywhere(String archiveId) async {
    for (final r in inFolder(archiveId)) {
      await removeFromFolder(r.key, archiveId);
    }
  }

  // ─── The old system ─────────────────────────────────────────────────────
  // Saves used to be full copies at users/{uid}/archives/{id}/savedItems,
  // and "saved in this Daily" was a flag on the post itself (shared by
  // everyone). The copies are turned into pointers once per account.

  static Future<void> _migrateOld(String uid) async {
    final flag = 'saved_migrated_$uid';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(flag) == true) return;
      final folders =
      await _db.collection('users').doc(uid).collection('archives').get();
      for (final f in folders.docs) {
        final old = await f.reference.collection('savedItems').get();
        for (final d in old.docs) {
          final m = d.data();
          final msgId = (m['message_id'] ?? m['messageId'] ?? d.id).toString();
          final dailyId = (m['daily_id'] ?? m['dailyId'] ?? '').toString();
          final clip = dailyId == 'clip';
          if (!clip && (dailyId.isEmpty || dailyId == 'unknown_daily')) {
            await d.reference.delete();
            continue;
          }
          final key = clip ? clipKey(msgId) : postKey(dailyId, msgId);
          await _ref(uid).doc(key).set({
            'kind': clip ? 'clip' : 'post',
            if (clip) 'clipId': msgId else ...{
              'dailyId': dailyId,
              'messageId': msgId,
            },
            'archiveIds': FieldValue.arrayUnion([f.id]),
            'savedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          await d.reference.delete();
        }
      }
      await prefs.setBool(flag, true);
    } catch (e) {
      print('SavedItems: old saves not moved yet: $e');
    }
  }
}