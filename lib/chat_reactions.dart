import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:lottie/lottie.dart';

// Reaction model
class ChatReaction {
  final String emoji;
  final String userId;
  final String username;
  final DateTime timestamp;

  ChatReaction({
    required this.emoji,
    required this.userId,
    required this.username,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'emoji': emoji,
    'user_id': userId,
    'username': username,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ChatReaction.fromJson(Map<String, dynamic> json) => ChatReaction(
    emoji: json['emoji'] ?? '',
    userId: json['user_id'] ?? '',
    username: json['username'] ?? '',
    timestamp: json['timestamp'] is String
        ? DateTime.parse(json['timestamp'])
        : DateTime.now(),
  );
}

class ReactionEmojis {
  static const List<String> emojis = [
    '🔥', '❤️', '😂', '😢', '👎', '👍', '🙄', '🤑', '😎', '🤫', '💀',
  ];
}

class AnimatedReactionEmoji extends StatelessWidget {
  final String emoji;
  final double size;

  const AnimatedReactionEmoji({Key? key, required this.emoji, this.size = 24}) : super(key: key);

  String? _getAnimationPath(String emoji) {
    switch (emoji) {
      case '🔥': return 'assets/animations/Fire.json';
      case '❤️': return 'assets/animations/Heart.json';
      case '😂': return 'assets/animations/laugh.json';
      case '😢': return 'assets/animations/Crying.json';
      case '👎': return 'assets/animations/ThumbsDown.json';
      case '👍': return 'assets/animations/ThumbsUp.json';
      case '🙄': return 'assets/animations/eyeroll.json';
      case '🤑': return 'assets/animations/Money.json';
      case '😎': return 'assets/animations/Cool.json';
      case '🤫': return 'assets/animations/Shush.json';
      case '💀': return 'assets/animations/Skull.json';
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final animationPath = _getAnimationPath(emoji);
    if (animationPath != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Lottie.asset(animationPath, fit: BoxFit.contain),
      );
    }
    return Text(emoji, style: TextStyle(fontSize: size));
  }
}

class ReactionPicker extends StatelessWidget {
  final Function(String) onReactionSelected;
  const ReactionPicker({Key? key, required this.onReactionSelected}) : super(key: key);

  // Never wider than the screen minus a margin on each side; on narrower
  // phones the emojis shrink just enough to fit (11 at full size need
  // ~460px, wider than most phones).
  static const double _screenMargin = 12;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width - _screenMargin * 2;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: context.isDark ? context.colors.surfaceMuted : context.colors.surface,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: ReactionEmojis.emojis.map((emoji) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onReactionSelected(emoji),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// Reactions sit on their own under the message, with no bubble around them.
class MessageReactionsDisplay extends StatelessWidget {
  final List<ChatReaction> reactions;
  final String currentUserId;
  final Function(String)? onReactionTap;

  const MessageReactionsDisplay({
    Key? key,
    required this.reactions,
    required this.currentUserId,
    this.onReactionTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    final Map<String, List<ChatReaction>> grouped = {};
    for (var r in reactions) {
      grouped.putIfAbsent(r.emoji, () => []).add(r);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: grouped.entries.map((entry) {
          final emoji = entry.key;
          final count = entry.value.length;

          return GestureDetector(
            onTap: () => onReactionTap?.call(emoji),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedReactionEmoji(emoji: emoji, size: 22),
                if (count > 1) ...[
                  const SizedBox(width: 3),
                  Text(count.toString(),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: context.colors.text)),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}