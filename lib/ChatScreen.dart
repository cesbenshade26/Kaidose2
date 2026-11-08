import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'message_service.dart';
import 'user_service.dart';
import 'chat_reactions.dart';
import 'NetworkVideoPlayer.dart';
import 'ChatBubble.dart';
import 'ChatTarget.dart';
import 'GroupAvatar.dart';
import 'ManageChat.dart';
import 'ChatComposer.dart';
import 'ChatMedia.dart';
import 'UnifiedMediaPicker.dart';
import 'DailyShare.dart';

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
  final ScrollController _scrollController = ScrollController();
  final FocusNode _chatInputFocusNode = FocusNode();

  String? _currentUsername;
  bool _isLoading = true;
  Message? _replyingTo;

  late final ChatTarget _target = ChatTarget.direct(
      friendUserId: widget.friendUserId, friendUsername: widget.friendUsername);

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    // Hide anything already seen in a previous session (After viewing),
    // then mark what's waiting as read (starts my timers).
    _messageService
        .onChatClosed(widget.friendUserId)
        .then((_) => _messageService.markChatMessagesAsRead(widget.friendUserId));
  }

  Future<void> _loadCurrentUser() async {
    final user = await _userService.getUserById(_messageService.currentUserId ?? '');
    if (mounted) {
      setState(() {
        _currentUsername = user?.username ?? 'You';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _chatInputFocusNode.unfocus();
    _scrollController.dispose();
    _chatInputFocusNode.dispose();

    // "After viewing": hide what I've seen when I leave (fire and forget).
    _messageService.onChatClosed(widget.friendUserId);

    super.dispose();
  }

  void _onReplyRequested(Message message) {
    setState(() => _replyingTo = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatInputFocusNode.canRequestFocus) _chatInputFocusNode.requestFocus();
    });
  }

  Future<void> _handleSend(String text, List<PickedMedia> media) async {
    if (_currentUsername == null) return;
    final pId = _replyingTo?.id;
    final pText = _replyingTo == null
        ? null
        : (_replyingTo!.text.isNotEmpty ? _replyingTo!.text : 'Media');
    setState(() => _replyingTo = null);

    final myId = _messageService.currentUserId ?? 'unknown';

    if (media.isEmpty) {
      await _messageService.sendChatMessage(
        recipientUserId: widget.friendUserId,
        text: text,
        senderUsername: _currentUsername!,
        parentMessageId: pId,
        parentText: pText,
      );
    } else {
      for (int i = 0; i < media.length; i++) {
        final up = await ChatMediaUploader.upload(
            media[i], 'chat_media/$myId');
        // Photos and videos ride along as message metadata; the bubble
        // already knows how to show both.
        final metadata = up.isVideo
            ? {'type': 'clip', 'videoUrl': up.url, 'thumbUrl': up.thumbUrl}
            : {'type': 'image', 'imageUrl': up.url};
        final caption = i == 0 ? text : '';

        await _messageService.sendChatMessage(
          recipientUserId: widget.friendUserId,
          text: caption,
          senderUsername: _currentUsername!,
          parentMessageId: i == 0 ? pId : null,
          parentText: i == 0 ? pText : null,
          metadata: metadata,
        );
      }
    }

    if (_scrollController.hasClients) {
      _scrollController.animateTo(0.0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _openManage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManageChatScreen(
          friendUserId: widget.friendUserId,
          friendUsername: widget.friendUsername,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ChatSettings?>(
      stream: _target.watchSettings(),
      builder: (context, snap) => _buildScaffold(snap.data),
    );
  }

  Widget _buildScaffold(ChatSettings? settings) {
    // With a wallpaper the title bar floats over the photo. If the top of the
    // photo is dark, the bar's text and icons turn white.
    final wallpaperUrl = settings?.wallpaperUrl;
    final hasWallpaper = wallpaperUrl != null;
    final light = hasWallpaper && (settings?.wallpaperTopDark ?? false);
    final barColor = light ? Colors.white : Colors.black;
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        systemOverlayStyle:
        light ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openManage,
          child: Text(
            widget.friendUsername,
            style: TextStyle(
              color: barColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: barColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Their face: tap to open this chat's settings.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openManage,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: MemberAvatar(userId: widget.friendUserId, size: 30),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (hasWallpaper)
            Positioned.fill(
              child: Image.network(
                wallpaperUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (hasWallpaper)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPad + 24,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        (light ? Colors.black : Colors.white).withOpacity(0.28),
                        (light ? Colors.black : Colors.white).withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(
                    child: CircularProgressIndicator(color: Colors.cyan))
                    : StreamBuilder<List<Message>>(
                  stream:
                  _messageService.getChatMessages(widget.friendUserId),
                  builder: (context, snapshot) {
                    final messages =
                    (snapshot.data ?? []).reversed.toList();
                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: EdgeInsets.only(
                          top: topPad + 12,
                          bottom: 16,
                          left: 12,
                          right: 12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        // Newest first: the older message is index + 1.
                        final older = index + 1 < messages.length
                            ? messages[index + 1]
                            : null;
                        final newer =
                        index > 0 ? messages[index - 1] : null;
                        final run = BubbleGrouping.compute(
                          senderId: m.senderId,
                          time: m.timestamp,
                          olderSender: older?.senderId,
                          olderTime: older?.timestamp,
                          olderBreaks: false,
                          newerSender: newer?.senderId,
                          newerTime: newer?.timestamp,
                          newerBreaks: false,
                        );
                        return ChatMessageWidget(
                          key: ValueKey(m.id),
                          run: run,
                          onWallpaper: hasWallpaper,
                          message: m,
                          isMe: m.senderId ==
                              _messageService.currentUserId,
                          friendUserId: widget.friendUserId,
                          currentUsername: _currentUsername ?? 'You',
                          messageService: _messageService,
                          onReply: () => _onReplyRequested(m),
                        );
                      },
                    );
                  },
                ),
              ),
              ChatComposer(
                focusNode: _chatInputFocusNode,
                onSend: _handleSend,
                banner: _buildReplyBanner(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget? _buildReplyBanner() {
    if (_replyingTo == null) return null;
    final preview =
    _replyingTo!.text.isNotEmpty ? _replyingTo!.text : 'Media';
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Colors.cyan, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Replying to: $preview",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _replyingTo = null),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16),
            ),
          ),
        ],
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
  final BubbleRun run;
  final bool onWallpaper;

  const ChatMessageWidget({
    Key? key,
    required this.message,
    required this.isMe,
    required this.friendUserId,
    required this.currentUsername,
    required this.messageService,
    required this.onReply,
    required this.run,
    this.onWallpaper = false,
  }) : super(key: key);

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ReactionPicker(
                onReactionSelected: (emoji) {
                  messageService.addReaction(
                    recipientUserId: friendUserId,
                    messageId: message.id,
                    emoji: emoji,
                    username: currentUsername,
                  );
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.black87),
                title: const Text("Reply"),
                onTap: () {
                  Navigator.pop(context);
                  onReply();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  String _getDeleteTimeRemaining() {
    final expiry = message.expiryFor(MessageService().currentUserId ?? '');
    if (expiry == null) return '';

    final remaining = expiry.difference(DateTime.now());

    if (remaining.isNegative) return '';

    if (remaining.inHours >= 24) {
      final days = remaining.inDays;
      return '🕐 ${days}d';
    } else if (remaining.inHours > 0) {
      return '🕐 ${remaining.inHours}h';
    } else if (remaining.inMinutes > 0) {
      return '🕐 ${remaining.inMinutes}m';
    } else {
      return '🕐 <1m';
    }
  }

  @override
  Widget build(BuildContext context) {
    final deleteTimer = _getDeleteTimeRemaining();

    // A message can carry media via metadata: a shared clip or recorded
    // video ({type: 'clip', videoUrl}) or a photo ({type: 'image', imageUrl}).
    final metadata = message.metadata;
    final mediaType = metadata?['type'] as String?;
    final videoUrl = metadata?['videoUrl'] as String?;
    final imageUrl = metadata?['imageUrl'] as String?;
    final hasVideo =
        mediaType == 'clip' && videoUrl != null && videoUrl.isNotEmpty;
    final hasImage =
        mediaType == 'image' && imageUrl != null && imageUrl.isNotEmpty;

    // Sent in from a Daily: show where it came from, tap to open it.
    final source = metadata?['source'] is Map ? metadata!['source'] as Map : null;
    final sourceLabel = DailyShareLink.labelFor(source);
    final sourceDailyId = source?['dailyId'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (run.timeLabel != null) BubbleTimeLabel(text: run.timeLabel!, onWallpaper: onWallpaper),
        GestureDetector(
          onLongPress: () => _showMenu(context),
          child: Column(
            crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              ChatBubble(
                isMe: isMe,
                text: message.text,
                parentText: message.parentText,
                imageUrl: hasImage ? imageUrl : null,
                videoUrl: hasVideo ? videoUrl : null,
                footer: deleteTimer.isEmpty ? null : deleteTimer,
                run: run,
                sourceLabel: sourceLabel,
                onSourceTap: sourceDailyId == null
                    ? null
                    : () => DailyShareLink.open(context, sourceDailyId),
              ),
              StreamBuilder<List<ChatReaction>>(
                stream: messageService.getMessageReactions(
                  recipientUserId: friendUserId,
                  messageId: message.id,
                ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Align(
                    alignment:
                    isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: MessageReactionsDisplay(
                      reactions: snapshot.data!,
                      currentUserId: messageService.currentUserId ?? '',
                      onReactionTap: (emoji) => messageService.addReaction(
                        recipientUserId: friendUserId,
                        messageId: message.id,
                        emoji: emoji,
                        username: currentUsername,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}