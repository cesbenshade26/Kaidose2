import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class FriendDailyService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? get currentUid => _auth.currentUser?.uid;
  static String get _today => DateTime.now().toIso8601String().split('T')[0];

  // ─── Compress helper ────────────────────────────────────────────────────────

  static Future<List<int>?> _compress(File photo) async {
    return FlutterImageCompress.compressWithFile(
      photo.absolute.path,
      minWidth: 600,
      minHeight: 800,
      quality: 65,
      format: CompressFormat.jpeg,
    );
  }

  // ─── Public story (Daily Post) ──────────────────────────────────────────────

  /// Upload to the current user's public daily story so ALL friends can see it.
  static Future<void> uploadMyDailyPhoto(File photo) async {
    final uid = currentUid;
    if (uid == null) return;

    try {
      final compressed = await _compress(photo);
      if (compressed == null) return;

      final base64String = base64Encode(compressed);
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final username = userDoc.data()?['username'] ?? 'Unknown';

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('daily_story')
          .doc(_today)
          .collection('photos')
          .add({
        'userId': uid,
        'username': username,
        'timestamp': FieldValue.serverTimestamp(),
        'base64Data': base64String,
        'date': _today,
      });

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('daily_story')
          .doc(_today)
          .set({
        'hasStory': true,
        'date': _today,
        'username': username,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('FriendDailyService: Uploaded public story for $uid');
    } catch (e) {
      print('FriendDailyService: Upload error: $e');
    }
  }

  // ─── Targeted story (Share with Friends) ───────────────────────────────────

  /// Send a story photo only to specific friends.
  /// Written into each friend's inbox: users/{friendUid}/friend_story_inbox/{myUid}_{today}
  static Future<void> sharePhotoWithFriends(
      File photo, List<String> friendUids) async {
    final uid = currentUid;
    if (uid == null || friendUids.isEmpty) return;

    try {
      final compressed = await _compress(photo);
      if (compressed == null) return;

      final base64String = base64Encode(compressed);
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final username = userDoc.data()?['username'] ?? 'Unknown';

      // Write into each selected friend's inbox
      final batch = _firestore.batch();
      for (final friendUid in friendUids) {
        final inboxRef = _firestore
            .collection('users')
            .doc(friendUid)
            .collection('friend_story_inbox')
            .doc('${uid}_$_today');

        batch.set(inboxRef, {
          'fromUserId': uid,
          'fromUsername': username,
          'date': _today,
          'base64Data': base64String,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();

      print('FriendDailyService: Shared story with ${friendUids.length} friends');
    } catch (e) {
      print('FriendDailyService: Share error: $e');
    }
  }

  // ─── Checking story existence ───────────────────────────────────────────────

  /// True if the given user has a public story today.
  static Future<bool> userHasPublicStoryToday(String userId) async {
    if (currentUid == null) return false;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('daily_story')
          .doc(_today)
          .get();
      return doc.exists && (doc.data()?['hasStory'] == true);
    } catch (e) {
      print('FriendDailyService: Error checking public story for $userId: $e');
      return false;
    }
  }

  /// True if the given user has sent a targeted story to the current user today.
  static Future<bool> userHasSharedStoryWithMe(String userId) async {
    final uid = currentUid;
    if (uid == null) return false;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('friend_story_inbox')
          .doc('${userId}_$_today')
          .get();
      return doc.exists;
    } catch (e) {
      print('FriendDailyService: Error checking inbox for $userId: $e');
      return false;
    }
  }

  /// True if the given user has EITHER a public story OR shared one with me.
  static Future<bool> userHasStoryToday(String userId) async {
    final hasPublic = await userHasPublicStoryToday(userId);
    if (hasPublic) return true;
    return await userHasSharedStoryWithMe(userId);
  }

  // ─── Stream of friends with stories ────────────────────────────────────────

  static Stream<Set<String>> getFriendsWithStoryToday(List<String> friendUserIds) {
    if (friendUserIds.isEmpty) return Stream.value(<String>{});
    if (currentUid == null) return Stream.value(<String>{});

    return Stream.periodic(const Duration(seconds: 30))
        .asyncMap((_) => _getFriendsWithStorySnapshot(friendUserIds))
        .startWithFuture(_getFriendsWithStorySnapshot(friendUserIds));
  }

  static Future<Set<String>> _getFriendsWithStorySnapshot(
      List<String> friendUserIds) async {
    if (currentUid == null) return <String>{};
    final Set<String> result = {};
    await Future.wait(
      friendUserIds.map((uid) async {
        if (await userHasStoryToday(uid)) result.add(uid);
      }),
    );
    return result;
  }

  // ─── Fetching photos ────────────────────────────────────────────────────────

  /// Get all photos for a friend's story today — public + any targeted to me.
  static Future<List<File>> getFriendStoryPhotos(String userId) async {
    if (currentUid == null) return [];
    try {
      final directory = await getApplicationDocumentsDirectory();
      final List<File> files = [];

      // 1. Public story photos
      final publicSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('daily_story')
          .doc(_today)
          .collection('photos')
          .orderBy('timestamp', descending: false)
          .get();

      for (final doc in publicSnap.docs) {
        final b64 = doc.data()['base64Data'] as String?;
        if (b64 == null) continue;
        final file = File(
            '${directory.path}/friend_story_${userId}_pub_${doc.id}.jpg');
        await file.writeAsBytes(base64Decode(b64));
        files.add(file);
      }

      // 2. Targeted (inbox) photo — single doc per sender per day
      final inboxDoc = await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('friend_story_inbox')
          .doc('${userId}_$_today')
          .get();

      if (inboxDoc.exists) {
        final b64 = inboxDoc.data()?['base64Data'] as String?;
        if (b64 != null) {
          final file = File(
              '${directory.path}/friend_story_${userId}_inbox.jpg');
          await file.writeAsBytes(base64Decode(b64));
          files.add(file);
        }
      }

      return files;
    } catch (e) {
      print('FriendDailyService: Error fetching friend story: $e');
      return [];
    }
  }

  // ─── Viewed tracking ────────────────────────────────────────────────────────

  static Future<void> markStoryViewed(String friendUserId) async {
    final uid = currentUid;
    if (uid == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('viewed_stories')
          .doc('${friendUserId}_$_today')
          .set({
        'viewedAt': FieldValue.serverTimestamp(),
        'friendUserId': friendUserId,
        'date': _today,
      });
    } catch (e) {
      print('FriendDailyService: Error marking viewed: $e');
    }
  }

  static Stream<Set<String>> getViewedStoriesStream() {
    final uid = currentUid;
    if (uid == null) return Stream.value(<String>{});

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('viewed_stories')
        .where('date', isEqualTo: _today)
        .snapshots()
        .handleError((e) {
      print('FriendDailyService: viewed_stories stream error: $e');
    })
        .map((snap) => snap.docs
        .map((d) => d.data()['friendUserId'] as String)
        .toSet());
  }
}

extension StartWithFuture<T> on Stream<T> {
  Stream<T> startWithFuture(Future<T> future) async* {
    yield await future;
    yield* this;
  }
}