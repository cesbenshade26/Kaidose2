import 'package:flutter/material.dart';
import 'ManageGroupChat.dart';

/// Manage Chat for a 1:1 conversation. It is the same screen as the group
/// version, with the single other person as the only member.
class ManageChatScreen extends StatelessWidget {
  final String friendUserId;
  final String friendUsername;

  const ManageChatScreen({
    Key? key,
    required this.friendUserId,
    required this.friendUsername,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ManageGroupChatScreen.direct(
      friendUserId: friendUserId,
      friendUsername: friendUsername,
    );
  }
}