import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'BackgroundPic.dart';
import 'ProfilePicManager.dart';
import 'ProfileStatsRow.dart';
import 'UserBubbleRow.dart';

/// Another person's profile, laid out like your own Profile tab: banner
/// photo, avatar sitting on its lower edge, username, bio, then their Daily
/// Bubbles. The tabs (Dailies, Clips) get added here later.
///
/// Open it from anywhere another user is tappable with
/// [UserProfileScreen.open] so every entry point behaves the same.
class UserProfileScreen extends StatefulWidget {
  final String userId;

  /// Shown right away while the real profile loads.
  final String username;

  const UserProfileScreen({
    Key? key,
    required this.userId,
    this.username = '',
  }) : super(key: key);

  /// Pushes the profile screen. Does nothing if there's no user id to show.
  static void open(BuildContext context, String? userId, {String? username}) {
    if (userId == null || userId.isEmpty || userId == 'current_user') return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: userId,
          username: username ?? '',
        ),
      ),
    );
  }

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  String? _username;
  Uint8List? _avatar;
  Uint8List? _banner;
  String? _bio;
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _username = widget.username.isEmpty ? null : widget.username;
    _load();
  }

  Uint8List? _decode(dynamic b64) {
    if (b64 is! String || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (!mounted) return;
      if (!doc.exists) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }
      final data = doc.data() ?? {};
      setState(() {
        final name = data['username'] as String?;
        if (name != null && name.isNotEmpty) _username = name;
        _avatar = _decode(data['profilePicBase64']);
        _banner = _decode(data['backgroundPicBase64']);

        // Same lookup as BioManager: the plain `bio` field, then the old
        // formatted `bioData.text` for accounts that haven't re-saved.
        String? bio = data['bio'] as String?;
        if (bio == null || bio.trim().isEmpty) {
          final old = data['bioData'];
          if (old is Map) bio = old['text'] as String?;
        }
        _bio = (bio == null || bio.trim().isEmpty) ? null : bio.trim();

        _loading = false;
      });
    } catch (e) {
      print('UserProfileScreen: load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bannerHeight = BackgroundSpec.bannerHeight;
    const avatarSize = BackgroundSpec.avatarSize;

    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(
          color: Colors.white,
          shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Banner (their background photo, or the default gradient)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: bannerHeight,
            child: _banner != null
                ? Image.memory(
              _banner!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Container(
                  decoration: BackgroundSpec.defaultDecoration),
            )
                : Container(decoration: BackgroundSpec.defaultDecoration),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: bannerHeight,
            child: IgnorePointer(
              child: Container(decoration: BackgroundSpec.scrimDecoration),
            ),
          ),
          Positioned(
            top: bannerHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(color: Colors.white),
          ),

          // Scrolls if a long bio plus bubbles don't fit on a small screen.
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: bannerHeight - avatarSize / 2),
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[300],
                  ),
                  child: ClipOval(
                    child: _avatar != null
                        ? Image.memory(
                      _avatar!,
                      width: avatarSize,
                      height: avatarSize,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const DefaultProfilePic(
                          size: avatarSize, borderWidth: 0),
                    )
                        : const DefaultProfilePic(
                        size: avatarSize, borderWidth: 0),
                  ),
                ),
                const SizedBox(height: 8),
                if (!_notFound)
                  ProfileStatsRow(
                    userId: widget.userId,
                    username: _username ?? '',
                    showProgress: false,
                  ),
                if (!_notFound) ...[
                  const SizedBox(height: 10),
                  if (_bio != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          _bio!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.3,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    )
                  else
                  // No bio: keep the one line of space your own Profile uses
                  // (where it shows "Add a bio") so the bubbles sit at the
                  // same height on both screens.
                    const SizedBox(height: 15 * 1.3),
                ],
                if (!_notFound) ...[
                  const SizedBox(height: 8),
                  UserBubbleRow(userId: widget.userId),
                ],
                if (_notFound)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('This account no longer exists',
                        style: TextStyle(color: Colors.grey[600])),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}