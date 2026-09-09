import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'MessageStorage.dart';
import 'SendDailyMessage.dart';
import 'InsideDaily.dart';

/// Shown when a Daily card is tapped in DailyPostActivity. Displays only
/// the current user's own posts (text/image/video) within that Daily,
/// reusing DailyMessageList/DailyMessageWidget so comments, reactions, and
/// saves behave identically to viewing the Daily directly — they read and
/// write through the same MessageStorage/CommentStorage the real Daily
/// uses, so changes made here show up for everyone else in that Daily too.
class DailyPostDetailScreen extends StatefulWidget {
  final DailyData daily;

  const DailyPostDetailScreen({Key? key, required this.daily}) : super(key: key);

  @override
  State<DailyPostDetailScreen> createState() => _DailyPostDetailScreenState();
}

class _DailyPostDetailScreenState extends State<DailyPostDetailScreen> {
  final ScrollController _scrollController = ScrollController();

  // The FULL message list for this Daily — every user's posts. Never save
  // a filtered subset back to storage, or other users' messages would be
  // wiped out.
  List<DailyMessage> _allMessages = [];
  bool _isLoading = true;
  VoidCallback? _messageStorageListener;

  @override
  void initState() {
    super.initState();
    _loadMessages();

    _messageStorageListener = () {
      if (mounted) _loadMessages();
    };
    MessageStorage.addListener(_messageStorageListener!);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (_messageStorageListener != null) {
      MessageStorage.removeListener(_messageStorageListener!);
    }
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final messages = await MessageStorage.loadMessages(widget.daily.id);
    if (mounted) {
      setState(() {
        _allMessages = messages;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveMessages() async {
    await MessageStorage.saveMessages(widget.daily.id, _allMessages);
  }

  List<DailyMessage> get _myMessages {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    return _allMessages.where((m) => m.userId == currentUid).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.daily.title,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : DailyMessageList(
        messages: _myMessages,
        scrollController: _scrollController,
        onMessageUpdate: _saveMessages,
      ),
    );
  }
}