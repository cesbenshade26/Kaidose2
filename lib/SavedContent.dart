import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'SavedItemStorage.dart';
import 'SendDailyMessage.dart' show DailyMessage;
import 'clip_service.dart';

/// A saved Daily post, read fresh from its Daily.
class SavedPost {
  final SavedRef ref;
  final DailyMessage message;
  final String dailyId;
  final String dailyTitle;
  final Color color;
  const SavedPost(this.ref, this.message, this.dailyId, this.dailyTitle, this.color);
}

/// Turns saved pointers into the real posts and clips. Ones that were
/// deleted (or removed by moderation) are left out, and deleted ones are
/// unsaved so they don't keep counting.
class SavedContent {
  SavedContent._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static final Map<String, (String, Color)> _daily = {};

  /// A Daily's title and color (cached).
  static Future<(String, Color)> dailyInfo(String id) async {
    final hit = _daily[id];
    if (hit != null) return hit;
    try {
      final d = (await _db.collection('dailies').doc(id).get()).data() ?? {};
      final t = (d['title'] as String?)?.trim();
      final c = d['iconColor'];
      return _daily[id] = (
      (t == null || t.isEmpty) ? 'Daily' : t,
      Color(c is int ? c : 0xFF00BCD4),
      );
    } catch (_) {
      return ('Daily', const Color(0xFF00BCD4));
    }
  }

  /// Gone for good (not just offline): stop keeping it.
  static void _prune(SavedRef r, DocumentSnapshot doc) {
    if (!doc.exists && !doc.metadata.isFromCache) SavedItems.unsave(r.key);
  }

  static Future<List<SavedPost>> posts(List<SavedRef> refs) async {
    final found = await Future.wait(refs.where((r) => r.isPost).map((r) async {
      try {
        final doc = await _db
            .collection('dailies')
            .doc(r.dailyId)
            .collection('daily_messages')
            .doc(r.messageId)
            .get();
        final data = doc.data();
        if (data == null) {
          _prune(r, doc);
          return null;
        }
        if (data['hidden'] == true) return null;
        final m = DailyMessage.fromJson(data);
        if (!m.hasContent) return null;
        final info = await dailyInfo(r.dailyId!);
        return SavedPost(r, m, r.dailyId!, info.$1, info.$2);
      } catch (e) {
        print('SavedContent.posts: $e');
        return null;
      }
    }));
    return found.whereType<SavedPost>().toList();
  }

  static Future<List<(SavedRef, ClipData)>> clips(List<SavedRef> refs) async {
    final found = await Future.wait(refs.where((r) => r.isClip).map((r) async {
      try {
        final doc = await _db.collection('clips').doc(r.clipId).get();
        final data = doc.data();
        if (data == null) {
          _prune(r, doc);
          return null;
        }
        if (data['hidden'] == true) return null;
        return (r, ClipData.fromFirestore(data, doc.id));
      } catch (e) {
        print('SavedContent.clips: $e');
        return null;
      }
    }));
    return found.whereType<(SavedRef, ClipData)>().toList();
  }
}