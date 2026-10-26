import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'DailyCoverData.dart';
import 'ManageDaily.dart';
import 'UponOpeningDaily.dart';
import 'InsideDaily.dart';
import 'FeedService.dart';
import 'DailyMembershipService.dart';

/// The cover card for a single Daily, as shown in the Dailies list.
///
/// Two layouts:
///  - With a cover (a photo/video was picked for this viewer's
///    time-zone-day): header row (icon, title, pin badge, menu), the hook
///    across the full width below it, then the cover image edge to edge
///    at the bottom of the card.
///  - Without one (nothing eligible was posted, or it's still being
///    generated): the original card, unchanged.
///
/// Asking for the cover is what triggers its generation the first time
/// anyone opens the app after their local midnight; see DailyCoverService.
///
/// [forYou] switches the card to its For You feed form, for Dailies the
/// viewer is not in: the pin/manage/delete menu becomes an "Add" button
/// (join as a member), tapping opens the Daily as a guest, and the cover is
/// only read — never generated — so scrolling the feed can't trigger AI.
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
  // Tallest the cover image gets; a naturally shorter image stays shorter.
  static const double _maxImageHeight = 240;

  String? _activeKey;
  Stream<DailyCoverData?>? _coverStream;

  @override
  void initState() {
    super.initState();
    _syncCover();
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
  }

  /// (Re)subscribes to the cover doc and asks for it to be generated
  /// when the viewer's time-zone-day has changed since we last looked.
  /// Cheap to call from build(): it does nothing unless the key changed.
  void _syncCover() {
    final key = CoverWindow.forNow().key;
    if (key == _activeKey && _coverStream != null) return;
    _activeKey = key;
    if (widget.forYou) {
      // Read-only: use a cover if a member's app already made one.
      _coverStream =
          Stream.fromFuture(DailyCoverService.getCoverOnce(widget.daily.id));
      return;
    }
    _coverStream = DailyCoverService.watchCover(widget.daily.id);
    DailyCoverService.ensureCover(widget.daily.id);
  }

  // For You only: 0 = not added, 1 = adding, 2 = added.
  int _addState = 0;

  Future<void> _addToMyDailies() async {
    if (_addState != 0) return;
    setState(() => _addState = 1);
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
      icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 22),
      color: Colors.white,
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
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'interested',
          child: Row(
            children: [
              Icon(Icons.thumb_up_alt_outlined,
                  size: 20, color: Colors.black87),
              SizedBox(width: 12),
              Text('Interested',
                  style: TextStyle(fontSize: 16, color: Colors.black87)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'not_interested',
          child: Row(
            children: [
              Icon(Icons.visibility_off_outlined,
                  size: 20, color: Colors.black87),
              SizedBox(width: 12),
              Text('Not interested',
                  style: TextStyle(fontSize: 16, color: Colors.black87)),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Daily?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${daily.title}"? This action cannot be undone.',
          style: const TextStyle(
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
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

  Future<void> _handleTap() async {
    final daily = widget.daily;

    if (widget.forYou) {
      // Not one of the viewer's Dailies, so no "viewed" bookkeeping.
      // InsideDaily works out for itself that the viewer is a guest.
      FeedService.recordInteraction(daily);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => InsideDaily(daily: daily)),
      );
      return;
    }

    bool wasUnviewed = !widget.hasBeenViewed;

    if (wasUnviewed && daily.dailyEntryPrompt.isNotEmpty) {
      // Mark as viewed AFTER showing the prompt (moved inside UponOpeningDaily)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UponOpeningDaily(
            daily: daily,
          ),
        ),
      );
    } else {
      await DailyList.markAsViewed(daily.id);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => InsideDaily(daily: daily),
        ),
      );
    }
  }

  BoxDecoration _cardDecoration(Color dailyColor) {
    final daily = widget.daily;
    // Neutral card: white body, dark grey outline (heavier when pinned).
    // The "new today" signal is the small cyan badge, not a tint.
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Colors.grey[800]!,
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

  bool get _hasPrompt => widget.daily.dailyEntryPrompt.trim().isNotEmpty;

  /// Cyan dot on the icon: My Dailies -> not opened yet today;
  /// For You -> this Daily has an entry prompt waiting.
  bool get _showBadge =>
      widget.forYou ? _hasPrompt : !widget.hasBeenViewed;

  /// For You only: the Daily's entry prompt, one truncated line.
  Widget _promptLine() {
    if (!widget.forYou || !_hasPrompt) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_outline, size: 14, color: Colors.cyan),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.daily.dailyEntryPrompt.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconSquare({required double size, required double iconSize}) {
    final daily = widget.daily;
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: daily.customIconPath != null && File(daily.customIconPath!).existsSync()
          ? ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(daily.customIconPath!),
          fit: BoxFit.cover,
        ),
      )
          : Icon(
        daily.icon,
        color: Colors.grey[800],
        size: iconSize,
      ),
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
                border: Border.all(color: Colors.white, width: 2),
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
        color: Colors.cyan,
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
        color: Colors.grey[600],
        size: 24,
      ),
      color: Colors.white,
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
                  color: Colors.black87,
                ),
                const SizedBox(width: 12),
                Text(
                  daily.isPinned ? 'Unpin' : 'Pin',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ];

        if (isUserCreated) {
          menuItems.add(
            const PopupMenuItem<String>(
              value: 'manage',
              child: Row(
                children: [
                  Icon(Icons.settings, size: 20, color: Colors.black87),
                  SizedBox(width: 12),
                  Text(
                    'Manage',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
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

  /// The original card, untouched — used whenever there's no cover.
  Widget _buildClassicCard(BuildContext context, Color dailyColor) {
    final daily = widget.daily;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
                      child: Text(
                        daily.title,
                        style: _getFontForDaily(daily).copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    if (daily.isPinned && !widget.forYou) _pinBadge(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  daily.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                _promptLine(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Active Friends: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(daily.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
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
    final imageUrl = cover.effectiveImageUrl!;
    final hook = cover.effectiveHook ?? "See what's new in ${daily.title}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration(dailyColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                _iconSquare(size: 44, iconSize: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    daily.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _getFontForDaily(daily).copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (daily.isPinned && !widget.forYou) ...[
                  _pinBadge(),
                  const SizedBox(width: 4),
                ],
                _menuButton(context),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              hook,
              style: TextStyle(
                fontSize: 15,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: Colors.grey[850],
              ),
            ),
          ),
          if (widget.forYou && _hasPrompt)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _promptLine(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _maxImageHeight),
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      // Disk-backed — unlike Image.network, this survives
                      // app restarts, so a cold launch after the first
                      // one doesn't re-download every cover from scratch.
                      placeholder: (context, url) => Container(
                        height: 180,
                        width: double.infinity,
                        color: Colors.grey[200],
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.cyan,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 120,
                        width: double.infinity,
                        color: Colors.grey[200],
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.grey[400], size: 36),
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
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncCover();

    final dailyColor = Color(widget.daily.iconColor ?? 0xFF00BCD4);

    return GestureDetector(
      onTap: _handleTap,
      child: StreamBuilder<DailyCoverData?>(
        stream: _coverStream,
        builder: (context, snapshot) {
          final cover = snapshot.data;
          final showCover = cover != null &&
              cover.status == CoverStatus.ready &&
              cover.effectiveImageUrl != null;

          if (showCover) {
            _maybePrecache(context, cover.effectiveImageUrl);
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: showCover
                ? KeyedSubtree(
              key: const ValueKey('cover'),
              child: _buildCoverCard(context, dailyColor, cover),
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