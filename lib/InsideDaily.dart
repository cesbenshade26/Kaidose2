import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'SendDailyMessage.dart';
import 'DrawPad.dart';
import 'MessageStorage.dart';
import 'DailySaved.dart';
import 'DailyComments.dart';
import 'DailyLikes.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_service.dart';
import 'UnifiedMediaPicker.dart';
import 'DailyMembershipService.dart';
import 'DailyCoverData.dart';
import 'FeedService.dart';

class InsideDaily extends StatefulWidget {
  final DailyData daily;

  const InsideDaily({
    Key? key,
    required this.daily,
  }) : super(key: key);

  @override
  State<InsideDaily> createState() => InsideDailyState();
}

class InsideDailyState extends State<InsideDaily> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  DateTime? _selectedDate;
  bool _showOptionsMenu = false;
  bool _showMediaPicker = false;
  bool _filterOnlyPromptMessages = false;

  // Everything queued up to send with the next message — could be zero,
  // one, or several photos/videos picked at once from the gallery grid,
  // plus at most one drawing. Each item becomes its own message bubble on
  // send, since DailyMessage only supports one image OR one video per
  // message, not a list.
  List<PickedMedia> _pendingMedia = [];

  List<DailyMessage> _messages = [];
  late AnimationController _optionsAnimationController;
  late Animation<double> _optionsAnimation;

  // The picker replaces the keyboard, so it stays roughly keyboard-sized
  // rather than any fraction of the screen.
  static const double _mediaPickerHeight = 340;

  // 0..1 — how much of the picker is currently revealed. One persistent
  // controller (never recreated) so there's always continuity to animate
  // from/to, whether driven by our own forward()/reverse() or synced
  // directly to a live keyboard inset (see didChangeDependencies).
  late AnimationController _pickerHeightController;
  double? _keyboardHeightWhenPickerOpened;

  // The keyboard's target height isn't known in advance on a *rise* (only
  // on a dismiss, where we already have its current value) — caching the
  // tallest inset ever observed this session lets every rise after the
  // first one sync properly too.
  double _knownKeyboardHeight = 0;
  bool _syncingPickerToKeyboardRise = false;

  Function()? _messageStorageListener;
  final UserService _userService = UserService();
  String? _currentUsername;

  bool _isEditingMessage = false;
  String? _editingMessageId;
  double _lastBottomInset = 0;

  // Guest = this is a Public Daily the viewer isn't in (opened from For
  // You or search). They can post freely; the chip below the app bar lets
  // them add it to My Dailies, which never happens automatically.
  bool _isGuest = false;
  bool _addingToMyDailies = false;

  // Today's entry prompt, shown as a banner for guests only (members get
  // the full-screen UponOpeningDaily gate instead). Empty = no banner.
  String _guestPrompt = '';
  bool _respondingToPrompt = false;

  // The banner sits just above the compose bar and tucks away as soon as
  // the user starts typing (the prompt becomes the field's placeholder
  // once they tap Respond, so nothing is lost).
  bool get _showGuestPromptBanner =>
      _isGuest &&
          _guestPrompt.isNotEmpty &&
          !_messageFocusNode.hasFocus &&
          !_respondingToPrompt &&
          !_showMediaPicker;

  Future<void> _checkGuestStatus() async {
    final inMine = await DailyMembershipService.isInMyDailies(widget.daily.id);
    if (!mounted) return;
    setState(() => _isGuest = !inMine);
    if (!inMine) _loadGuestPrompt();
  }

  /// Today's scheduled prompt if the owner set one, else the Daily's
  /// standing prompt.
  Future<void> _loadGuestPrompt() async {
    var prompt = widget.daily.dailyEntryPrompt.trim();
    try {
      final snap = await DailyCoverService.scheduleRef(
        widget.daily.id,
        CoverWindow.dateKey(DateTime.now()),
      ).get();
      final scheduled = (snap.data()?['prompt'] as String?)?.trim() ?? '';
      if (scheduled.isNotEmpty) prompt = scheduled;
    } catch (e) {
      print('InsideDaily: guest prompt load error: $e');
    }
    if (mounted) setState(() => _guestPrompt = prompt);
  }

  void _respondToPrompt() {
    setState(() => _respondingToPrompt = true);
    _messageFocusNode.requestFocus();
  }

  /// A small tab that rises out of the top of the compose bar (rounded on
  /// top only, same grey as the text field) instead of a boxed card. Tapping
  /// anywhere on it starts a reply to the prompt.
  Widget _buildGuestPromptBanner() {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: _respondToPrompt,
        child: Container(
          margin: const EdgeInsets.only(left: 16, right: 16),
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PROMPT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: Colors.cyan,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _guestPrompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.north_east, size: 14, color: Colors.cyan),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToMyDailies() async {
    if (_addingToMyDailies) return;
    setState(() => _addingToMyDailies = true);
    final result = await DailyMembershipService.addToMyDailies(widget.daily);
    if (!mounted) return;
    final ok = result['success'] == true;
    setState(() {
      _addingToMyDailies = false;
      if (ok) {
        _isGuest = false;
        _guestPrompt = '';
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Added "${widget.daily.title}" to My Dailies'
            : (result['error']?.toString() ?? 'Could not add')),
        backgroundColor: ok ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Guests only: a small round "+" in the app bar (same size and style as
  /// its neighbours) that adds this Daily to My Dailies, then goes away.
  Widget _buildAddAction() {
    return Tooltip(
      message: 'Add to My Dailies',
      child: GestureDetector(
        onTap: _addToMyDailies,
        child: Container(
          margin: const EdgeInsets.only(right: 14),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            shape: BoxShape.circle,
          ),
          child: _addingToMyDailies
              ? const SizedBox(
            width: 22,
            height: 22,
            child: Padding(
              padding: EdgeInsets.all(3),
              child: CircularProgressIndicator(
                  color: Colors.cyan, strokeWidth: 2),
            ),
          )
              : const Icon(Icons.add, color: Colors.cyan, size: 22),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentUser(); // NEW: Load username first
    _checkGuestStatus();

    _optionsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _optionsAnimation = CurvedAnimation(
      parent: _optionsAnimationController,
      curve: Curves.easeOutCubic,
    );

    _pickerHeightController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );

    _loadMessages();

    _messageController.addListener(_handleComposeContentChanged);
    _messageFocusNode.addListener(_handleFocusChanged);

    _messageStorageListener = () {
      if (mounted) _loadMessages();
    };
    MessageStorage.addListener(_messageStorageListener!);
  }

  void _handleComposeContentChanged() {
    if (mounted) setState(() {});
  }

  /// Fires the instant the text field gains focus — the same moment the
  /// keyboard starts rising — so the jump happens right alongside it
  /// instead of waiting for MediaQuery's viewInsets to catch up.
  void _handleFocusChanged() {
    if (mounted) setState(() {}); // banner above the compose bar reacts to focus
    if (_messageFocusNode.hasFocus) {
      // Keyboard and picker occupy the same spot now — regaining focus
      // means the keyboard is about to take that space back.
      if (_showMediaPicker) {
        if (_knownKeyboardHeight > 0) {
          // Sync the picker's shrink directly to the keyboard's own
          // rise (see didChangeDependencies) instead of racing it with
          // a separate animation.
          _keyboardHeightWhenPickerOpened = null;
          _syncingPickerToKeyboardRise = true;
        } else {
          // Haven't seen the keyboard's height yet this session, so
          // there's nothing to sync against — animate normally. Every
          // subsequent close will sync correctly from here on.
          _closeMediaPicker();
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _loadCurrentUser() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) {
      final user = await _userService.getUserById(currentUid);
      if (mounted) {
        setState(() {
          _currentUsername = user?.username ?? 'You';
        });
      }
    }
  }

  Future<void> _loadMessages() async {
    final messages = await MessageStorage.loadMessages(widget.daily.id);
    setState(() {
      _messages = messages;
    });

    if (messages.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _saveMessages() async {
    await MessageStorage.saveMessages(widget.daily.id, _messages);
  }

  void addPromptMessage(String messageText) {
    if (messageText.trim().isEmpty) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';

    final promptMessage = DailyMessage(
      text: messageText,
      timestamp: DateTime.now(),
      dailyId: widget.daily.id,
      isFromPrompt: true,
      userId: currentUid,
      username: _currentUsername ?? 'You',
    );

    setState(() {
      _messages.add(promptMessage);
    });

    _saveMessages();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void addPromptMessageWithMedia(String messageText, String? imagePath, String? videoPath) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';

    final promptMessage = DailyMessage(
      text: messageText.trim().isNotEmpty ? messageText : null,
      imagePath: imagePath,
      videoPath: videoPath,
      timestamp: DateTime.now(),
      dailyId: widget.daily.id,
      isFromPrompt: true,
      userId: currentUid,
      username: _currentUsername ?? 'You',
    );

    setState(() {
      _messages.add(promptMessage);
    });

    _saveMessages();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.removeListener(_handleComposeContentChanged);
    _messageFocusNode.removeListener(_handleFocusChanged);
    _messageFocusNode.dispose();
    _messageController.dispose();
    _optionsAnimationController.dispose();
    _pickerHeightController.dispose();
    if (_messageStorageListener != null) {
      MessageStorage.removeListener(_messageStorageListener!);
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Keyboard show/hide changes the body's available height (Scaffold's
    // default resizeToAvoidBottomInset), but the message list's own
    // scroll offset doesn't automatically follow — without this, the
    // newest message ends up short of the new bottom edge once the
    // keyboard shrinks the viewport.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    // Remember the tallest keyboard inset we've ever seen this session,
    // so a future rise can be synced against immediately rather than
    // needing to observe it once first.
    if (bottomInset > _knownKeyboardHeight) {
      _knownKeyboardHeight = bottomInset;
    }

    // Picker is shrinking because the keyboard is rising back up (see
    // _handleFocusChanged) — mirror image of the dismiss-sync below,
    // riding the keyboard's own live values instead of a separate timer.
    if (_syncingPickerToKeyboardRise) {
      final progress = _knownKeyboardHeight > 0
          ? (1 - (bottomInset / _knownKeyboardHeight)).clamp(0.0, 1.0)
          : 0.0;
      _pickerHeightController.value = progress;
      if (bottomInset > 0 && progress <= 0.0) {
        _syncingPickerToKeyboardRise = false;
        if (_showMediaPicker) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _showMediaPicker = false);
          });
        }
      }
    }

    // While the picker is replacing an already-open keyboard, ride the
    // keyboard's own smooth dismiss values frame-by-frame instead of
    // running a separate animation of our own — that's what was causing
    // the two to drift apart and create a visible gap.
    if (_keyboardHeightWhenPickerOpened != null) {
      final progress =
      (1 - (bottomInset / _keyboardHeightWhenPickerOpened!)).clamp(0.0, 1.0);
      _pickerHeightController.value = progress;
      if (progress >= 1.0) {
        // Keyboard's fully gone — hand control back to normal
        // forward()/reverse() for any future close.
        _keyboardHeightWhenPickerOpened = null;
      }
    }

    if (bottomInset != _lastBottomInset) {
      _lastBottomInset = bottomInset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Date'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.all_inclusive, color: Colors.cyan),
                title: const Text('Any time'),
                subtitle: const Text('Show all messages'),
                onTap: () => Navigator.pop(context, 'any_time'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.calendar_today, color: Colors.cyan),
                title: const Text('Pick a specific date'),
                onTap: () => Navigator.pop(context, 'pick_date'),
              ),
            ],
          ),
        );
      },
    );

    if (result == 'any_time') {
      setState(() {
        _selectedDate = null;
      });
    } else if (result == 'pick_date') {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Colors.cyan,
                onPrimary: Colors.white,
                onSurface: Colors.black,
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.cyan,
                ),
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        setState(() {
          _selectedDate = picked;
        });
      }
    }
  }

  void _toggleOptionsMenu() {
    setState(() {
      _showOptionsMenu = !_showOptionsMenu;
      if (_showOptionsMenu) {
        _optionsAnimationController.forward();
      } else {
        _optionsAnimationController.reverse();
      }
    });
  }

  void _openMediaPicker() {
    final currentKeyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    setState(() => _showMediaPicker = true);

    if (currentKeyboardHeight > 0) {
      // Keyboard's already up — dismiss it and ride its own smooth
      // animation via didChangeDependencies instead of running a
      // separate one that would race it.
      _keyboardHeightWhenPickerOpened = currentKeyboardHeight;
      _messageFocusNode.unfocus();
    } else {
      _keyboardHeightWhenPickerOpened = null;
      _pickerHeightController.forward();
    }
  }

  void _closeMediaPicker() {
    _keyboardHeightWhenPickerOpened = null;
    _pickerHeightController.reverse().then((_) {
      // Only actually removes the widget once fully collapsed, so its
      // content stays visible (being progressively hidden) throughout
      // the close animation instead of vanishing instantly at the start.
      if (mounted) setState(() => _showMediaPicker = false);
    });
  }

  void _toggleMediaPicker() {
    if (_showMediaPicker) {
      _closeMediaPicker();
    } else {
      _openMediaPicker();
    }
  }

  /// Called by UnifiedMediaPickerPanel's Add button with every item the
  /// user checked. They all join the pending strip above the text field;
  /// nothing sends until the normal Send button is pressed.
  void _handleMediaPicked(List<PickedMedia> items) {
    setState(() {
      _pendingMedia.addAll(items);
    });
    _closeMediaPicker();
  }

  Future<void> _openDrawPad() async {
    final File? drawingFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          onDrawingComplete: (file) {
            Navigator.pop(context, file);
          },
        ),
      ),
    );

    if (drawingFile != null) {
      setState(() {
        _pendingMedia.add(PickedMedia(file: drawingFile, isVideo: false));
      });
      _closeMediaPicker();
      print('Drawing attached: ${drawingFile.path}');
    }
  }

  void _startEditingMessage(String messageId) {
    final message = _messages.firstWhere(
          (msg) => msg.messageId == messageId,
      orElse: () => _messages.first,
    );

    setState(() {
      _isEditingMessage = true;
      _editingMessageId = messageId;
      _messageController.text = message.text ?? '';

      if (message.imagePath != null) {
        _pendingMedia = [PickedMedia(file: File(message.imagePath!), isVideo: false)];
      } else {
        _pendingMedia = [];
      }
    });

    print('Editing message: $messageId');
  }

  void _cancelEditingMessage() {
    setState(() {
      _isEditingMessage = false;
      _editingMessageId = null;
      _messageController.clear();
      _pendingMedia = [];
    });
  }

  Future<void> _updateMessage() async {
    if (_editingMessageId == null) return;

    final text = _messageController.text.trim();

    if (text.isEmpty && _pendingMedia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message cannot be empty'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final messageIndex = _messages.indexWhere((msg) => msg.messageId == _editingMessageId);

    if (messageIndex != -1) {
      final oldMessage = _messages[messageIndex];
      final updatedMessage = DailyMessage(
        text: text.isNotEmpty ? text : null,
        imagePath: _pendingMedia.isNotEmpty ? _pendingMedia.first.file.path : null,
        timestamp: oldMessage.timestamp,
        userId: oldMessage.userId,
        messageId: oldMessage.messageId,
        dailyId: oldMessage.dailyId,
        isSaved: oldMessage.isSaved,
        reactions: oldMessage.reactions,
      );

      setState(() {
        _messages[messageIndex] = updatedMessage;
        _isEditingMessage = false;
        _editingMessageId = null;
        _messageController.clear();
        _pendingMedia = [];
      });

      _saveMessages();

      print('Message updated: ${updatedMessage.toJson()}');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message updated'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_isEditingMessage) {
      await _updateMessage();
      return;
    }

    final text = _messageController.text.trim();

    if (text.isEmpty && _pendingMedia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a message or attach media'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final username = _currentUsername ?? 'You';

    // One message, whether it's text-only, a single photo/video, or
    // several picked at once — DailyMessageWidget renders that last case
    // as a swipeable carousel rather than a wall of separate bubbles.
    final message = DailyMessage(
      text: text.isNotEmpty ? text : null,
      media: _pendingMedia
          .map((p) => DailyMediaItem(path: p.file.path, isVideo: p.isVideo))
          .toList(),
      timestamp: DateTime.now(),
      dailyId: widget.daily.id,
      userId: currentUid,
      username: username,
      isFromPrompt: _respondingToPrompt,
    );

    setState(() {
      _messages.add(message);
      _messageController.clear();
      _pendingMedia = [];
      _respondingToPrompt = false;
    });

    _saveMessages();
    FeedService.recordEvent(widget.daily, FeedEvent.post);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    print('Sent 1 message with ${message.media.length} media item(s)');
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Any time';
    }

    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today';
    }

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Whether the compose button should show Send (something to actually
  /// send) rather than Camera — true text, any pending photo/video, or
  /// mid-edit all count.
  bool get _canSend =>
      _messageController.text.trim().isNotEmpty ||
          _pendingMedia.isNotEmpty ||
          _isEditingMessage;

  List<DailyMessage> _getFilteredMessages() {
    List<DailyMessage> filtered = _messages;

    if (_selectedDate != null) {
      filtered = filtered.where((message) {
        final messageDate = message.timestamp;
        return messageDate.year == _selectedDate!.year &&
            messageDate.month == _selectedDate!.month &&
            messageDate.day == _selectedDate!.day;
      }).toList();
    }

    if (_filterOnlyPromptMessages) {
      filtered = filtered.where((message) => message.isFromPrompt).toList();
    }

    return filtered;
  }
  TextStyle _getFontForDaily(DailyData daily) {
    final fontFamily = daily.titleFont ?? 'Default';

    switch (fontFamily) {
      case 'Roboto':
        return GoogleFonts.roboto();
      case 'Playfair Display':
        return GoogleFonts.playfairDisplay();
      case 'Pacifico':
        return GoogleFonts.pacifico();
      case 'Bebas Neue':
        return GoogleFonts.bebasNeue();
      case 'Caveat':
        return GoogleFonts.caveat();
      case 'Permanent Marker':
        return GoogleFonts.permanentMarker();
      case 'Righteous':
        return GoogleFonts.righteous();
      case 'Lobster':
        return GoogleFonts.lobster();
      case 'Dancing Script':
        return GoogleFonts.dancingScript();
      case 'Bangers':
        return GoogleFonts.bangers();
      default:
        return const TextStyle();
    }
  }

  Widget _buildOptionsMenu() {
    return Positioned(
      // extendBodyBehindAppBar means body starts at the very top of the
      // screen now, not below the AppBar — top:8 alone would tuck this
      // under the status bar/title instead of below the toggle button.
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
      right: 16,
      child: FadeTransition(
        opacity: _optionsAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.3),
            end: Offset.zero,
          ).animate(_optionsAnimation),
          child: Container(
            width: 210,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 10,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildOptionItem(Icons.bookmark_outline, 'Saved'),
                Divider(height: 1, color: Colors.grey[300]),
                _buildOptionItem(Icons.add_reaction_outlined, 'Reacted'),
                Divider(height: 1, color: Colors.grey[300]),
                _buildOptionItem(Icons.comment_outlined, 'Comments'),
                Divider(height: 1, color: Colors.grey[300]),
                _buildFilterOptionItem(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionItem(IconData icon, String label) {
    return InkWell(
      onTap: () {
        _toggleOptionsMenu();

        if (label == 'Saved') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DailySavedScreen(daily: widget.daily),
            ),
          );
        } else if (label == 'Reacted') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DailyLikesScreen(daily: widget.daily),
            ),
          );
        } else if (label == 'Comments') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DailyCommentsScreen(daily: widget.daily),
            ),
          );
        } else {
          print('$label tapped');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOptionItem() {
    return InkWell(
      onTap: () {
        setState(() {
          _filterOnlyPromptMessages = !_filterOnlyPromptMessages;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.filter_list, size: 20, color: Colors.black87),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Entry Messages Only',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            Checkbox(
              value: _filterOnlyPromptMessages,
              onChanged: (val) {
                setState(() {
                  _filterOnlyPromptMessages = val ?? false;
                });
              },
              activeColor: Colors.cyan,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingMediaStrip() {
    if (_pendingMedia.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 90,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingMedia.length,
        itemBuilder: (context, index) {
          final item = _pendingMedia[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[300]!, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.isVideo
                        ? Container(
                      color: Colors.grey[800],
                      child: const Center(
                        child: Icon(Icons.play_circle_fill, color: Colors.white, size: 28),
                      ),
                    )
                        : Image.file(
                      item.file,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[200],
                        child: Icon(Icons.broken_image, color: Colors.grey[400]),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _pendingMedia.removeAt(index)),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Text(
          widget.daily.title,
          style: _getFontForDaily(widget.daily).copyWith(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isGuest) _buildAddAction(),
          // Options menu toggle — used to be an up arrow at the bottom of
          // the screen; now lives up here, so it reads as a down arrow
          // (opening the menu) that flips when toggled.
          GestureDetector(
            onTap: _toggleOptionsMenu,
            child: AnimatedRotation(
              turns: _showOptionsMenu ? 0.5 : 0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.cyan,
                  size: 22,
                ),
              ),
            ),
          ),
          // Clear date filter — only shown while a date filter is active
          if (_selectedDate != null)
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDate = null;
                });
                _loadMessages();
              },
              child: Container(
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.clear,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
            ),
          // Date picker
          GestureDetector(
            onTap: () => _selectDate(context),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_today,
                color: Colors.cyan,
                size: 22,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: DailyMessageList(
                  messages: _getFilteredMessages(),
                  scrollController: _scrollController,
                  onEdit: _startEditingMessage,
                  onMessageUpdate: _saveMessages,
                  topPadding: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
                ),
              ),

              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.bottomCenter,
                child: _showGuestPromptBanner
                    ? _buildGuestPromptBanner()
                    : const SizedBox(width: double.infinity),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  // The picker (when open) becomes the true bottom-most
                  // content — it reserves its own bottom safe area below,
                  // so this shouldn't reserve space here too, or a stray
                  // gap opens up between the two.
                  bottom: !_showMediaPicker,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPendingMediaStrip(),
                      if (_isEditingMessage)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            border: Border(
                              bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.edit, color: Colors.cyan, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Editing message',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _cancelEditingMessage,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey[400]!, width: 1),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(
                                Icons.perm_media,
                                color: Colors.grey[700],
                                size: 22,
                              ),
                              onPressed: _toggleMediaPicker,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: TextField(
                                controller: _messageController,
                                focusNode: _messageFocusNode,
                                decoration: InputDecoration(
                                  hintText: _respondingToPrompt && _guestPrompt.isNotEmpty
                                      ? _guestPrompt
                                      : 'Type a message...',
                                  hintStyle: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 16,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                maxLines: null,
                                textCapitalization: TextCapitalization.sentences,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, animation) => ScaleTransition(
                              scale: animation,
                              child: FadeTransition(opacity: animation, child: child),
                            ),
                            child: _canSend
                                ? Container(
                              key: const ValueKey('send'),
                              decoration: const BoxDecoration(
                                color: Colors.cyan,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.send,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: _sendMessage,
                              ),
                            )
                                : Container(
                              key: const ValueKey('camera'),
                              decoration: const BoxDecoration(
                                color: Colors.cyan,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: () {
                                  // Placeholder — quick camera
                                  // capture wiring comes later.
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Sits directly below the compose bar, in the same spot
              // the keyboard would occupy — opening this unfocuses the
              // text field first (see _openMediaPicker), so the two
              // never compete for the same space at once. Uses
              // _pickerHeightController (rather than AnimatedSize
              // swapping between two different widgets) so the panel's
              // content stays mounted and visible throughout — revealed
              // or hidden progressively via ClipRect/Align — instead of
              // vanishing instantly the moment _showMediaPicker flips.
              if (_showMediaPicker)
                AnimatedBuilder(
                  animation: _pickerHeightController,
                  builder: (context, child) {
                    return ClipRect(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: _pickerHeightController.value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: _mediaPickerHeight,
                      child: UnifiedMediaPickerPanel(
                        height: _mediaPickerHeight,
                        onMediaSelected: _handleMediaPicked,
                        onDrawTap: _openDrawPad,
                        onClose: _closeMediaPicker,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Gradient scrim — sits behind the (transparent) AppBar's
          // title/buttons, above the scrolling message content, so text
          // and icons stay legible no matter what scrolls underneath
          // them. Scaffold always layers the real AppBar on top of body
          // regardless of paint order here, so this just needs to be
          // painted above the message list — but below the options menu
          // popup below, which should stay crisp, not washed out.
          IgnorePointer(
            child: Container(
              height: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          if (_showOptionsMenu) _buildOptionsMenu(),
        ],
      ),
    );
  }
}

class DailyMessageList extends StatelessWidget {
  final List<DailyMessage> messages;
  final ScrollController scrollController;
  final Function(String)? onEdit;
  final VoidCallback? onMessageUpdate;
  final double topPadding;

  const DailyMessageList({
    Key? key,
    required this.messages,
    required this.scrollController,
    this.onEdit,
    this.onMessageUpdate,
    this.topPadding = 16,
  }) : super(key: key);

  static const Duration _groupWindow = Duration(minutes: 5);

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _timeOfDay(DateTime t) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "Today", "Yesterday", a weekday within the last week, else a date.
  String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff > 1 && diff < 7) return _weekdays[t.weekday - 1];
    final date = '${_months[t.month - 1]} ${t.day}';
    return t.year == now.year ? date : '$date, ${t.year}';
  }

  Widget _buildDateMarker(DateTime t) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: _dayLabel(t),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: ' ${_timeOfDay(t)}'),
            ],
          ),
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to get started!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    // A centered date/time marker goes in front of the first message of
    // each calendar day (iMessage-style), so individual messages don't need
    // their own timestamps.
    //
    // Consecutive messages from the same person, on the same day and within
    // [_groupWindow] of the previous one, form a group: only the first shows
    // the username and the rest sit right up against it.
    final items = <Object>[];
    final groupedIds = <String>{};
    DateTime? previousDay;
    DailyMessage? previousMessage;
    for (final message in messages) {
      final t = message.timestamp;
      final day = DateTime(t.year, t.month, t.day);
      var startedNewDay = false;
      if (previousDay == null || day != previousDay) {
        items.add(t);
        previousDay = day;
        startedNewDay = true;
      }
      if (!startedNewDay &&
          previousMessage != null &&
          previousMessage.userId == message.userId &&
          t.difference(previousMessage.timestamp).abs() <= _groupWindow) {
        groupedIds.add(message.messageId);
      }
      items.add(message);
      previousMessage = message;
    }

    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.only(top: topPadding, bottom: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is DateTime) return _buildDateMarker(item);

        final message = item as DailyMessage;
        final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';

        final grouped = groupedIds.contains(message.messageId);

        return DailyMessageWidget(
          message: message,
          isCurrentUser: message.userId == currentUid,
          showUsername: !grouped,
          groupedWithPrevious: grouped,
          onEdit: onEdit,
          onSaveToggle: onMessageUpdate,
          onReactionAdded: (emoji) {
            if (onMessageUpdate != null) {
              onMessageUpdate!();
            }
          },
        );
      },
    );
  }
}