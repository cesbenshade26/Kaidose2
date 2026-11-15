import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'ChatScreen.dart';
import 'GroupChatScreen.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'UponOpeningDaily.dart';
import 'InsideDaily.dart';

/// Push notifications on the phone side.
///
///  - Asks for permission (iOS, and Android 13+).
///  - Saves this phone's FCM token at users/{uid}/fcm_tokens/{token}, which
///    is where the Cloud Functions look when they send.
///  - Opens the right screen when a notification is tapped.
///
/// Sending never happens here; the Cloud Functions in functions/index.js
/// react to Firestore writes and do it.
///
/// Wired in at:
///   main.dart        MaterialApp(navigatorKey: NotificationService.navigatorKey)
///   Home.dart        NotificationService.instance.start()   (signed in)
///   SettingBar.dart  NotificationService.instance.stop()    (before logout)
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Lets a tapped notification navigate from outside any widget.
  static final GlobalKey<NavigatorState> navigatorKey =
  GlobalKey<NavigatorState>();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  bool _started = false;
  String? _token;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _openSub;

  /// Call once the user is signed in. Safe to call more than once.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      final settings = await _fm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print('NotificationService: permission denied');
        _started = false;
        return;
      }

      // While the app is open, the chat list / Dailies badges already show
      // what's new, so no banner pops over what the user is doing.
      await _fm.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );

      final token = await _getToken();
      if (token != null) await _saveToken(token);

      _refreshSub = _fm.onTokenRefresh.listen(_saveToken);

      // App was in the background and a notification was tapped.
      _openSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

      // App was fully closed and opened by tapping a notification.
      final initial = await _fm.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _handleTap(initial));
      }
    } catch (e) {
      print('NotificationService: start error: $e');
      _started = false;
    }
  }

  /// Call BEFORE signing out, so this phone stops getting the old
  /// account's notifications.
  Future<void> stop() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _refreshSub?.cancel();
    await _openSub?.cancel();
    _refreshSub = null;
    _openSub = null;
    try {
      if (uid != null && _token != null) {
        await _fs
            .collection('users')
            .doc(uid)
            .collection('fcm_tokens')
            .doc(_token)
            .delete();
      }
      await _fm.deleteToken();
    } catch (e) {
      print('NotificationService: stop error: $e');
    }
    _token = null;
    _started = false;
  }

  /// On iOS the FCM token only exists once Apple's (APNs) token has
  /// arrived, which can take a moment after launch.
  Future<String?> _getToken() async {
    if (Platform.isIOS) {
      for (var i = 0; i < 10; i++) {
        if (await _fm.getAPNSToken() != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    try {
      return await _fm.getToken();
    } catch (e) {
      print('NotificationService: getToken error: $e');
      return null;
    }
  }

  Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _token = token;
    try {
      await _fs
          .collection('users')
          .doc(uid)
          .collection('fcm_tokens')
          .doc(token)
          .set({
        'platform': Platform.isIOS ? 'ios' : 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('NotificationService: save token error: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Tap routing. Keys come from the `data` each Cloud Function sends.
  // ---------------------------------------------------------------------

  Future<void> _handleTap(RemoteMessage message) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final d = message.data;
    final type = d['type'];

    if (type == 'chat') {
      // New message, reaction, or a friend request that was accepted.
      final friendUid = d['friendUid'];
      if (friendUid == null || friendUid.isEmpty) return;
      nav.push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          friendUserId: friendUid,
          friendUsername: d['friendUsername'] ?? '',
        ),
      ));
    } else if (type == 'group') {
      final groupId = d['groupId'];
      if (groupId == null || groupId.isEmpty) return;
      nav.push(MaterialPageRoute(
        builder: (_) => GroupChatScreen(groupId: groupId),
      ));
    } else if (type == 'daily' ||
        type == 'daily_joined' ||
        type == 'join_accepted') {
      await _openDaily(nav, d['dailyId']);
    } else if (type == 'friend_request' ||
        type == 'daily_invite' ||
        type == 'join_request') {
      // Something to accept or decline.
      nav.pushNamed('/notifications');
    }
  }

  /// Opens one of the viewer's Dailies the same way tapping its card in
  /// My Dailies does: the entry prompt first if they haven't answered or
  /// skipped it today, otherwise straight inside.
  Future<void> _openDaily(NavigatorState nav, String? dailyId) async {
    if (dailyId == null || dailyId.isEmpty) return;

    DailyData? daily = await DailyList.getDailyById(dailyId);
    if (daily == null) {
      // Just accepted into it: the owner's app may still be copying the
      // Daily into this account. Give it a moment, then try once more.
      await Future.delayed(const Duration(seconds: 2));
      daily = await DailyList.getDailyById(dailyId);
    }
    if (!nav.mounted) return;
    if (daily == null) {
      nav.pushNamed('/notifications');
      return;
    }

    final viewed = await DailyList.hasBeenViewedToday(dailyId);
    if (!nav.mounted) return;

    if (!viewed && daily.dailyEntryPrompt.isNotEmpty) {
      nav.push(MaterialPageRoute(
        builder: (_) => UponOpeningDaily(daily: daily!),
      ));
    } else {
      await DailyList.markAsViewed(dailyId);
      if (!nav.mounted) return;
      nav.push(MaterialPageRoute(
        builder: (_) => InsideDaily(daily: daily!),
      ));
    }
  }
}