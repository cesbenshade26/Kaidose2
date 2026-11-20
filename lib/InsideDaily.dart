import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'SunColors.dart';
import 'SafetyService.dart';
import 'SafetySheets.dart';
import 'DailyData.dart';
import 'SendDailyMessage.dart';
import 'DrawPad.dart';
import 'MessageStorage.dart';
import 'DailySaved.dart';
import 'DailyComments.dart';
import 'DailyLikes.dart';
import 'dart:io';
import 'DailyFonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_service.dart';
import 'UnifiedMediaPicker.dart';
import 'DailyMembershipService.dart';
import 'DailyCoverData.dart';
import 'FeedService.dart';
import 'DailyUnread.dart';
import 'dart:async';
import 'DailyModeration.dart';
import 'CoverJump.dart';
import 'MediaAspect.dart' show MediaAspect, precacheNetworkImage;
import 'DailyPostActivity.dart' show DailyPostVideoCache;
import 'CameraCapture.dart';

class InsideDaily extends StatefulWidget {
  final DailyData daily;

  /// Opened by tapping a cover: the post that cover came from. The Daily
  /// opens right at it (once; see CoverJump), with the newest messages a
  /// "Latest" tap away.
  final String? coverMessageId;

  const InsideDaily({
    Key? key,
    required this.daily,
    this.coverMessageId,
  }) : super(key: key);

  @override
  State<InsideDaily> createState() => InsideDailyState();
}

class InsideDailyState extends State<InsideDaily>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Time spent looking at this Daily (app in the foreground). Reported to
  // the feed when you leave, so Dailies you linger in shape both feeds.
  DateTime? _viewingSince = DateTime.now();
  Duration _timeSpent = Duration.zero;

  void _pauseTimer() {
    final since = _viewingSince;
    if (since != null) _timeSpent += DateTime.now().difference(since);
    _viewingSince = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _viewingSince ??= DateTime.now();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pauseTimer();
    }
  }

  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  DateTime? _selectedDate;
  bool _showOptionsMenu = false;
  bool _showMediaPicker = false;

  // Opened from a cover: the list starts at that post (the anchor), which
  // is briefly highlighted. Null = normal (opens at the newest).
  bool _wantCoverJump = false;
  String? _anchorId;
  String? _highlightId;

  // "Latest" button: shown when you're well above the newest messages.
  bool _showLatest = false;

  // Everything queued up to send with the next message — could be zero,
  // one, or several photos/videos picked at once from the gallery grid,
  // plus at most one drawing. Each item becomes its own message bubble on
  // send, since DailyMessage only supports one image OR one video per
  // message, not a list.
  List<PickedMedia> _pendingMedia = [];

  List<DailyMessage> _messages = [];

  // Messages you just sent that are still uploading (not in Firestore yet).
  // Kept on screen through reloads so they never blink out.
  final Set<String> _sending = {};
  bool _loadedOnce = false;
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

  // Banned from this Daily (by its owner or a moderator): they can still
  // read it, but can't post or add it while the ban lasts.
  DailyBan? _myBan;
  StreamSubscription<DailyBan?>? _banSub;

  // Owner / moderator: can remove anyone's post and ban from a post.
  DailyPermissions _perms = DailyPermissions.none;
  List<String> _moderatorUids = const [];
  StreamSubscription<DailyPermissions>? _permsSub;
  StreamSubscription<List<String>>? _modsSub;
  bool get _isBanned => _myBan?.isActive == true;

  // Today's entry prompt, shown as a banner for guests only (members get
  // the full-screen UponOpeningDaily gate instead). Empty = no banner.
  String _guestPrompt = '';
  bool _respondingToPrompt = false;

  // The banner sits just above the compose bar and tucks away as soon as
  // the user starts typing (the prompt becomes the field's placeholder
  // once they tap Respond, so nothing is lost).
  bool get _showGuestPromptBanner =>
      !_isBanned &&
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

  /// Today's scheduled prompt, if the owner set one for today. Prompts
  /// are per day (like covers), so there's no standing prompt anymore.
  Future<void> _loadGuestPrompt() async {
    final prompt = await DailyCoverService.todayPrompt(widget.daily.id);
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
            color: kc.grey(100),
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
                  color: SunColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _guestPrompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: kc.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.north_east, size: 14, color: SunColors.ink),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToMyDailies() async {
    if (_addingToMyDailies || _isBanned) return;
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

  /// Takes the compose bar's place while you're banned from this Daily.
  Widget _buildBannedBar() {
    final ban = _myBan!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: kc.surface,
        border: Border(top: BorderSide(color: kc.grey(200))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Icon(Icons.block, size: 20, color: kc.grey(600)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "You're banned from this Daily",
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ban.isPermanent
                        ? "You can't post here."
                        : "You can't post here for now · ${ban.timeLeft}",
                    style: TextStyle(fontSize: 13, color: kc.grey(600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCurrentUser(); // NEW: Load username first
    _checkGuestStatus();
    _permsSub = DailyModeration.watchPermissions(widget.daily).listen((p) {
      if (mounted) setState(() => _perms = p);
    }, onError: (_) {});
    _modsSub = DailyModeration.watchModerators(widget.daily.id).listen((m) {
      if (mounted) setState(() => _moderatorUids = m);
    }, onError: (_) {});
    _banSub = DailyModeration.watchMyBan(widget.daily.id).listen((ban) {
      if (!mounted) return;
      setState(() => _myBan = ban);
      // Banned while typing: close the keyboard and any picker.
      if (ban != null) _messageFocusNode.unfocus();
    });

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

    _wantCoverJump =
        CoverJump.shouldJump(widget.daily.id, widget.coverMessageId);
    _scrollController.addListener(_updateLatestButton);

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
    final loaded = await MessageStorage.loadMessages(widget.daily.id);
    if (!mounted) return;

    // Still-uploading messages of yours stay (they'd vanish otherwise).
    final ids = loaded.map((m) => m.messageId).toSet();
    final pending = _messages
        .where((m) => _sending.contains(m.messageId) && !ids.contains(m.messageId))
        .toList();
    final messages = [...loaded, ...pending]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Only jump to the newest message on the first load, or if you were
    // already at the bottom; never yank you away from where you're reading.
    final atBottom = !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <
            160;
    var jump = !_loadedOnce || atBottom;

    // Opened from a cover (not seen yet): start at that post instead of
    // the bottom, unless it's already among the newest few.
    String? anchor;
    if (!_loadedOnce && _wantCoverJump) {
      _wantCoverJump = false;
      final id = widget.coverMessageId!;
      final i = messages.indexWhere((m) => m.messageId == id);
      if (i >= 0) {
        CoverJump.markSeen(widget.daily.id, id);
        if (i < messages.length - 4) {
          jump = false;
          anchor = id;
          _warmAround(messages, i);
        }
      }
    }
    // Normal open (at the newest messages): get the posts you'll see first
    // ready right away: their photos, video still frames and sizes, plus
    // the newest videos.
    if (!_loadedOnce && anchor == null && messages.isNotEmpty) {
      _warmAround(messages, messages.length - 1);
    }
    _loadedOnce = true;

    setState(() {
      _messages = messages;
      if (anchor != null) {
        _anchorId = anchor;
        _highlightId = anchor;
      }
    });

    // Opening at a cover post shows "Latest" right away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateLatestButton();
    });

    // Everything just loaded counts as read: clears this Daily's
    // "N new" pill in My Dailies.
    DailyUnreadService.markRead(widget.daily.id, loaded);

    if (messages.isNotEmpty && jump) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  /// Gets the posts around [index] (the cover post, or the newest one on a
  /// normal open) ready: their photos and video
  /// still frames download and their sizes are worked out (so nothing
  /// jumps while scrolling up or down from there), and the cover's video
  /// plus the next one start loading.
  void _warmAround(List<DailyMessage> messages, int index) {
    var videos = 0;
    final from = (index - 10).clamp(0, messages.length);
    final to = (index + 11).clamp(0, messages.length);
    // Nearest first, so the ones on screen are ready first.
    final order = List.generate(to - from, (k) => from + k)
      ..sort((a, b) => (a - index).abs().compareTo((b - index).abs()));
    for (final i in order) {
      for (final item in messages[i].media) {
        if (!item.path.startsWith('http')) continue;
        if (!item.isVideo || item.thumb != null) {
          MediaAspect.of(item.path, isVideo: item.isVideo, thumb: item.thumb);
        }
        if (item.isVideo) {
          final thumb = item.thumb;
          if (thumb != null) precacheNetworkImage(thumb);
          if (videos < 2 && (i - index).abs() <= 3) {
            DailyPostVideoCache.warm(item.path);
            videos++;
          }
        } else {
          precacheNetworkImage(item.path);
        }
      }
    }
  }

  void _updateLatestButton() {
    if (!_scrollController.hasClients) return;
    final p = _scrollController.position;
    final show = p.maxScrollExtent - p.pixels > 900;
    if (show != _showLatest) setState(() => _showLatest = show);
  }

  /// Down to the newest messages. From far up it hops most of the way
  /// first, so it doesn't take ages scrolling past everything.
  Future<void> _jumpToLatest() async {
    if (!_scrollController.hasClients) return;
    final p = _scrollController.position;
    final screen = p.viewportDimension;
    if (p.maxScrollExtent - p.pixels > screen * 3) {
      _scrollController.jumpTo(p.maxScrollExtent - screen);
    }
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    // Lazy lists can grow as they're reached: land exactly at the end.
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Widget _buildLatestButton() {
    return GestureDetector(
      onTap: _jumpToLatest,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Latest',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kc.grey(850))),
            const SizedBox(width: 4),
            Icon(Icons.arrow_downward_rounded,
                size: 18, color: kc.grey(850)),
          ],
        ),
      ),
    );
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

    MessageStorage.addMessage(widget.daily.id, promptMessage);

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

  /// Posts the answer to this Daily's entry prompt (from the prompt pop-up
  /// in UponOpeningDaily): text and any photos/videos, as one message, the
  /// same way the normal Send button posts.
  Future<void> addPromptEntry(String messageText, List<PickedMedia> media) async {
    final text = messageText.trim();
    if (_isBanned || (text.isEmpty && media.isEmpty)) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    // Right after the Daily opens, your name may not have loaded yet; get it
    // so the post doesn't go out under "You".
    var username = _currentUsername;
    if (username == null || username == 'You') {
      try {
        final user = await _userService.getUserById(currentUid);
        username = user?.username ?? username;
      } catch (_) {}
    }

    final promptMessage = DailyMessage(
      text: text.isNotEmpty ? text : null,
      media: media
          .map((p) => DailyMediaItem(path: p.file.path, isVideo: p.isVideo))
          .toList(),
      timestamp: DateTime.now(),
      dailyId: widget.daily.id,
      isFromPrompt: true,
      userId: currentUid,
      username: username ?? 'You',
    );

    if (!mounted) return;
    setState(() {
      _selectedDate = null;
      _messages.add(promptMessage);
    });

    _sending.add(promptMessage.messageId);
    MessageStorage.addMessage(widget.daily.id, promptMessage)
        .whenComplete(() => _sending.remove(promptMessage.messageId));
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseTimer();
    FeedService.recordDailyTime(widget.daily, _timeSpent);
    _banSub?.cancel();
    _permsSub?.cancel();
    _modsSub?.cancel();
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

  /// Days (midnight) that have at least one message.
  Set<DateTime> get _daysWithMessages => {
    for (final m in _messages)
      DateTime(m.timestamp.year, m.timestamp.month, m.timestamp.day),
  };

  /// Calendar: jump to one day's messages. Only days that actually have
  /// messages can be picked, so a filter never comes up empty.
  Future<void> _selectDate(BuildContext context) async {
    if (_showOptionsMenu) _toggleOptionsMenu();
    final days = _daysWithMessages;
    if (days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No messages to look through yet'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final sorted = days.toList()..sort();
    final first = sorted.first;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = sorted.last.isAfter(today) ? sorted.last : today;
    final current = _selectedDate == null
        ? null
        : DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
    final initial =
    (current != null && days.contains(current)) ? current : sorted.last;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Show messages from',
      confirmText: 'Show',
      selectableDayPredicate: (d) =>
          days.contains(DateTime(d.year, d.month, d.day)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: (AppTheme.isDark ? ColorScheme.dark : ColorScheme.light)(
              primary: Colors.cyan,
              onPrimary: Colors.white,
              onSurface: kc.text,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: kc.surface,
              surfaceTintColor: Colors.transparent,
              headerBackgroundColor: kc.surface,
              headerForegroundColor: kc.text,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: Colors.cyan[700]),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = picked;
      _anchorId = null; // date filter: back to a normal list
      _highlightId = null;
    });
    // Start at the top of that day.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
      _anchorId = null;
    });
    // Back to the newest messages.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
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

  /// The camera button (shown while there's nothing typed): take a photo
  /// or record a video. It joins the pending strip like anything picked from
  /// the gallery, so you can add a caption before sending.
  Future<void> _openCamera() async {
    if (_isBanned) return;
    final shot = await CameraCapture.capture(context);
    if (shot == null || !mounted) return;
    setState(() => _pendingMedia.add(shot));
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
        isFromPrompt: oldMessage.isFromPrompt,
        reactions: oldMessage.reactions,
        username: oldMessage.username,
      );

      setState(() {
        _messages[messageIndex] = updatedMessage;
        _isEditingMessage = false;
        _editingMessageId = null;
        _messageController.clear();
        _pendingMedia = [];
      });

      MessageStorage.updateMessageContent(widget.daily.id, updatedMessage);

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
    if (_isBanned) return;
    if (_isEditingMessage) {
      await _updateMessage();
      return;
    }

    final text = _messageController.text.trim();

    // Looking at an older day: your new message wouldn't show, so go back
    // to everything.
    if (_selectedDate != null && (text.isNotEmpty || _pendingMedia.isNotEmpty)) {
      setState(() => _selectedDate = null);
    }

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

    _sending.add(message.messageId);
    MessageStorage.addMessage(widget.daily.id, message)
        .whenComplete(() => _sending.remove(message.messageId));
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

    final yesterday = DateTime(now.year, now.month, now.day - 1);
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    final year = date.year == now.year ? '' : ', ${date.year}';
    return '${months[date.month - 1]} ${date.day}$year';
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

    return filtered;
  }
  /// The Daily's own title font (shared fonts, preloaded at launch: see
  /// DailyFonts). Only the Daily cards and the inside of a Daily use it.
  TextStyle _getFontForDaily(DailyData daily, {FontWeight? weight}) =>
      DailyFonts.style(daily.titleFont, fontWeight: weight);

  Widget _buildOptionsMenu() {
    return Positioned(
      // extendBodyBehindAppBar means body starts at the very top of the
      // screen now, not below the AppBar — top:8 alone would tuck this
      // under the status bar/title instead of below the toggle button.
      top: MediaQuery.of(context).padding.top +
          kToolbarHeight +
          8 +
          (_showSubBar ? 40 : 0),
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
              color: kc.surface,
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
                // Your saved posts from this Daily: only in My Dailies.
                if (!_isGuest) ...[
                  _buildOptionItem(Icons.bookmark_outline, 'Saved'),
                  Divider(height: 1, color: kc.grey(300)),
                ],
                _buildOptionItem(Icons.add_reaction_outlined, 'Reacted'),
                Divider(height: 1, color: kc.grey(300)),
                _buildOptionItem(Icons.comment_outlined, 'Comments'),
                if (widget.daily.creatorUid !=
                    FirebaseAuth.instance.currentUser?.uid) ...[
                  Divider(height: 1, color: kc.grey(300)),
                  _buildOptionItem(Icons.flag_outlined, 'Report Daily'),
                ],
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
        } else if (label == 'Report Daily') {
          ReportSheet.show(
            context,
            target: ReportTarget.daily,
            targetId: widget.daily.id,
            ownerUid: widget.daily.creatorUid ?? '',
            path: 'public_dailies/${widget.daily.id}',
            preview: '${widget.daily.title}\n${widget.daily.description}',
          );
        } else {
          print('$label tapped');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: kc.text),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: kc.text,
              ),
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
                    border: Border.all(color: kc.grey(300), width: 2),
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
                        color: kc.grey(200),
                        child: Icon(Icons.broken_image, color: kc.grey(400)),
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
      backgroundColor: kc.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: kc.text, size: 28),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Text(
          widget.daily.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _getFontForDaily(widget.daily, weight: FontWeight.w600).copyWith(
            color: kc.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        // Just two buttons up here, so the title always has room. Adding a
        // Daily (guests) and the date filter live in the strip below.
        actions: [
          _barButton(
            icon: Icons.calendar_today_rounded,
            active: _selectedDate != null,
            onTap: () => _selectDate(context),
          ),
          const SizedBox(width: 8),
          AnimatedRotation(
            turns: _showOptionsMenu ? 0.5 : 0,
            duration: const Duration(milliseconds: 300),
            child: _barButton(
              icon: Icons.keyboard_arrow_down_rounded,
              onTap: _toggleOptionsMenu,
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DailyMessageList(
                        messages: _getFilteredMessages(),
                        anchorMessageId: _anchorId,
                        highlightMessageId: _highlightId,
                        scrollController: _scrollController,
                        onEdit: _startEditingMessage,
                        // Reactions and saves write themselves (one field each).
                        onMessageUpdate: null,
                        dailyTitle: widget.daily.title,
                        isPrivateDaily: widget.daily.privacy != 'Public',
                        permissions: _perms,
                        ownerUid: widget.daily.creatorUid,
                        moderatorUids: _moderatorUids,
                        inMyDailies: !_isGuest,
                        topPadding: MediaQuery.of(context).padding.top +
                            kToolbarHeight +
                            12 +
                            (_showSubBar ? 40 : 0),
                      ),
                    ),
                    // Back to the newest messages.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _showLatest
                              ? _buildLatestButton()
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
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

              if (_isBanned)
                _buildBannedBar()
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: kc.surface,
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
                              color: kc.grey(100),
                              border: Border(
                                bottom: BorderSide(color: kc.grey(300), width: 1),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.edit, color: Colors.cyan, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Editing message',
                                  style: TextStyle(
                                    color: kc.text,
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
                                      color: kc.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: kc.grey(400), width: 1),
                                    ),
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: kc.text,
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
                                color: kc.grey(200),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.perm_media,
                                  color: kc.grey(700),
                                  size: 22,
                                ),
                                onPressed: _toggleMediaPicker,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: kc.grey(100),
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
                                      color: kc.grey(500),
                                      fontSize: 16,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: kc.text,
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
                                decoration: BoxDecoration(
                                  color: kc.adapt(const Color(0xFFF1F3F5)),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.camera_alt_outlined,
                                    color: kc.adapt(const Color(0xFF2E2E2E)),
                                    size: 22,
                                  ),
                                  onPressed: _openCamera,
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
              if (_showMediaPicker && !_isBanned)
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

          if (_showSubBar) _buildSubBar(),
          if (_showOptionsMenu) _buildOptionsMenu(),
        ],
      ),
    );
  }

  /// Round grey button in the app bar; cyan-filled while [active].
  Widget _barButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? Colors.cyan : kc.adapt(const Color(0xFFF1F3F5)),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: active ? Colors.white : kc.adapt(const Color(0xFF2E2E2E)), size: 20),
      ),
    );
  }

  /// The strip under the app bar: "Add to My Dailies" for guests, and the
  /// day you're filtered to (tap the x to see everything again).
  bool get _showSubBar =>
      (_isGuest && !_isBanned) || _selectedDate != null;

  Widget _buildSubBar() {
    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool filled = false,
      bool busy = false,
      Widget? trailing,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: EdgeInsets.only(left: 10, right: trailing != null ? 4 : 12),
          decoration: BoxDecoration(
            color: filled ? Colors.cyan : kc.surface,
            borderRadius: BorderRadius.circular(16),
            border: filled ? null : Border.all(color: kc.adapt(const Color(0xFFE2E5E9))),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : Icon(icon,
                  size: 16,
                  color: filled ? Colors.white : kc.grey(700)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : kc.text,
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      );
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 2,
      left: 0,
      right: 0,
      child: Center(
        child: Wrap(
          spacing: 8,
          children: [
            if (_isGuest && !_isBanned)
              chip(
                icon: Icons.add_rounded,
                label: 'Add to My Dailies',
                filled: true,
                busy: _addingToMyDailies,
                onTap: _addToMyDailies,
              ),
            if (_selectedDate != null)
              chip(
                icon: Icons.calendar_today_rounded,
                label: _formatDate(_selectedDate),
                onTap: () => _selectDate(context),
                trailing: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _clearDateFilter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: kc.grey(600)),
                  ),
                ),
              ),
          ],
        ),
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
  final String? dailyTitle;
  final bool isPrivateDaily;

  /// Start the list at this post (opened from a cover) instead of at the
  /// bottom. Messages load lazily both up and down from it.
  final String? anchorMessageId;

  /// Briefly highlighted, with a small "From the cover" tag.
  final String? highlightMessageId;

  // Who's looking, for the owner / moderator options on each post.
  final DailyPermissions permissions;
  final String? ownerUid;
  final List<String> moderatorUids;

  /// One of your Dailies (not a guest visit from For You).
  final bool inMyDailies;

  const DailyMessageList({
    Key? key,
    required this.messages,
    required this.scrollController,
    this.onEdit,
    this.onMessageUpdate,
    this.dailyTitle,
    this.isPrivateDaily = false,
    this.anchorMessageId,
    this.highlightMessageId,
    this.permissions = DailyPermissions.none,
    this.ownerUid,
    this.moderatorUids = const [],
    this.inMyDailies = true,
    this.topPadding = 16,
  }) : super(key: key);

  /// Whether the viewer can remove this author's posts and ban them.
  /// Owner: anyone but themselves. Moderator: members only (not the owner
  /// or other moderators).
  bool _canBan(String authorUid, String? me) {
    if (authorUid == me || authorUid == ownerUid) return false;
    if (permissions.isOwner) return true;
    return permissions.isModerator && !moderatorUids.contains(authorUid);
  }

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
          style: TextStyle(fontSize: 12, color: kc.grey(500)),
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
              color: kc.grey(300),
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 18,
                color: kc.grey(500),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to get started!',
              style: TextStyle(
                fontSize: 14,
                color: kc.grey(400),
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

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final cacheExtent = MediaQuery.of(context).size.height * 1.5;

    Widget buildItem(Object item) {
      if (item is DateTime) return _buildDateMarker(item);
      final message = item as DailyMessage;
      final grouped = groupedIds.contains(message.messageId);
      final widget = DailyMessageWidget(
        // Keeps each message's state (loaded media, comment counts) with
        // that message when the list reloads.
        key: ValueKey(message.messageId),
        message: message,
        isCurrentUser: message.userId == currentUid,
        showUsername: !grouped,
        groupedWithPrevious: grouped,
        dailyTitle: dailyTitle,
        isPrivateDaily: isPrivateDaily,
        // Same rule for removing a post as for banning its author.
        canModerate: _canBan(message.userId, currentUid),
        canBanAuthor: _canBan(message.userId, currentUid),
        inMyDailies: inMyDailies,
        onEdit: onEdit,
        onSaveToggle: onMessageUpdate,
        onReactionAdded: (emoji) {
          if (onMessageUpdate != null) {
            onMessageUpdate!();
          }
        },
      );
      return message.messageId == highlightMessageId
          ? _CoverHighlight(child: widget)
          : widget;
    }

    // Opened from a cover: split the list at that post. Older messages
    // grow upward from it, newer ones downward, both built lazily with the
    // same build-ahead distance, so scrolling either way is ready.
    final anchorIndex = anchorMessageId == null
        ? -1
        : items.indexWhere(
            (i) => i is DailyMessage && i.messageId == anchorMessageId);
    if (anchorIndex >= 0) {
      // Keep its date marker with it.
      final split = (anchorIndex > 0 && items[anchorIndex - 1] is DateTime)
          ? anchorIndex - 1
          : anchorIndex;
      final before = items.sublist(0, split).reversed.toList();
      final after = items.sublist(split);
      const centerKey = ValueKey('cover-anchor');
      return CustomScrollView(
        controller: scrollController,
        center: centerKey,
        // The cover post sits a bit below the app bar.
        anchor: 0.18,
        cacheExtent: cacheExtent,
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, i) => i == before.length
                  ? SizedBox(height: topPadding) // very top
                  : buildItem(before[i]),
              childCount: before.length + 1,
            ),
          ),
          SliverList(
            key: centerKey,
            delegate: SliverChildBuilderDelegate(
                  (context, i) => i == after.length
                  ? const SizedBox(height: 16) // very bottom
                  : buildItem(after[i]),
              childCount: after.length + 1,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.only(top: topPadding, bottom: 16),
      cacheExtent: cacheExtent,
      itemCount: items.length,
      itemBuilder: (context, index) => buildItem(items[index]),
    );
  }
}

/// The post a cover came from, when the Daily is opened from that cover:
/// a small "From the cover" tag, and a soft cyan glow that fades away.
class _CoverHighlight extends StatefulWidget {
  final Widget child;
  const _CoverHighlight({required this.child});

  @override
  State<_CoverHighlight> createState() => _CoverHighlightState();
}

class _CoverHighlightState extends State<_CoverHighlight> {
  bool _glow = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _glow = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      decoration: BoxDecoration(
        color: SunColors.mid.withOpacity(_glow ? 0.16 : 0.0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 2),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 13, color: SunColors.ink),
                const SizedBox(width: 4),
                Text('From the cover',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SunColors.ink)),
              ],
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}