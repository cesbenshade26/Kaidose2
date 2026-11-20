import 'MusicSearch.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'StoryMediaItem.dart';
import 'SafetyService.dart';

class FriendDailyService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static String? get currentUid => _auth.currentUser?.uid;
  static String get _today => DateTime.now().toIso8601String().split('T')[0];

  // ─── Compress helper (photos only) ─────────────────────────────────────────

  static Future<List<int>?> _compress(File photo) async {
    return FlutterImageCompress.compressWithFile(
      photo.absolute.path,
      minWidth: 600,
      minHeight: 800,
      quality: 65,
      format: CompressFormat.jpeg,
    );
  }

  // ─── Video upload helper ────────────────────────────────────────────────────

  /// Uploads a video to Storage and returns its download URL.
  static Future<String?> _uploadVideo(File video, String pathSegment) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('daily_story_videos/$pathSegment/$timestamp.mp4');
      await ref.putFile(video, SettableMetadata(contentType: 'video/mp4'));
      return await ref.getDownloadURL();
    } catch (e) {
      print('FriendDailyService: video upload error: $e');
      return null;
    }
  }

  // ─── Public story (Daily Post) ──────────────────────────────────────────────

  /// Upload to the current user's public daily story so ALL friends can see it.
  static Future<void> uploadMyDailyPhoto(File photo,
      {MusicTrack? music, Map<String, dynamic>? source}) async {
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
        'mediaType': 'photo',
        'base64Data': base64String,
        'date': _today,
        if (music != null) 'music': music.toMap(),
        // Added from a Daily: {dailyId, dailyTitle, private}
        if (source != null) 'source': source,
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

      print('FriendDailyService: Uploaded public photo story for $uid');
    } catch (e) {
      print('FriendDailyService: Upload error: $e');
    }
  }

  /// Upload a video to the current user's public daily story. Unlike
  /// photos, the video itself goes to Storage — only its URL is written
  /// to Firestore, since a compressed video would still blow past
  /// Firestore's 1MB document limit if stored inline like a photo is.
  static Future<void> uploadMyDailyVideo(File video,
      {MusicTrack? music, Map<String, dynamic>? source}) async {
    final uid = currentUid;
    if (uid == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final username = userDoc.data()?['username'] ?? 'Unknown';

      final videoUrl = await _uploadVideo(video, '$uid/$_today');
      if (videoUrl == null) return;

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
        'mediaType': 'video',
        'videoUrl': videoUrl,
        'date': _today,
        if (music != null) 'music': music.toMap(),
        // Added from a Daily: {dailyId, dailyTitle, private}
        if (source != null) 'source': source,
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

      print('FriendDailyService: Uploaded public video story for $uid');
    } catch (e) {
      print('FriendDailyService: Video upload error: $e');
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
          'mediaType': 'photo',
          'base64Data': base64String,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();

      print('FriendDailyService: Shared photo story with ${friendUids.length} friends');
    } catch (e) {
      print('FriendDailyService: Share error: $e');
    }
  }

  /// Send a story video only to specific friends — same inbox doc shape as
  /// sharePhotoWithFriends, just with a Storage URL instead of base64.
  static Future<void> shareVideoWithFriends(
      File video, List<String> friendUids) async {
    final uid = currentUid;
    if (uid == null || friendUids.isEmpty) return;

    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final username = userDoc.data()?['username'] ?? 'Unknown';

      final videoUrl = await _uploadVideo(video, '$uid/shared');
      if (videoUrl == null) return;

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
          'mediaType': 'video',
          'videoUrl': videoUrl,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();

      print('FriendDailyService: Shared video story with ${friendUids.length} friends');
    } catch (e) {
      print('FriendDailyService: Video share error: $e');
    }
  }

  // ─── Checking story existence ───────────────────────────────────────────────

  /// True if the given user has a public story today.
  static Future<bool> userHasPublicStoryToday(String userId) async {
    if (currentUid == null) return false;
    // They hid their story from me (or one of us blocked the other).
    if (await SafetyService.instance.isStoryHiddenFromMe(userId)) return false;
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
    if (SafetyService.instance.isHidden(userId)) return false;
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

  // ─── Fetching story media ───────────────────────────────────────────────────

  /// Get all story media for a friend today — public + any targeted to me.
  /// Photos are decoded from base64 straight to a local file; videos are
  /// downloaded from their Storage URL to a local file — either way the
  /// caller gets a ready-to-play local File, wrapped with a type flag.
  static Future<List<StoryMediaItem>> getFriendStoryPhotos(String userId) async {
    if (currentUid == null) return [];
    try {
      final directory = await getApplicationDocumentsDirectory();
      final List<StoryMediaItem> items = [];
      final safety = SafetyService.instance;
      if (safety.isHidden(userId)) return [];
      final publicHidden = await safety.isStoryHiddenFromMe(userId);

      // 1. Public story items (unless they hid their story from me)
      final publicDocs = publicHidden
          ? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]
          : (await _firestore
          .collection('users')
          .doc(userId)
          .collection('daily_story')
          .doc(_today)
          .collection('photos')
          .orderBy('timestamp', descending: false)
          .get())
          .docs;

      for (final doc in publicDocs) {
        final data = doc.data();
        final mediaType = data['mediaType'] as String? ?? 'photo';

        if (mediaType == 'video') {
          final videoUrl = data['videoUrl'] as String?;
          if (videoUrl == null) continue;
          final file = File('${directory.path}/friend_story_${userId}_pub_${doc.id}.mp4');
          try {
            await _storage.refFromURL(videoUrl).writeToFile(file);
            items.add(StoryMediaItem(
                file: file,
                isVideo: true,
                music: MusicTrack.fromMap(data['music']),
                source: _source(data)));
          } catch (e) {
            print('FriendDailyService: video download error: $e');
          }
        } else {
          final b64 = data['base64Data'] as String?;
          if (b64 == null) continue;
          final file = File('${directory.path}/friend_story_${userId}_pub_${doc.id}.jpg');
          await file.writeAsBytes(base64Decode(b64));
          items.add(StoryMediaItem(
              file: file,
              isVideo: false,
              music: MusicTrack.fromMap(data['music']),
              source: _source(data)));
        }
      }

      // 2. Targeted (inbox) item — single doc per sender per day
      final inboxDoc = await _firestore
          .collection('users')
          .doc(currentUid)
          .collection('friend_story_inbox')
          .doc('${userId}_$_today')
          .get();

      if (inboxDoc.exists) {
        final data = inboxDoc.data()!;
        final mediaType = data['mediaType'] as String? ?? 'photo';

        if (mediaType == 'video') {
          final videoUrl = data['videoUrl'] as String?;
          if (videoUrl != null) {
            final file = File('${directory.path}/friend_story_${userId}_inbox.mp4');
            try {
              await _storage.refFromURL(videoUrl).writeToFile(file);
              items.add(StoryMediaItem(file: file, isVideo: true));
            } catch (e) {
              print('FriendDailyService: inbox video download error: $e');
            }
          }
        } else {
          final b64 = data['base64Data'] as String?;
          if (b64 != null) {
            final file = File('${directory.path}/friend_story_${userId}_inbox.jpg');
            await file.writeAsBytes(base64Decode(b64));
            items.add(StoryMediaItem(file: file, isVideo: false));
          }
        }
      }

      return items;
    } catch (e) {
      print('FriendDailyService: Error fetching friend story: $e');
      return [];
    }
  }

  static Map<String, dynamic>? _source(Map<String, dynamic> data) =>
      data['source'] is Map
          ? Map<String, dynamic>.from(data['source'] as Map)
          : null;

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

  // ─── Who viewed / liked your story ──────────────────────────────────────────
  //
  // users/{owner}/daily_story/{day}/viewers/{viewerUid} {uid, username, viewedAt}
  // users/{owner}/daily_story/{day}/likes/{likerUid}    {uid, username, likedAt}
  //
  // Only the owner can read the lists (a liker can also read their own like,
  // to show the sun filled in). A new like notifies the owner (Cloud
  // Function notifyStoryLike).

  static String? _myUsername;

  static Future<String> _myName() async {
    final cached = _myUsername;
    if (cached != null) return cached;
    try {
      final doc = await _firestore.collection('users').doc(currentUid).get();
      final name = doc.data()?['username'] as String?;
      if (name != null && name.isNotEmpty) _myUsername = name;
      return name ?? 'Someone';
    } catch (_) {
      return 'Someone';
    }
  }

  static DocumentReference<Map<String, dynamic>> _dayRef(String ownerUid) =>
      _firestore
          .collection('users')
          .doc(ownerUid)
          .collection('daily_story')
          .doc(_today);

  /// Puts you on [ownerUid]'s viewer list for today's story.
  static Future<void> recordStoryView(String ownerUid) async {
    final uid = currentUid;
    if (uid == null || uid == ownerUid) return;
    try {
      await _dayRef(ownerUid).collection('viewers').doc(uid).set({
        'uid': uid,
        'username': await _myName(),
        'viewedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('FriendDailyService: record view error: $e');
    }
  }

  /// Whether you've given [ownerUid]'s story today a sun.
  static Future<bool> isStoryLiked(String ownerUid) async {
    final uid = currentUid;
    if (uid == null) return false;
    try {
      final doc =
      await _dayRef(ownerUid).collection('likes').doc(uid).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Gives (or takes back) a sun on [ownerUid]'s story today.
  static Future<void> setStoryLiked(String ownerUid, bool liked) async {
    final uid = currentUid;
    if (uid == null || uid == ownerUid) return;
    final ref = _dayRef(ownerUid).collection('likes').doc(uid);
    try {
      if (liked) {
        await ref.set({
          'uid': uid,
          'username': await _myName(),
          'likedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await ref.delete();
      }
    } catch (e) {
      print('FriendDailyService: like error: $e');
    }
  }

  /// Everyone who has seen your story today, newest first, with whether
  /// they gave it a sun. Updates live.
  static Stream<List<StoryViewer>> myStoryViewers() {
    final uid = currentUid;
    if (uid == null) return Stream.value(const <StoryViewer>[]);
    final day = _dayRef(uid);

    late final StreamController<List<StoryViewer>> out;
    StreamSubscription? viewersSub;
    StreamSubscription? likesSub;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? viewers;
    var likes = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    void emit() {
      final seen = viewers;
      if (seen == null || out.isClosed) return;
      final list = <StoryViewer>[];
      final ids = <String>{};
      for (final d in seen) {
        ids.add(d.id);
        final m = d.data();
        list.add(StoryViewer(
          uid: d.id,
          username: (m['username'] as String?) ?? 'Someone',
          time: (m['viewedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          liked: likes.containsKey(d.id),
        ));
      }
      // A like whose view didn't save still counts.
      likes.forEach((id, d) {
        if (ids.contains(id)) return;
        final m = d.data();
        list.add(StoryViewer(
          uid: id,
          username: (m['username'] as String?) ?? 'Someone',
          time: (m['likedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          liked: true,
        ));
      });
      list.sort((a, b) => b.time.compareTo(a.time));
      out.add(list);
    }

    out = StreamController<List<StoryViewer>>(
      onListen: () {
        viewersSub = day.collection('viewers').snapshots().listen((s) {
          viewers = s.docs;
          emit();
        }, onError: (e) {
          print('FriendDailyService: viewers stream error: $e');
          viewers ??= const [];
          emit();
        });
        likesSub = day.collection('likes').snapshots().listen((s) {
          likes = {for (final d in s.docs) d.id: d};
          emit();
        }, onError: (e) {
          print('FriendDailyService: likes stream error: $e');
        });
      },
      onCancel: () async {
        await viewersSub?.cancel();
        await likesSub?.cancel();
      },
    );
    return out.stream;
  }
}

/// One person on your story's viewer list.
class StoryViewer {
  final String uid;
  final String username;
  final DateTime time;
  final bool liked;

  const StoryViewer({
    required this.uid,
    required this.username,
    required this.time,
    required this.liked,
  });
}

extension StartWithFuture<T> on Stream<T> {
  Stream<T> startWithFuture(Future<T> future) async* {
    yield await future;
    yield* this;
  }
}