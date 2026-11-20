import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'ChatUnread.dart' show ChatAvatar;

/// A group chat's picture: its photo if someone set one (Manage chat →
/// tap the picture), otherwise the usual group icon.
class GroupIcon extends StatelessWidget {
  final String? iconUrl;
  final String name;
  final double size;

  const GroupIcon({
    Key? key,
    required this.iconUrl,
    required this.name,
    this.size = 50,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final url = iconUrl;
    final fallback = ChatAvatar(name: name, group: true, size: size);
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * 3).round(),
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}