import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'ProfilePicManager.dart';
import 'UserProfileScreen.dart';

/// A member's profile picture (falls back to the default head-and-shoulders).
/// Loaded once per user and cached for the session.
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

  static final Map<String, Uint8List?> _cache = {};

  @override
  State<MemberAvatar> createState() => _MemberAvatarState();
}

class _MemberAvatarState extends State<MemberAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.userId;
    if (MemberAvatar._cache.containsKey(id)) {
      _bytes = MemberAvatar._cache[id];
      return;
    }
    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(id).get();
      final b64 = doc.data()?['profilePicBase64'] as String?;
      final bytes = (b64 != null && b64.isNotEmpty) ? base64Decode(b64) : null;
      MemberAvatar._cache[id] = bytes;
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      MemberAvatar._cache[id] = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final Widget avatar = _bytes == null
        ? DefaultProfilePic(size: size, borderWidth: 0)
        : ClipOval(
      child: Image.memory(_bytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true),
    );
    if (!widget.openProfileOnTap) return avatar;
    return GestureDetector(
      onTap: () => UserProfileScreen.open(context, widget.userId,
          username: widget.username),
      child: avatar,
    );
  }
}