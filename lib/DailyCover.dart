import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'DailyFonts.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'DailyCoverData.dart';
import 'ManageDaily.dart';
import 'UponOpeningDaily.dart';
import 'InsideDaily.dart';
import 'FeedService.dart';
import 'DailyMembershipService.dart';
import 'DailyUnread.dart';
import 'DailyWarmup.dart';
import 'DailyModeration.dart';
import 'DailyIcon.dart';
import 'CoverJump.dart';
import 'GroupAvatar.dart' show MemberAvatar;

/// The cover card for a single Daily, as shown in the Dailies list.
///
/// Two layouts:
///  - With a cover: header row (icon, title, pin badge, menu), the hook
///    across the full width below it (left out when there's no hook), then
///    the cover image edge to edge at the bottom of the card.
///  - Without one (nothing eligible was posted): the original card.
///
/// Covers are picked by the server three times a day and are the same for
/// every viewer in every time zone, so For You cards and My Dailies cards
/// show the same cover. Cards only read; nothing here generates anything.
///
/// [forYou] switches the card to its For You feed form, for Dailies the
/// viewer is not in: the pin/manage/delete menu becomes an "Add" button
/// (join as a member) and tapping opens the Daily as a guest.
///
/// My Dailies only: an unread pill ("3 new") sits in the header row, in the
/// same spot on both layouts, counting messages from other people the
/// viewer hasn't loaded yet (see DailyUnreadService).
/// Gets Daily cards ready before they're on screen: reads each cover and
/// downloads its image into memory, so when the card is built (scrolling
/// to it, switching tabs, opening Dailies) it appears already loaded.
class DailyCoverPrefetch {
  DailyCoverPrefetch._();

  static final Set<String> _started = {};
  // Keeps each image's download alive until it's in the image cache.
  static final Map<String, ImageStream> _loading = {};

  /// Warms the first [count] of [dailies] (once each per session).
  static void warm(List<DailyData> dailies, {int count = 6}) {
    for (final d in dailies.take(count)) {
      if (!_started.add(d.id)) continue;
      _warmOne(d.id);
    }
  }

  static Future<void> _warmOne(String dailyId) async {
    final cover = DailyCoverService.isKnown(dailyId)
        ? DailyCoverService.lastKnown(dailyId)
        : await DailyCoverService.getCoverOnce(dailyId);
    final url = cover?.effectiveImageUrl;
    if (cover == null || !cover.isShowable || url == null) return;
    precache(url);
  }

  /// Downloads [url] into the same cache the card's CachedNetworkImage
  /// reads from.
  static void precache(String url) {
    if (_loading.containsKey(url)) return;
    final stream =
    CachedNetworkImageProvider(url).resolve(ImageConfiguration.empty);
    _loading[url] = stream;
    late final ImageStreamListener listener;
    listener = ImageStreamListener((_, __) {
      stream.removeListener(listener);
    }, onError: (_, __) {
      stream.removeListener(listener);
      _loading.remove(url);
    });
    stream.addListener(listener);
  }
}

class DailyCover extends StatefulWidget {
  final DailyData daily;
  final bool hasBeenViewed;
  final bool forYou;

  /// For You only: called after the viewer successfully adds this Daily, so
  /// the feed can keep the card on screen (showing "Added") instead of
  /// dropping it from under their thumb.
  final VoidCallback? onAdded;

  /// For You only: called after the viewer picks "Not interested", so the
  /// feed can drop this card.
  final VoidCallback? onHidden;

  const DailyCover({
    Key? key,
    required this.daily,
    required this.hasBeenViewed,
    this.forYou = false,
    this.onAdded,
    this.onHidden,
  }) : super(key: key);

  @override
  State<DailyCover> createState() => _DailyCoverState();
}

class _DailyCoverState extends State<DailyCover> {
  // Tallest the cover image gets, as a share of its width (and a hard cap
  // for big screens). A naturally shorter image stays shorter.
  static const double _maxImageAspect = 1.2;
  static const double _maxImageHeight = 480;

  // White strip between the cover image and the card's outline.
  static const double _imageInset = 8;

  // The one accent used for "something new for you".
  static const Color _accent = Color(0xFF0097A7); // cyan[700]

  String? _activeKey;
  Stream<DailyCoverData?>? _coverStream;

  // My Dailies only: live count of unread messages from other people. The
  // last count is remembered so a rebuilt card doesn't flash 0 first.
  static final Map<String, int> _lastUnread = {};
  StreamSubscription<int>? _unreadSub;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _syncCover();
    _syncUnread();
    // On screen: start getting its newest photos ready for opening.
    DailyWarmup.warm(widget.daily.id);
    // Owner's older Daily with a phone-only icon: upload it for everyone.
    DailyIconStore.migrateIfLocal(widget.daily);
  }

  @override
  void didUpdateWidget(covariant DailyCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ListView can hand this State a different Daily when the list
    // reorders (e.g. pinning), so start over if the id changed.
    if (oldWidget.daily.id != widget.daily.id) {
      _activeKey = null;
      _syncCover();
    }
    if (oldWidget.daily.id != widget.daily.id ||
        oldWidget.forYou != widget.forYou) {
      _syncUnread();
    }
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  /// (Re)subscribes to this Daily's unread count. For You cards don't get
  /// one: the viewer isn't a member, so there's nothing "unread" for them.
  void _syncUnread() {
    _unreadSub?.cancel();
    _unreadSub = null;
    _unread = 0;
    if (widget.forYou) return;
    final id = widget.daily.id;
    _unread = _lastUnread[id] ?? 0;
    _unreadSub = DailyUnreadService.watchUnread(id).listen((count) {
      _lastUnread[id] = count;
      if (mounted && count != _unread) setState(() => _unread = count);
    });
  }

  /// (Re)subscribes to the cover when the date has changed since we last
  /// looked (the owner's schedule is per calendar day). Cheap to call from
  /// build(): it does nothing unless the date changed.
  void _syncCover() {
    final key = CoverWindow.dateKey(DateTime.now());
    if (key == _activeKey && _coverStream != null) return;
    _activeKey = key;
    _coverStream = DailyCoverService.watchCover(widget.daily.id);
    // The owner's app keeps the Daily's time zone, title and description
    // on the shared doc the server reads (once per session, owner only).
    if (!widget.forYou) DailyCoverService.syncDailyInfo(widget.daily);
  }

  // For You only: 0 = not added, 1 = adding, 2 = added.
  int _addState = 0;

  Future<void> _addToMyDailies() async {
    if (_addState != 0) return;
    setState(() => _addState = 1);
    // Banned from this Daily: can't add it back while the ban lasts.
    final ban = await DailyModeration.myBan(widget.daily.id);
    if (ban != null) {
      if (!mounted) return;
      setState(() => _addState = 0);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ban.isPermanent
            ? "You're banned from this Daily"
            : "You're banned from this Daily · ${ban.timeLeft}"),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    final result = await DailyMembershipService.addToMyDailies(widget.daily);
    if (!mounted) return;
    final ok = result['success'] == true;
    setState(() => _addState = ok ? 2 : 0);
    if (ok) {
      FeedService.recordInteraction(widget.daily);
      widget.onAdded?.call();
    }
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

  Widget _addButton() {
    final added = _addState == 2;
    final adding = _addState == 1;
    return GestureDetector(
      onTap: _addToMyDailies,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(left: 4, right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: added ? Colors.green.withOpacity(0.12) : Colors.cyan,
          borderRadius: BorderRadius.circular(18),
        ),
        child: adding
            ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2),
        )
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(added ? Icons.check : Icons.add,
                size: 16, color: added ? Colors.green : Colors.white),
            const SizedBox(width: 4),
            Text(
              added ? 'Added' : 'Add',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: added ? Colors.green : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// For You only: small "..." next to Add with "Not interested". Hides the
  /// Daily for good and teaches the feed to show fewer like it.
  Widget _forYouMenu() {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      icon: Icon(Icons.more_vert, color: kc.grey(600), size: 22),
      color: kc.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'interested') {
          FeedService.recordEvent(widget.daily, FeedEvent.interested);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Got it — we'll show more Dailies like this"),
              duration: Duration(seconds: 2),
            ),
          );
        } else if (value == 'not_interested') {
          FeedService.markNotInterested(widget.daily);
          widget.onHidden?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Got it — we'll show fewer Dailies like this"),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'interested',
          child: Row(
            children: [
              Icon(Icons.thumb_up_alt_outlined,
                  size: 20, color: kc.text),
              SizedBox(width: 12),
              Text('Interested',
                  style: TextStyle(fontSize: 16, color: kc.text)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'not_interested',
          child: Row(
            children: [
              Icon(Icons.visibility_off_outlined,
                  size: 20, color: kc.text),
              SizedBox(width: 12),
              Text('Not interested',
                  style: TextStyle(fontSize: 16, color: kc.text)),
            ],
          ),
        ),
      ],
    );
  }

  // Tracks which image URL we've already warmed into the cache, so a
  // revisit to this card never shows even a one-frame loading flash.
  // Precaches through CachedNetworkImageProvider specifically — the same
  // provider the display widget uses below — so this warms the one
  // shared disk-backed cache rather than a separate in-memory-only one.
  String? _precachedUrl;

  void _maybePrecache(BuildContext context, String? imageUrl) {
    if (imageUrl == null || imageUrl == _precachedUrl) return;
    _precachedUrl = imageUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(CachedNetworkImageProvider(imageUrl), context).catchError((e) {
        print('DailyCover: precache error: $e');
      });
    });
  }

  bool _isUserCreatedDaily(DailyData daily) {
    return true;
  }

  /// The Daily's own title font (shared fonts, preloaded at launch: see
  /// DailyFonts). Only the Daily cards and the inside of a Daily use it.
  TextStyle _getFontForDaily(DailyData daily, {FontWeight? weight}) =>
      DailyFonts.style(daily.titleFont, fontWeight: weight);

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    }
  }

  void _showDeleteConfirmation(BuildContext context) {
    final daily = widget.daily;
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: kc.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Delete Daily?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: kc.text,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${daily.title}"? This action cannot be undone.',
          style: TextStyle(
            fontSize: 16,
            color: kc.text,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kc.grey(500),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              DailyList.deleteDaily(daily.id);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${daily.title} deleted'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The post this card's cover came from, if opening should go straight
  /// to it (a cover is showing and you haven't been taken to it yet).
  String? get _coverJumpTarget {
    final cover = DailyCoverService.lastKnown(widget.daily.id);
    if (cover == null || !cover.isShowable) return null;
    final id = cover.jumpMessageId;
    return CoverJump.shouldJump(widget.daily.id, id) ? id : null;
  }

  /// Finger down: get the Daily ready to open (its thread, newest videos),
  /// and if it'll open at the cover post, that post's video and the posts
  /// around it.
  void _warmForOpen() {
    final jumpTo = _coverJumpTarget;
    final cover = DailyCoverService.lastKnown(widget.daily.id);
    DailyWarmup.warm(
      widget.daily.id,
      videos: true,
      aroundMessageId: jumpTo,
      coverVideoUrl: (jumpTo != null && cover?.isVideo == true)
          ? cover?.mediaUrl
          : null,
    );
  }

  Future<void> _handleTap() async {
    final daily = widget.daily;
    // Opened from its cover: start at the cover's post (once).
    final coverMessageId = _coverJumpTarget;

    if (widget.forYou) {
      // Not one of the viewer's Dailies, so no "viewed" bookkeeping.
      // InsideDaily works out for itself that the viewer is a guest.
      FeedService.recordInteraction(daily);
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) =>
                InsideDaily(daily: daily, coverMessageId: coverMessageId)),
      );
      return;
    }

    bool wasUnviewed = !widget.hasBeenViewed;

    // Only today's scheduled prompt counts (prompts are per day, like
    // covers).
    final prompt =
    wasUnviewed ? await DailyCoverService.todayPrompt(daily.id) : '';
    if (!mounted) return;

    if (wasUnviewed && prompt.isNotEmpty) {
      // Marked as viewed once they answer or skip (inside UponOpeningDaily).
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UponOpeningDaily(
            daily: daily,
            prompt: prompt,
          ),
        ),
      );
    } else {
      await DailyList.markAsViewed(daily.id);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              InsideDaily(daily: daily, coverMessageId: coverMessageId),
        ),
      );
    }
  }

  BoxDecoration _cardDecoration(Color dailyColor) {
    final daily = widget.daily;
    // Neutral card: white body, dark grey outline (heavier when pinned).
    // The "new today" signal is the small cyan badge, not a tint.
    return BoxDecoration(
      color: kc.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: kc.grey(800),
        width: (daily.isPinned && !widget.forYou) ? 2 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.1),
          spreadRadius: 1,
          blurRadius: 3,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  bool get _hasPrompt =>
      (DailyCoverService.knownPrompt(widget.daily.id) ?? '').isNotEmpty;

  /// Cyan dot on the icon: My Dailies -> not opened yet today;
  /// For You -> this Daily has an entry prompt waiting.
  bool get _showBadge =>
      widget.forYou ? _hasPrompt : !widget.hasBeenViewed;


  /// My Dailies only: solid accent pill with the unread count, e.g.
  /// "3 new". Sits in the header row on both layouts, so it lands in the
  /// same place whether or not today's cover has an image. Pops in when
  /// something arrives and shrinks away once the Daily is opened.
  Widget _unreadPill() {
    final show = !widget.forYou && _unread > 0;
    final label = _unread > 99 ? '99+ new' : '$_unread new';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: !show
          ? const SizedBox.shrink(key: ValueKey('no_unread'))
          : Container(
        key: const ValueKey('unread'),
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_rounded,
                size: 11, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconSquare({required double size, required double iconSize}) {
    final daily = widget.daily;
    final tile = DailyIconTile(
      icon: daily.icon,
      customIconPath: daily.customIconPath,
      size: size,
      radius: 12,
    );
    if (!_showBadge) return tile;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: tile),
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.cyan,
                shape: BoxShape.circle,
                border: Border.all(color: kc.background, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pinBadge() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Color(0xFF2E2E2E),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.push_pin,
        size: 14,
        color: Colors.white,
      ),
    );
  }

  Widget _menuButton(BuildContext context) {
    if (widget.forYou) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _addButton(),
          _forYouMenu(),
        ],
      );
    }
    final daily = widget.daily;
    final isUserCreated = _isUserCreatedDaily(daily);

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: kc.grey(600),
        size: 24,
      ),
      color: kc.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (value) {
        if (value == 'pin') {
          DailyList.togglePin(daily.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                daily.isPinned ? '${daily.title} unpinned!' : '${daily.title} pinned!',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (value == 'delete') {
          _showDeleteConfirmation(context);
        } else if (value == 'manage') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ManageDailyScreen(daily: daily),
            ),
          );
        }
      },
      itemBuilder: (BuildContext context) {
        List<PopupMenuEntry<String>> menuItems = [
          PopupMenuItem<String>(
            value: 'pin',
            child: Row(
              children: [
                Icon(
                  daily.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 20,
                  color: kc.text,
                ),
                const SizedBox(width: 12),
                Text(
                  daily.isPinned ? 'Unpin' : 'Pin',
                  style: TextStyle(
                    fontSize: 16,
                    color: kc.text,
                  ),
                ),
              ],
            ),
          ),
        ];

        if (isUserCreated) {
          menuItems.add(
            PopupMenuItem<String>(
              value: 'manage',
              child: Row(
                children: [
                  Icon(Icons.settings, size: 20, color: kc.text),
                  SizedBox(width: 12),
                  Text(
                    'Manage',
                    style: TextStyle(
                      fontSize: 16,
                      color: kc.text,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        menuItems.add(
          const PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20, color: Colors.red),
                SizedBox(width: 12),
                Text(
                  'Delete',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        );

        return menuItems;
      },
    );
  }

  /// The original card — used whenever there's no cover.
  Widget _buildClassicCard(BuildContext context, Color dailyColor) {
    final daily = widget.daily;
    final pinned = daily.isPinned && !widget.forYou;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(dailyColor),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconSquare(size: 60, iconSize: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _FitTitle(
                        daily.title,
                        style: _getFontForDaily(daily, weight: FontWeight.w700).copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kc.text,
                        ),
                      ),
                    ),
                    _unreadPill(),
                    if (pinned) ...[
                      const SizedBox(width: 6),
                      _pinBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  daily.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: kc.grey(700),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // For You cards skip the date.
                if (!widget.forYou) ...[
                  const SizedBox(height: 8),
                  Text(
                    _formatDate(daily.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: kc.grey(500),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _menuButton(context),
        ],
      ),
    );
  }

  /// Title up top, hook below it across the full width, cover image below
  /// that running edge to edge inside the card.
  Widget _buildCoverCard(
      BuildContext context, Color dailyColor, DailyCoverData cover) {
    final daily = widget.daily;
    // No hook (AI hooks turned off, none could be written, or a text
    // cover, where the text is the hook): no line.
    final hook = cover.effectiveHook;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _cardDecoration(dailyColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 0),
            child: Row(
              children: [
                _iconSquare(size: 44, iconSize: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: _FitTitle(
                    daily.title,
                    style: _getFontForDaily(daily, weight: FontWeight.w700).copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: kc.text,
                    ),
                  ),
                ),
                _unreadPill(),
                if (daily.isPinned && !widget.forYou) ...[
                  const SizedBox(width: 6),
                  _pinBadge(),
                  const SizedBox(width: 4),
                ],
                _menuButton(context),
              ],
            ),
          ),
          if (hook != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Text(
                hook,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                  color: kc.grey(850),
                ),
              ),
            )
          else
            const SizedBox(height: 10),
          // The cover is the focus: almost the card's full width, with a
          // thin white strip between it and the outline, and allowed to be
          // tall (up to 1.2x its width). A text post shows as a quote card.
          if (cover.showsTextCover)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  _imageInset, 0, _imageInset, _imageInset),
              child: _quoteCard(cover),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  _imageInset, 0, _imageInset, _imageInset),
              child: LayoutBuilder(builder: (context, box) {
                final maxH = (box.maxWidth * _maxImageAspect)
                    .clamp(0.0, _maxImageHeight)
                    .toDouble();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxH),
                    child: Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: cover.effectiveImageUrl!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          // Disk-backed — unlike Image.network, this survives
                          // app restarts, so a cold launch after the first
                          // one doesn't re-download every cover from scratch.
                          placeholder: (context, url) => Container(
                            height: box.maxWidth * 0.75,
                            width: double.infinity,
                            color: kc.grey(200),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: kc.adapt(const Color(0xFFB0B5BC)),
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            height: 120,
                            width: double.infinity,
                            color: kc.grey(200),
                            child: Icon(Icons.broken_image_outlined,
                                color: kc.grey(400), size: 36),
                          ),
                        ),
                        if (cover.showsVideoBadge)
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  /// A text post as the cover: the words big on soft cyan, with who said
  /// it small underneath. Text size steps down as it gets longer.
  Widget _quoteCard(DailyCoverData cover) {
    final text = cover.text!.trim();
    final size = text.length <= 60
        ? 23.0
        : text.length <= 140
        ? 19.0
        : 16.5;
    final name = cover.authorName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyan.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, size: 30, color: Colors.cyan[600]),
          const SizedBox(height: 2),
          Text(
            text,
            maxLines: 7,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: size,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: kc.text,
            ),
          ),
          if (name != null && name.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (cover.authorUid != null) ...[
                  MemberAvatar(userId: cover.authorUid!, size: 22),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: kc.grey(600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncCover();

    final dailyColor = Color(widget.daily.iconColor ?? 0xFF00BCD4);

    return GestureDetector(
      // Finger down: its newest videos start loading too, so they're
      // playing by the time the Daily opens.
      onTapDown: (_) => _warmForOpen(),
      onTap: _handleTap,
      child: StreamBuilder<DailyCoverData?>(
        stream: _coverStream,
        // Seen before this session -> shown right away, no loading.
        initialData: DailyCoverService.lastKnown(widget.daily.id),
        builder: (context, snapshot) {
          final cover = snapshot.data;
          final showCover = cover != null && cover.isShowable;

          if (showCover) {
            _maybePrecache(context, cover.effectiveImageUrl);
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: showCover
                ? KeyedSubtree(
              key: const ValueKey('cover'),
              child: _buildCoverCard(context, dailyColor, cover!),
            )
                : KeyedSubtree(
              key: const ValueKey('classic'),
              child: _buildClassicCard(context, dailyColor),
            ),
          );
        },
      ),
    );
  }
}

/// A Daily's title on its card. Titles wrap at spaces as usual (up to two
/// lines). When a single word is too long to fit on a line (e.g.
/// "testingdailyfeed"), the title shrinks a little, down to 75% of its
/// size, so the word isn't split mid-letter; past that it ends with "…".
class _FitTitle extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _FitTitle(this.text, {required this.style});

  static const double _minScale = 0.6;

  double _widest(TextStyle style, TextScaler scaler) {
    var widest = 0.0;
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (tp.width > widest) widest = tp.width;
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        var fitted = style;
        final size = style.fontSize ?? 18;
        final widest = _widest(style, scaler);
        if (box.maxWidth.isFinite && widest > box.maxWidth && widest > 0) {
          final scale = (box.maxWidth / widest).clamp(_minScale, 1.0);
          // A hair under, so rounding never pushes it back over the edge.
          fitted = style.copyWith(fontSize: size * scale * 0.98);
        }
        // One long word ("testingdailyfeed") stays on one line: shrunk to
        // fit, or cut with "..." if it's extremely long, never split in the
        // middle of the word.
        final oneWord = !text.trim().contains(RegExp(r'\s'));
        return Text(
          text,
          maxLines: oneWord ? 1 : 2,
          softWrap: !oneWord,
          overflow: TextOverflow.ellipsis,
          style: fitted,
        );
      },
    );
  }
}