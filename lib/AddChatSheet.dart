import 'package:flutter/material.dart';

enum AddChatOption { groupChat }

/// The "+" menu in Chats. Add more options to [AddChatOption] and the list
/// below as they come.
Future<AddChatOption?> showAddChatSheet(BuildContext context) {
  return showModalBottomSheet<AddChatOption>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _tile(
              context,
              icon: Icons.group_add_outlined,
              title: 'Group chat',
              subtitle: 'Chat with several friends at once',
              option: AddChatOption.groupChat,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

Widget _tile(
    BuildContext context, {
      required IconData icon,
      required String title,
      required String subtitle,
      required AddChatOption option,
    }) {
  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.cyan[700]),
    ),
    title: Text(title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle,
        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
    onTap: () => Navigator.pop(context, option),
  );
}