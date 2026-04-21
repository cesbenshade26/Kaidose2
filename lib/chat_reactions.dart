import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ReactionEmojis.emojis.map((emoji) {
          return GestureDetector(
            onTap: () => onReactionSelected(emoji),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(emoji, style: const TextStyle(fontSize: 28)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

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
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: grouped.entries.map((entry) {
          final emoji = entry.key;
          final count = entry.value.length;
          final userReacted = entry.value.any((r) => r.userId == currentUserId);

          return GestureDetector(
            onTap: () => onReactionTap?.call(emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: userReacted ? Colors.cyan.withOpacity(0.1) : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedReactionEmoji(emoji: emoji, size: 22),
                  if (count > 1) ...[
                    const SizedBox(width: 4),
                    Text(count.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}