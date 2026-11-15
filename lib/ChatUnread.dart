import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What's waiting for me in one chat, read from its Firestore doc.
class ChatActivity {
  /// kind -> count. Kinds: message, photo, clip, daily.
  final Map<String, int> counts;
  final String? lastPreview;
  final String? lastKind;
  final DateTime? lastTime;
  final String? lastSender;
  final bool muted;

  const ChatActivity({
    this.counts = const {},
    this.lastPreview,
    this.lastKind,
    this.lastTime,
    this.lastSender,
    this.muted = false,
  });

  int get total => counts.values.fold(0, (a, b) => a + b);
  bool get hasNew => total > 0;
}

/// Watches my 1:1 chat docs and remembers which friends/groups I've already
/// "met" (opened), so brand-new ones can say "New friend" / "New group".
class ChatUnreadService {
  ChatUnreadService._();
  static final ChatUnreadService instance = ChatUnreadService._();

  static const _knownKey = 'chat_known_ids_v1';

  /// friendUid -> activity
  Stream<Map<String, ChatActivity>> directActivity() {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return Stream.value(const {});
    return FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: me)
        .snapshots()
        .map((snap) {
      final out = <String, ChatActivity>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final parts = List<String>.from(d['participants'] ?? const []);
        final other = parts.firstWhere((p) => p != me, orElse: () => '');
        if (other.isEmpty) continue;
        final counts = <String, int>{};
        final raw = (d['unread'] is Map) ? (d['unread'] as Map)[me] : null;
        if (raw is Map) {
          raw.forEach((k, v) {
            if (v is num && v > 0) counts['$k'] = v.toInt();
          });
        }
        out[other] = ChatActivity(
          counts: counts,
          lastPreview: d['lastMessage'] as String?,
          lastKind: d['lastMessageKind'] as String?,
          lastTime: (d['lastMessageTime'] as Timestamp?)?.toDate(),
          lastSender: d['lastMessageSender'] as String?,
          muted: List<String>.from(d['mutedBy'] ?? const []).contains(me),
        );
      }
      return out;
    });
  }

  /// Null when this device has never recorded anything yet.
  Future<Set<String>?> loadKnown() async {
    try {
      final p = await SharedPreferences.getInstance();
      final l = p.getStringList(_knownKey);
      return l?.toSet();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveKnown(Set<String> ids) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_knownKey, ids.toList());
    } catch (_) {}
  }
}

/// The small palette the chat list uses. Mostly neutral; cyan only marks
/// "something is waiting for you".
class ChatColors {
  static const accent = Color(0xFF0097A7); // cyan[700]
  static const accentSoft = Color(0xFFEAF5F7); // avatar fill
  static const ink = Color(0xFF1C1C1E); // names
  static const sub = Color(0xFF8E8E93); // previews, times, icons
  static const line = Color(0xFFEFEFF1); // dividers
  static const mutedDot = Color(0xFFC7C7CC);
}

/// What kind of thing is new, as an icon + label.
class ChatBadge {
  final IconData icon;
  final String label;
  const ChatBadge(this.icon, this.label);

  static IconData iconFor(String kind) {
    switch (kind) {
      case 'photo':
        return Icons.photo_outlined;
      case 'clip':
        return Icons.play_circle_outline;
      case 'daily':
        return Icons.wb_sunny_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  static String _count(int n) => n > 9 ? '9+' : '$n';

  static String _one(String kind) {
    switch (kind) {
      case 'photo':
        return 'New photo';
      case 'clip':
        return 'New clip';
      case 'daily':
        return 'New Daily';
      default:
        return 'New message';
    }
  }

  static String _many(String kind, int n) {
    switch (kind) {
      case 'photo':
        return '${_count(n)} new photos';
      case 'clip':
        return '${_count(n)} new clips';
      case 'daily':
        return '${_count(n)} new Dailies';
      default:
        return '${_count(n)} new messages';
    }
  }

  static String _short(String kind, int n) {
    switch (kind) {
      case 'photo':
        return '${_count(n)} ${n == 1 ? 'photo' : 'photos'}';
      case 'clip':
        return '${_count(n)} ${n == 1 ? 'clip' : 'clips'}';
      case 'daily':
        return '${_count(n)} ${n == 1 ? 'Daily' : 'Dailies'}';
      default:
        return '${_count(n)} ${n == 1 ? 'message' : 'messages'}';
    }
  }

  /// Turns per-kind counts into one honest line.
  static ChatBadge? fromCounts(Map<String, int> counts) {
    const order = ['message', 'photo', 'clip', 'daily'];
    final kinds = order.where((k) => (counts[k] ?? 0) > 0).toList();
    if (kinds.isEmpty) return null;
    if (kinds.length == 1) {
      final k = kinds.first;
      final n = counts[k]!;
      return ChatBadge(iconFor(k), n == 1 ? _one(k) : _many(k, n));
    }
    final parts = kinds.take(2).map((k) => _short(k, counts[k]!)).toList();
    var label = parts.join(' · ');
    if (kinds.length > 2) label += ' +${kinds.length - 2}';
    // The most "special" kind leads the glyph: Daily > clip > photo > text.
    final lead = kinds.contains('daily')
        ? 'daily'
        : kinds.contains('clip')
        ? 'clip'
        : kinds.contains('photo')
        ? 'photo'
        : 'message';
    return ChatBadge(iconFor(lead), label);
  }
}

String chatAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${(d.inDays / 7).floor()}w';
}

/// Plain round avatar: soft tinted circle with the person's initial,
/// or a group glyph for group chats.
class ChatAvatar extends StatelessWidget {
  final String name;
  final bool group;
  final double size;
  const ChatAvatar({
    Key? key,
    required this.name,
    this.group = false,
    this.size = 50,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial =
    trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: ChatColors.accentSoft,
        shape: BoxShape.circle,
      ),
      child: group
          ? Icon(Icons.group_outlined,
          color: ChatColors.accent, size: size * 0.46)
          : Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: ChatColors.accent,
        ),
      ),
    );
  }
}

/// The line under a chat name when something is new:
/// small glyph + "3 new messages", in the accent (grey when muted).
class ChatStatusLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool muted;
  const ChatStatusLine({
    Key? key,
    required this.icon,
    required this.label,
    this.muted = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = muted ? ChatColors.sub : ChatColors.accent;
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// One row in the chat list: avatar, name + subtitle, time + unread dot,
/// and an optional menu button on the far right.
class ChatRow extends StatelessWidget {
  final Widget avatar;
  final String title;
  final Widget subtitle;
  final String time;
  final bool unread;
  final bool muted;
  final bool pinned;
  final Widget? menu;
  final VoidCallback onTap;
  final VoidCallback? onAvatarTap;

  const ChatRow({
    Key? key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.time = '',
    this.unread = false,
    this.muted = false,
    this.pinned = false,
    this.menu,
    this.onAvatarTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final highlight = unread && !muted;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, menu == null ? 16 : 0, 10),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAvatarTap,
                child: avatar,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w500,
                              color: ChatColors.ink,
                            ),
                          ),
                        ),
                        if (pinned) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.push_pin,
                              size: 13, color: ChatColors.sub),
                        ],
                        if (muted) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.notifications_off_outlined,
                              size: 14, color: ChatColors.sub),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    subtitle,
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                      highlight ? FontWeight.w600 : FontWeight.w400,
                      color: highlight ? ChatColors.accent : ChatColors.sub,
                    ),
                  ),
                  const SizedBox(height: 7),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: unread ? 1 : 0,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: muted ? ChatColors.mutedDot : ChatColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              if (menu != null) menu!,
            ],
          ),
        ),
      ),
    );
  }
}