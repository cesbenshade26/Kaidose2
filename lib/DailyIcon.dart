import 'dart:io';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'DailyList.dart';

/// A Daily's custom icon lives in Firebase Storage, so everyone sees it.
/// `customIconPath` on the Daily holds its download URL. (Older Dailies
/// kept a path on the creator's phone instead; [migrateIfLocal] moves
/// those up the next time the owner sees the card.)
class DailyIconStore {
  DailyIconStore._();

  // Same folder as scheduled covers, which the Storage rules already allow.
  static Reference _folder(String dailyId) =>
      FirebaseStorage.instance.ref().child('daily_cover_thumbnails/$dailyId');

  static bool isRemote(String? path) =>
      path != null && (path.startsWith('http://') || path.startsWith('https://'));

  /// Uploads a picture as this Daily's icon (shrunk to 256px wide first,
  /// it's only ever shown small) and returns its URL. A URL passed in comes
  /// straight back. Throws if the upload fails.
  static Future<String> upload(String dailyId, String path) async {
    if (isRemote(path)) return path;
    final original = await File(path).readAsBytes();
    var bytes = original;
    var type = 'image/jpeg';
    try {
      final codec = await ui.instantiateImageCodec(original, targetWidth: 256);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png != null) {
        bytes = png.buffer.asUint8List();
        type = 'image/png';
      }
    } catch (_) {
      // Couldn't shrink it: upload as-is.
    }
    // New name each time, so a changed icon gets a new URL (no stale cache).
    final ref = _folder(dailyId).child(
        'icon_${DateTime.now().millisecondsSinceEpoch}.${type == 'image/png' ? 'png' : 'jpg'}');
    await ref.putData(bytes, SettableMetadata(contentType: type));
    return ref.getDownloadURL();
  }

  static final Set<String> _migrating = {};

  /// Owner only, once per session: a Daily whose icon is still a file on
  /// this phone gets it uploaded, so everyone else sees it too.
  static Future<void> migrateIfLocal(DailyData daily) async {
    final path = daily.customIconPath;
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (path == null || isRemote(path) || me == null) return;
    if (daily.creatorUid != null && daily.creatorUid != me) return;
    if (!File(path).existsSync() || !_migrating.add(daily.id)) return;
    try {
      final url = await upload(daily.id, path);
      await DailyList.updateDaily(withIcon(daily, url));
    } catch (e) {
      _migrating.remove(daily.id);
      print('DailyIconStore: migrate failed for ${daily.id}: $e');
    }
  }

  /// [daily] with a different custom icon (null = back to the preset).
  static DailyData withIcon(DailyData d, String? customIconPath) => DailyData(
    id: d.id,
    title: d.title,
    description: d.description,
    privacy: d.privacy,
    keywords: d.keywords,
    managementTiers: d.managementTiers,
    icon: d.icon,
    iconColor: d.iconColor,
    customIconPath: customIconPath,
    invitedFriendIds: d.invitedFriendIds,
    foundingMemberIds: d.foundingMemberIds,
    createdAt: d.createdAt,
    isPinned: d.isPinned,
    tierAssignments: d.tierAssignments,
    tierPrivileges: d.tierPrivileges,
    titleFont: d.titleFont,
    dailyEntryPrompt: d.dailyEntryPrompt,
    creatorUid: d.creatorUid,
  );
}

/// The custom picture itself, filling whatever box it's given: from
/// Storage (cached on disk) or, for older Dailies, from this phone.
/// [fallback] shows if there's nothing to show.
class DailyIconPicture extends StatelessWidget {
  final String path;
  final Widget fallback;

  const DailyIconPicture({Key? key, required this.path, required this.fallback})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (DailyIconStore.isRemote(path)) {
      return CachedNetworkImage(
        imageUrl: path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => fallback,
      );
    }
    final file = File(path);
    if (!file.existsSync()) return fallback;
    return Image.file(
      file,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

/// A Daily's icon tile, the same everywhere: light grey square with a dark
/// icon, or the custom picture.
class DailyIconTile extends StatelessWidget {
  final IconData icon;
  final String? customIconPath;
  final double size;
  final double radius;

  const DailyIconTile({
    Key? key,
    required this.icon,
    this.customIconPath,
    this.size = 56,
    this.radius = 12,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(icon, color: Colors.grey[800], size: size * 0.5);
    final path = customIconPath;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(radius),
      ),
      child: path == null
          ? glyph
          : ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DailyIconPicture(path: path, fallback: Center(child: glyph)),
      ),
    );
  }
}