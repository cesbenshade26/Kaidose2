import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Settings → Privacy → Likes. Saved on users/{uid}.likePrefs:
///
///   hideMine    other people don't see like counts on your clips (the
///               server copies it onto each clip as `hideLikes`)
///   hideOthers  you don't see like counts on anyone else's clips
///   shareLikes  your likes show up in friends' Clips lens (on unless
///               switched off; turning it off removes the old ones too)
///
/// Started once in main.dart; follows whoever is signed in.
class LikePrefs {
  LikePrefs._();

  static final ValueNotifier<Map<String, bool>> values =
  ValueNotifier<Map<String, bool>>(const {});

  static bool get hideMine => values.value['hideMine'] == true;
  static bool get hideOthers => values.value['hideOthers'] == true;
  static bool get shareLikes => values.value['shareLikes'] != false;

  static StreamSubscription<User?>? _auth;
  static StreamSubscription? _doc;

  static void start() {
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      _doc?.cancel();
      _doc = null;
      values.value = const {};
      if (user == null) return;
      _doc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((s) {
        final raw = s.data()?['likePrefs'];
        final next = <String, bool>{};
        if (raw is Map) {
          raw.forEach((k, v) {
            if (v is bool) next['$k'] = v;
          });
        }
        if (!mapEquals(next, values.value)) values.value = next;
      }, onError: (_) {});
    });
  }

  static Future<void> set(String key, bool on) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    values.value = {...values.value, key: on}; // show it right away
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'likePrefs': {key: on},
    }, SetOptions(merge: true));
  }
}