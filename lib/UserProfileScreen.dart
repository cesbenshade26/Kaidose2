import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'BackgroundPic.dart';
import 'ProfilePicManager.dart';
import 'ProfileStatsRow.dart';
import 'UserBubbleRow.dart';
import 'StoryRing.dart';
import 'DailyPostActivity.dart';
import 'ClipsActivity.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'SafetyService.dart';
import 'SafetySheets.dart';

/// Another person's profile, laid out exactly like your own Profile tab:
/// banner photo, avatar on its lower edge, stats, bio, Daily Bubbles, then
/// the Dailies and Clips tabs showing what THEY posted. Like your Profile,
/// the whole page scrolls as one, and scrolling back up a little brings in a
/// compact bar (back, both tabs).
///
/// Dailies only lists posts from public Dailies (the same as everyone sees
/// on your own profile). Their posts and clips can be viewed, not edited.
///
/// Open it from anywhere another user is tappable with
/// [UserProfileScreen.open] so every entry point behaves the same.
class UserProfileScreen extends StatefulWidget {
  final String userId;

  /// Shown right away while the real profile loads.
  final String username;

  const UserProfileScreen({
    Key? key,
    required this.userId,
    this.username = '',
  }) : super(key: key);

  /// Pushes the profile screen. Does nothing if there's no user id to show.
  static void open(BuildContext context, String? userId, {String? username}) {
    if (userId == null || userId.isEmpty || userId == 'current_user') return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: userId,
          username: username ?? '',
        ),
      ),
    );
  }

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  String? _username;
  Uint8List? _avatar;
  Uint8List? _banner;
  String? _bio;
  bool _loading = true;
  bool _notFound = false;
  int _selectedTabIndex = 0;

  // Whole-page scrolling, same as Profile: the header scrolls away with the
  // content, and scrolling back UP a little brings in a compact bar.
  final ScrollController _outer = ScrollController();
  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 460;
  bool _showBar = false;
  double _upAccum = 0;

  @override
  void initState() {
    super.initState();
    _username = widget.username.isEmpty ? null : widget.username;
    SafetyService.instance.changes.addListener(_onSafety);
    _load();
  }

  @override
  void dispose() {
    SafetyService.instance.changes.removeListener(_onSafety);
    _outer.dispose();
    super.dispose();
  }

  void _onSafety() {
    if (mounted) setState(() {});
  }

  bool get _isMe => widget.userId == FirebaseAuth.instance.currentUser?.uid;
  bool get _iBlocked => SafetyService.instance.isBlocked(widget.userId);
  bool get _blocksMe => SafetyService.instance.blocksMe(widget.userId);

  void _openActions() =>
      UserActions.show(context, uid: widget.userId, username: _username);

  /// Shown instead of their stats, bio and posts while blocked.
  Widget _blockedPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
      child: Column(
        children: [
          Icon(Icons.block_rounded, size: 40, color: Colors.grey[350]),
          const SizedBox(height: 10),
          Text(
            _iBlocked
                ? 'You blocked ${_username ?? 'this account'}'
                : "This account isn't available",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _iBlocked
                ? "They can't see your profile or message you."
                : "You can't see their posts right now.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: Colors.grey[600]),
          ),
          if (_iBlocked) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () =>
                  BlockFlow.unblock(context, widget.userId, username: _username),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey[300]!),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Unblock'),
            ),
          ],
        ],
      ),
    );
  }

  Uint8List? _decode(dynamic b64) {
    if (b64 is! String || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (!mounted) return;
      if (!doc.exists) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }
      final data = doc.data() ?? {};
      setState(() {
        final name = data['username'] as String?;
        if (name != null && name.isNotEmpty) _username = name;
        _avatar = _decode(data['profilePicBase64']);
        _banner = _decode(data['backgroundPicBase64']);

        // Same lookup as BioManager: the plain `bio` field, then the old
        // formatted `bioData.text` for accounts that haven't re-saved.
        String? bio = data['bio'] as String?;
        if (bio == null || bio.trim().isEmpty) {
          final old = data['bioData'];
          if (old is Map) bio = old['text'] as String?;
        }
        _bio = (bio == null || bio.trim().isEmpty) ? null : bio.trim();

        _loading = false;
      });
    } catch (e) {
      print('UserProfileScreen: load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Tabs ───────────────────────────────────────────────────────────────────

  void _setTab(int i) {
    if (i == _selectedTabIndex) return;
    setState(() {
      _selectedTabIndex = i;
      _showBar = false;
      _upAccum = 0;
    });
  }

  /// Same as Profile: shows the compact bar when the user scrolls UP after
  /// the header has scrolled out of view; hides it when scrolling down or
  /// when the real header is back on screen.
  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification) return false;

    final outerOffset = _outer.hasClients ? _outer.offset : 0.0;
    if (outerOffset < _headerHeight - 2) {
      _upAccum = 0;
      if (_showBar) setState(() => _showBar = false);
      return false;
    }

    if (n.metrics.pixels > n.metrics.maxScrollExtent) return false;

    final delta = n.scrollDelta ?? 0;
    if (delta < 0) {
      _upAccum += -delta;
      if (_upAccum > 8 && !_showBar) setState(() => _showBar = true);
    } else if (delta > 0) {
      _upAccum = 0;
      if (_showBar) setState(() => _showBar = false);
    }
    return false;
  }

  Widget _barTab(int i, IconData off, IconData on, String label) {
    final selected = _selectedTabIndex == i;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setTab(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Icon(
            selected ? on : off,
            size: 24,
            color: selected ? Colors.black : Colors.grey[400],
          ),
        ),
      ),
    );
  }

  /// The compact bar: back, both tabs, and their name.
  Widget _buildFloatingBar() {
    final topInset = MediaQuery.of(context).padding.top;
    return IgnorePointer(
      ignoring: !_showBar,
      child: AnimatedSlide(
        offset: _showBar ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _showBar ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: EdgeInsets.only(top: topInset, left: 4, right: 12),
                height: topInset + 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.86),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: Colors.black, size: 24),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    _barTab(0, Icons.wb_sunny_outlined, Icons.wb_sunny_rounded,
                        'Dailies'),
                    _barTab(1, Icons.videocam_outlined, Icons.videocam, 'Clips'),
                    const Spacer(),
                    if (_username != null)
                      Flexible(
                        child: Text(
                          _username!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    if (!_isMe)
                      IconButton(
                        icon: const Icon(Icons.more_horiz_rounded,
                            color: Colors.black87, size: 24),
                        onPressed: _openActions,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Same tab bar as Profile: Dailies and Clips icons with a sliding line.
  Widget _buildTabBar() {
    const icons = [
      [Icons.wb_sunny_outlined, Icons.wb_sunny_rounded],
      [Icons.videocam_outlined, Icons.videocam],
    ];
    const labels = ['Dailies', 'Clips'];

    return Column(
      children: [
        Row(
          children: List.generate(2, (i) {
            final selected = _selectedTabIndex == i;
            return Expanded(
              child: Semantics(
                label: labels[i],
                button: true,
                selected: selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setTab(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: TweenAnimationBuilder<Color?>(
                      duration: const Duration(milliseconds: 200),
                      tween: ColorTween(
                        end: selected ? Colors.black : Colors.grey[400],
                      ),
                      builder: (context, color, _) => Icon(
                        icons[i][selected ? 1 : 0],
                        size: 25,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        SizedBox(
          height: 2.5,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(height: 1, color: Colors.grey[200]),
              ),
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment(_selectedTabIndex * 2 - 1.0, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / 2,
                  child: Center(
                    child: Container(
                      width: 28,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabContent() {
    if (_notFound) return const SizedBox();
    // Keyed by user so switching between two people's profiles never reuses
    // the previous person's posts.
    switch (_selectedTabIndex) {
      case 0:
        return DailyPostActivity(
          key: ValueKey('dailies-${widget.userId}'),
          userId: widget.userId,
        );
      case 1:
        return ClipsActivity(
          key: ValueKey('clips-${widget.userId}'),
          userId: widget.userId,
        );
      default:
        return const SizedBox();
    }
  }

  // ─── Header ─────────────────────────────────────────────────────────────────

  Widget _buildBanner() {
    const h = BackgroundSpec.bannerHeight;
    return SizedBox(
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _banner != null
              ? Image.memory(
            _banner!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                Container(decoration: BackgroundSpec.defaultDecoration),
          )
              : Container(decoration: BackgroundSpec.defaultDecoration),
          // Light scrim so the status bar and back arrow stay readable
          IgnorePointer(
              child: Container(decoration: BackgroundSpec.scrimDecoration)),
        ],
      ),
    );
  }

  Widget _buildBioText() {
    if (_bio == null) {
      // No bio: keep the one line of space your own Profile uses (where it
      // shows "Add a bio") so everything sits at the same height.
      return const SizedBox(height: 15 * 1.3);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          _bio!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.3,
            color: Colors.grey[800],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const avatarSize = BackgroundSpec.avatarSize;
    return Stack(
      key: _headerKey,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: BackgroundSpec.bannerHeight,
          child: _buildBanner(),
        ),
        SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                  height: BackgroundSpec.bannerHeight - avatarSize / 2),
              SizedBox(
                height: avatarSize,
                child: Center(
                  // Ring + tap-to-watch when they have a story you can see.
                  child: UserStoryRing(
                    userId: widget.userId,
                    username: _username ?? widget.username,
                    child: Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[300],
                      ),
                      child: ClipOval(
                        child: _avatar != null
                            ? Image.memory(
                          _avatar!,
                          width: avatarSize,
                          height: avatarSize,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) =>
                          const DefaultProfilePic(
                              size: avatarSize, borderWidth: 0),
                        )
                            : const DefaultProfilePic(
                            size: avatarSize, borderWidth: 0),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_notFound)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 24),
                  child: Text('This account no longer exists',
                      style: TextStyle(color: Colors.grey[600])),
                )
              else if (_iBlocked || _blocksMe)
                _blockedPanel()
              else ...[
                  ProfileStatsRow(
                    userId: widget.userId,
                    username: _username ?? '',
                    showProgress: false,
                  ),
                  const SizedBox(height: 10),
                  _buildBioText(),
                  const SizedBox(height: 8),
                  UserBubbleRow(userId: widget.userId),
                  const SizedBox(height: 4),
                  _buildTabBar(),
                ],
            ],
          ),
        ),

        // Back (top left, where your Profile has the bell)
        Positioned(
          top: 50,
          left: 4,
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
            ),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),

        // Mute, hide story, remove friend, report, block (top right)
        if (!_isMe && !_notFound)
          Positioned(
            top: 50,
            right: 4,
            child: IconButton(
              icon: const Icon(
                Icons.more_horiz_rounded,
                color: Colors.white,
                size: 28,
                shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
              ),
              onPressed: _openActions,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Measure the header so we know when it has fully scrolled away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _headerKey.currentContext?.size?.height;
      if (h != null && h > 0) _headerHeight = h;
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _showBar ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: NestedScrollView(
                controller: _outer,
                headerSliverBuilder: (context, innerScrolled) => [
                  SliverToBoxAdapter(child: _buildHeader()),
                ],
                body: _loading
                    ? const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: CircularProgressIndicator(color: Colors.cyan),
                  ),
                )
                    : (_iBlocked || _blocksMe)
                    ? const SizedBox.shrink()
                    : _buildTabContent(),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildFloatingBar(),
            ),
          ],
        ),
      ),
    );
  }
}