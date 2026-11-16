import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'ProfilePicManager.dart';
import 'UserProfileScreen.dart';

/// Anyone's profile picture (falls back to the default head-and-shoulders).
/// Used everywhere a person shows up: chats, clips, comments, search,
/// Dailies.
///
/// Pictures live on each user's doc (profilePicBase64), so each person is
/// fetched ONCE per app session and kept in memory: a Daily with 40 messages
/// from 5 people costs 5 reads, not 40. Your own picture comes straight from
/// the copy on this phone, so it's instant and updates the moment you change
/// it.
class MemberAvatar extends StatefulWidget {
  final String userId;
  final double size;

  /// When true, tapping the avatar opens this person's profile.
  final bool openProfileOnTap;
  final String? username;

  const MemberAvatar({
    Key? key,
    required this.userId,
    this.size = 44,
    this.openProfileOnTap = false,
    this.username,
  }) : super(key: key);

  // uid -> picture bytes (null = they have none). Shared by every avatar.
  static final Map<String, Uint8List?> _cache = {};
  // uid -> the fetch already in progress, so 20 avatars for the same person
  // appearing at once share one read.
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  /// Forget someone's cached picture (e.g. after they change it).
  static void evict(String uid) {
    _cache.remove(uid);
    _inFlight.remove(uid);
  }

  /// Forget everyone (use when logging out).
  static void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }

  static Future<Uint8List?> _fetch(String uid) {
    return _inFlight.putIfAbsent(uid, () async {
      try {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final b64 = doc.data()?['profilePicBase64'] as String?;
        final bytes =
        (b64 != null && b64.isNotEmpty) ? base64Decode(b64) : null;
        _cache[uid] = bytes;
        return bytes;
      } catch (_) {
        return null; // not cached, so it's tried again next time
      } finally {
        _inFlight.remove(uid);
      }
    });
  }

  @override
  State<MemberAvatar> createState() => _MemberAvatarState();
}

class _MemberAvatarState extends State<MemberAvatar> {
  Uint8List? _bytes;
  VoidCallback? _ownListener;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  /// Old Daily messages saved your id as 'current_user'.
  bool get _isMe =>
      widget.userId == 'current_user' ||
          (_myUid != null && widget.userId == _myUid);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(MemberAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _stop();
      _bytes = null;
      _start();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    if (_isMe) {
      // Your own picture: follow the copy on this phone.
      _ownListener = () {
        if (mounted) setState(() {});
      };
      ProfilePicManager.addListener(_ownListener!);
      return;
    }
    final id = widget.userId;
    if (id.isEmpty) return;
    if (MemberAvatar._cache.containsKey(id)) {
      _bytes = MemberAvatar._cache[id];
      return;
    }
    MemberAvatar._fetch(id).then((bytes) {
      if (mounted && widget.userId == id) setState(() => _bytes = bytes);
    });
  }

  void _stop() {
    if (_ownListener != null) {
      ProfilePicManager.removeListener(_ownListener!);
      _ownListener = null;
    }
  }

  Widget _default() =>
      DefaultProfilePic(size: widget.size, borderWidth: 0);

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    Widget avatar;

    if (_isMe) {
      final File? file = ProfilePicManager.globalProfilePic;
      avatar = (file != null && file.existsSync())
          ? ClipOval(
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          // Small avatars decode small.
          cacheWidth: (size * 3).round(),
          key: ValueKey(file.path + file.lastModifiedSync().toString()),
          errorBuilder: (_, __, ___) => _default(),
        ),
      )
          : _default();
    } else {
      avatar = _bytes == null
          ? _default()
          : ClipOval(
        child: Image.memory(
          _bytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, __, ___) => _default(),
        ),
      );
    }

    avatar = SizedBox(width: size, height: size, child: avatar);
    if (!widget.openProfileOnTap || _isMe) return avatar;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => UserProfileScreen.open(context, widget.userId,
          username: widget.username),
      child: avatar,
    );
  }
}