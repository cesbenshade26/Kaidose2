import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'user_service.dart';
import 'chat_reactions.dart';
import 'GroupChatService.dart';
import 'ChatBubble.dart';
import 'ChatComposer.dart';
import 'NetworkVideoPlayer.dart';
import 'GroupAvatar.dart';
import 'GroupMediaScreen.dart';
import 'ManageGroupChat.dart';
import 'UnifiedMediaPicker.dart';
import 'DailyShare.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;

  const GroupChatScreen({Key? key, required this.groupId}) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final GroupChatService _service = GroupChatService();
  final UserService _userService = UserService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  String _currentUsername = 'You';
  bool _isLoading = true;
  GroupMessage? _replyingTo;
  bool _removedHandled = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = await _userService.getUserById(_service.currentUserId ?? '');
    if (mounted) {
      setState(() {
        _currentUsername = user?.username ?? 'You';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _inputFocus.unfocus();
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onReplyRequested(GroupMessage message) {
    setState(() => _replyingTo = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inputFocus.canRequestFocus) _inputFocus.requestFocus();
    });
  }

  Future<void> _handleSend(String text, List<PickedMedia> media) async {
    final pId = _replyingTo?.id;
    final pText = _replyingTo?.text.isNotEmpty == true
        ? _replyingTo!.text
        : (_replyingTo != null ? 'Media' : null);
    setState(() => _replyingTo = null);

    if (media.isEmpty) {
      await _service.sendMessage(
        groupId: widget.groupId,
        text: text,
        senderUsername: _currentUsername,
        parentMessageId: pId,
        parentText: pText,
      );
    } else {
      for (int i = 0; i < media.length; i++) {
        // The caption and reply go with the first item.
        await _service.sendMedia(
          groupId: widget.groupId,
          media: media[i],
          senderUsername: _currentUsername,
          text: i == 0 ? text : '',
          parentMessageId: i == 0 ? pId : null,
          parentText: i == 0 ? pText : null,
        );
      }
    }

    if (_scrollController.hasClients) {
      _scrollController.animateTo(0.0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Widget _memberFaces(GroupChat group, Color ringColor) {
    final ids = group.memberIds.take(3).toList();
    const size = 30.0;
    const step = 18.0;
    return SizedBox(
      width: size + step * (ids.length - 1),
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < ids.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: MemberAvatar(userId: ids[i], size: size - 3),
              ),
            ),
        ],
      ),
    );
  }

  void _openManage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManageGroupChatScreen(groupId: widget.groupId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GroupChat?>(
      stream: _service.watchGroup(widget.groupId),
      builder: (context, groupSnap) {
        final group = groupSnap.data;
        final myId = _service.currentUserId;

        // Removed from the group (or it was deleted): leave this screen.
        final gone = groupSnap.connectionState != ConnectionState.waiting &&
            (group == null || !group.memberIds.contains(myId));
        if (gone && !_removedHandled) {
          _removedHandled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).popUntil((r) => r.isFirst);
          });
        }
        return _buildScaffold(group, myId);
      },
    );
  }

  Widget _buildScaffold(GroupChat? group, String? myId) {
    // With a wallpaper the title bar floats over the photo. If the top of the
    // photo is dark, the bar's text and icons turn white.
    final hasWallpaper = group?.wallpaperUrl != null;
    final light = hasWallpaper && group!.wallpaperTopDark;
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
        iconTheme: IconThemeData(color: barColor),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: barColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openManage,
          child: Text(
            group == null ? 'Group chat' : group.displayName(myId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: barColor,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        actions: [
          // The members' faces: tap to open the group's settings.
          if (group != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openManage,
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _memberFaces(group, barColor),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (group?.wallpaperUrl != null)
            Positioned.fill(
              child: Image.network(
                group!.wallpaperUrl!,
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
                    : StreamBuilder<List<GroupMessage>>(
                  stream: _service.getMessages(widget.groupId),
                  builder: (context, snapshot) {
                    final messages = snapshot.data ?? [];
                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: EdgeInsets.only(
                          top: topPad + 12, bottom: 16, left: 12, right: 12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        // Newest first: the older message is index + 1.
                        final older = index + 1 < messages.length
                            ? messages[index + 1]
                            : null;
                        final newer = index > 0 ? messages[index - 1] : null;
                        final run = BubbleGrouping.compute(
                          senderId: m.senderId,
                          time: m.timestamp,
                          olderSender: older?.senderId,
                          olderTime: older?.timestamp,
                          olderBreaks: older?.isSystem ?? false,
                          newerSender: newer?.senderId,
                          newerTime: newer?.timestamp,
                          newerBreaks: newer?.isSystem ?? false,
                        );
                        if (m.isSystem) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  m.text,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]),
                                ),
                              ),
                            ),
                          );
                        }
                        return GroupMessageWidget(
                          key: ValueKey(m.id),
                          message: m,
                          isMe: m.senderId == myId,
                          run: run,
                          onWallpaper: hasWallpaper,
                          groupId: widget.groupId,
                          currentUsername: _currentUsername,
                          service: _service,
                          onReply: () => _onReplyRequested(m),
                        );
                      },
                    );
                  },
                ),
              ),
              ChatComposer(
                focusNode: _inputFocus,
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
    final preview = _replyingTo!.text.isNotEmpty
        ? _replyingTo!.text
        : (_replyingTo!.videoUrl != null ? 'Video' : 'Photo');
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
              'Replying to ${_replyingTo!.senderUsername}: $preview',
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

/// Same bubble look as the 1:1 chat, plus the sender's name on others'
/// messages.
class GroupMessageWidget extends StatelessWidget {
  final GroupMessage message;
  final bool isMe;
  final BubbleRun run;
  final bool onWallpaper;
  final String groupId;
  final String currentUsername;
  final GroupChatService service;
  final VoidCallback onReply;

  const GroupMessageWidget({
    Key? key,
    required this.message,
    required this.isMe,
    required this.run,
    this.onWallpaper = false,
    required this.groupId,
    required this.currentUsername,
    required this.service,
    required this.onReply,
  }) : super(key: key);

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
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
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ReactionPicker(
                onReactionSelected: (emoji) {
                  service.toggleReaction(
                    groupId: groupId,
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
                title: const Text('Reply'),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (run.timeLabel != null)
          BubbleTimeLabel(text: run.timeLabel!, onWallpaper: onWallpaper),
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
                senderName: message.senderUsername,
                imageUrl: message.imageUrl,
                videoUrl: message.videoUrl,
                run: run,
                sourceLabel: DailyShareLink.labelFor(message.source),
                onSourceTap: message.source?['dailyId'] == null
                    ? null
                    : () => DailyShareLink.open(
                    context, message.source!['dailyId'] as String),
                onImageTap: message.imageUrl == null
                    ? null
                    : () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    opaque: false,
                    pageBuilder: (_, __, ___) => GroupImageViewer(
                      items: [
                        GroupMediaItem(
                            url: message.imageUrl!,
                            previewUrl: message.imageUrl,
                            isVideo: false)
                      ],
                      initialIndex: 0,
                    ),
                    transitionsBuilder: (_, a, __, child) =>
                        FadeTransition(opacity: a, child: child),
                  ),
                ),
              ),
              StreamBuilder<List<ChatReaction>>(
                stream: service.getReactions(
                    groupId: groupId, messageId: message.id),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Align(
                    alignment:
                    isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: MessageReactionsDisplay(
                      reactions: snapshot.data!,
                      currentUserId: service.currentUserId ?? '',
                      onReactionTap: (emoji) => service.toggleReaction(
                        groupId: groupId,
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