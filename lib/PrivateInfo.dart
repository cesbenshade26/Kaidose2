import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Email, phone number and birthday: kept in user_private/{uid}, which
/// only that account can read (users/{uid} is readable by everyone signed
/// in, since it's the public profile).
///
/// Accounts made before this had them on users/{uid} and on their
/// usernames/ reservation. [start] (main.dart) moves them over the first
/// time each account opens the app, and makes sure username login still
/// works (login_lookup/). After that it's one quick read per launch.
class PrivateInfo {
  PrivateInfo._();

  static const List<String> fields = [
    'email', 'phone', 'birthYear', 'birthMonth', 'birthDay',
  ];

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> ref(String uid) =>
      _db.collection('user_private').doc(uid);

  /// The id a username has in usernames/ and login_lookup/ (same as
  /// AuthService uses): lowercased and URL-encoded.
  static String _usernameKey(String username) =>
      Uri.encodeComponent(username.trim().toLowerCase()).toLowerCase();

  static StreamSubscription<User?>? _auth;
  static String? _doneFor;

  static void start() {
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null || user.uid == _doneFor) return;
      _doneFor = user.uid;
      _tidy(user).catchError((e) {
        _doneFor = null; // try again next launch
        print('PrivateInfo: $e');
      });
    });
  }

  static Future<void> _tidy(User user) async {
    final uid = user.uid;
    final usersRef = _db.collection('users').doc(uid);
    final profile = (await usersRef.get()).data();
    if (profile == null) return; // still signing up

    // 1. Move private fields off the public profile.
    final moving = <String, dynamic>{
      for (final k in fields)
        if (profile.containsKey(k) && profile[k] != null && profile[k] != '')
          k: k == 'email'
              ? (profile[k] as String).trim().toLowerCase()
              : profile[k],
    };
    if (moving.isNotEmpty) {
      await ref(uid).set(moving, SetOptions(merge: true));
    }
    final stale = fields.where(profile.containsKey).toList();
    if (stale.isNotEmpty) {
      await usersRef.update({for (final k in stale) k: FieldValue.delete()});
    }

    // 2. Username login: login_lookup/{name} instead of the reservation.
    final username = profile['username'] as String? ?? '';
    if (username.isEmpty) return;
    final key = _usernameKey(username);
    final lookup = _db.collection('login_lookup').doc(key);
    if (!(await lookup.get()).exists) {
      final email = user.email ?? '';
      await lookup.set({
        'uid': uid,
        if (email.isNotEmpty) 'email': email else 'phoneAccount': true,
      });
    }
    final reservation = _db.collection('usernames').doc(key);
    final r = (await reservation.get()).data();
    if (r != null &&
        r['uid'] == uid &&
        (r.containsKey('email') || r.containsKey('phone'))) {
      await reservation.update({
        'email': FieldValue.delete(),
        'phone': FieldValue.delete(),
      });
    }
  }
}