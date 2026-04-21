import 'package:flutter/material.dart';
import 'message_service.dart';
import 'user_service.dart';
import 'chat_reactions.dart';

class ChatScreen extends StatefulWidget {
  final String friendUserId;
  final String friendUsername;

  const ChatScreen({Key? key, required this.friendUserId, required this.friendUsername}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessageService _messageService = MessageService();
  final UserService _userService = UserService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _chatInputFocusNode = FocusNode();

  String? _currentUsername;
  bool _isLoading = true;
  Message? _replyingTo;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _messageService.markChatMessagesAsRead(widget.friendUserId);
  }

  Future<void> _loadCurrentUser() async {
    final user = await _userService.getUserById(_messageService.currentUserId ?? '');
    if (mounted) setState(() { _currentUsername = user?.username ?? 'You'; _isLoading = false; });
  }

  @override
  void dispose() {
    _chatInputFocusNode.unfocus();
    _messageController.dispose();
    _scrollController.dispose();
    _chatInputFocusNode.dispose();
    super.dispose();
  }

  void _onReplyRequested(Message message) {
    setState(() => _replyingTo = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatInputFocusNode.canRequestFocus) _chatInputFocusNode.requestFocus();
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUsername == null) return;

    final pId = _replyingTo?.id;
    final pText = _replyingTo?.text;
    _messageController.clear();
    setState(() => _replyingTo = null);

    await _messageService.sendChatMessage(
      recipientUserId: widget.friendUserId,
      text: text,
      senderUsername: _currentUsername!,
      parentMessageId: pId,
      parentText: pText,
    );

    if (_scrollController.hasClients) {
      _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.friendUsername, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
                : StreamBuilder<List<Message>>(
              stream: _messageService.getChatMessages(widget.friendUserId),
              builder: (context, snapshot) {
                final messages = (snapshot.data ?? []).reversed.toList();
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => ChatMessageWidget(
                    key: ValueKey(messages[index].id),
                    message: messages[index],
                    isMe: messages[index].senderId == _messageService.currentUserId,
                    friendUserId: widget.friendUserId,
                    currentUsername: _currentUsername ?? 'You',
                    messageService: _messageService,
                    onReply: () => _onReplyRequested(messages[index]),
                  ),
                );
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade100))),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: const Border(left: BorderSide(color: Colors.cyan, width: 4))),
                child: Row(
                  children: [
                    Expanded(child: Text("Replying to: ${_replyingTo!.text}", maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _replyingTo = null)),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _chatInputFocusNode,
                    decoration: InputDecoration(hintText: 'Message...', filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(backgroundColor: Colors.cyan, child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 18), onPressed: _sendMessage)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ChatMessageWidget extends StatelessWidget {
  final Message message;
  final bool isMe;
  final String friendUserId;
  final String currentUsername;
  final MessageService messageService;
  final VoidCallback onReply;

  const ChatMessageWidget({Key? key, required this.message, required this.isMe, required this.friendUserId, required this.currentUsername, required this.messageService, required this.onReply}) : super(key: key);

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReactionPicker(onReactionSelected: (emoji) {
              messageService.addReaction(recipientUserId: friendUserId, messageId: message.id, emoji: emoji, username: currentUsername);
              Navigator.pop(context);
            }),
            ListTile(leading: const Icon(Icons.reply), title: const Text("Reply"), onTap: () { Navigator.pop(context); onReply(); }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showMenu(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: Border.all(color: Colors.cyan.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.parentText != null)
                    Text(message.parentText!, style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                  Text(message.text, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
            StreamBuilder<List<ChatReaction>>(
              stream: messageService.getMessageReactions(recipientUserId: friendUserId, messageId: message.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: MessageReactionsDisplay(
                    reactions: snapshot.data!,
                    currentUserId: messageService.currentUserId ?? '',
                    onReactionTap: (emoji) => messageService.addReaction(recipientUserId: friendUserId, messageId: message.id, emoji: emoji, username: currentUsername),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}