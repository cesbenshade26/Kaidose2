import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'DailyCover.dart';
import 'FeedService.dart';

/// Holds the state of the For You tab of Dailies: a discovery feed of Public
/// Dailies the viewer isn't in yet.
///
/// One shared instance for the session ([shared]), started at sign-in by
/// DailiesPreload, so the whole Dailies screen can be ONE scroll view and
/// leaving or switching tabs never reloads the feed, and ranking still comes entirely from FeedService.getRankedFeed(),
/// so swapping in a better feed later needs no changes here.
class DailyForYouController extends ChangeNotifier {
  static const int pageSize = 10;

  // One feed for the whole session, started at sign-in by DailiesPreload,
  // so the tab is ready (cards, position, pages loaded) whenever it's shown.
  static DailyForYouController? _shared;
  static DailyForYouController get shared =>
      _shared ??= DailyForYouController();
  static DailyForYouController? get sharedOrNull => _shared;

  /// Signed out / switched accounts: the next [shared] starts fresh.
  static void resetShared() {
    _shared?.dispose();
    _shared = null;
  }

  // Older than this, the feed quietly refreshes the next time you're at
  // the top of For You (never while you're scrolled down in it).
  static const Duration _stale = Duration(minutes: 10);
  DateTime? _loadedAt;

  List<DailyData> _feed = [];
  bool isLoading = true;
  bool hasError = false;
  int visibleCount = pageSize;

  // Dailies added from a card this session: they stay on screen (as
  // "Added") until the next refresh, instead of vanishing mid-scroll.
  final Set<String> addedHere = {};
  // "Not interested" this session: gone from the list right away (the
  // choice itself is saved by FeedService and also filters future loads).
  final Set<String> hiddenHere = {};

  // IDs of every Daily currently in My Dailies (created or joined), kept
  // live from the same stream the My Dailies tab reads. Joining from
  // anywhere (search, inside a Daily as a guest, another device) drops it
  // from For You right away.
  Set<String> _mineIds = {};
  StreamSubscription<List<DailyData>>? _mineSub;
  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Whose feed this is (a different account gets a new one).
  final String? ownerUid = FirebaseAuth.instance.currentUser?.uid;

  DailyForYouController() {
    loadFeed();
    _mineSub = DailyList.getDailiesStream().listen((dailies) {
      if (_disposed) return;
      _mineIds = dailies.map((d) => d.id).toSet();
      notifyListeners();
    }, onError: (e) {
      print('DailyForYouController: My Dailies stream error: $e');
    });
  }

  /// Refreshes quietly if the feed is old. Only call when the viewer is at
  /// the top of For You, so cards never shuffle under them.
  void refreshIfStale() {
    final at = _loadedAt;
    if (isLoading || at == null) return;
    if (DateTime.now().difference(at) > _stale) loadFeed(silent: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _mineSub?.cancel();
    super.dispose();
  }

  /// [silent] keeps the current cards on screen while refreshing (used by
  /// pull-to-refresh) instead of swapping them for a spinner.
  Future<void> loadFeed({bool silent = false}) async {
    if (!silent || _feed.isEmpty) {
      isLoading = true;
    }
    hasError = false;
    if (!_disposed) notifyListeners();

    try {
      final ranked = await FeedService.getRankedFeed();
      if (_disposed) return;
      _feed = ranked.map((s) => s.daily).toList();
      _loadedAt = DateTime.now();
      visibleCount = pageSize;
      addedHere.clear();
      hiddenHere.clear();
      isLoading = false;
      notifyListeners();
    } catch (e) {
      print('DailyForYouController: feed load error: $e');
      if (_disposed) return;
      isLoading = false;
      hasError = true;
      notifyListeners();
    }
  }

  /// Public Dailies the viewer neither created nor joined, in feed order.
  /// Private Dailies never show here — they're only reachable through
  /// search's Request to Join.
  ///
  /// The one exception: a Daily added from its For You card this session
  /// stays (showing "Added") until the next refresh, so it doesn't vanish
  /// from under the user's thumb.
  List<DailyData> get eligible {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return _feed
        .where((d) =>
    !hiddenHere.contains(d.id) &&
        d.privacy == 'Public' &&
        d.creatorUid != uid &&
        (!_mineIds.contains(d.id) || addedHere.contains(d.id)))
        .toList();
  }

  /// Called as the user nears the bottom of the screen.
  void loadMoreIfNeeded() {
    if (visibleCount < eligible.length) {
      visibleCount += pageSize;
      notifyListeners();
    }
  }

  void hide(String id) {
    hiddenHere.add(id);
    notifyListeners();
  }
}

/// The For You cards as a sliver, so it scrolls together with the rest of
/// the Dailies screen.
class DailyForYouSliver extends StatelessWidget {
  final DailyForYouController controller;

  const DailyForYouSliver({Key? key, required this.controller})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isLoading) {
          return _box(const CircularProgressIndicator(color: Colors.cyan));
        }

        if (controller.hasError) {
          return _box(_message(
            icon: Icons.cloud_off_outlined,
            title: "Couldn't load For You",
            body: 'Check your connection and try again',
            action: TextButton(
              onPressed: controller.loadFeed,
              child: const Text('Retry', style: TextStyle(color: Colors.cyan)),
            ),
          ));
        }

        final eligible = controller.eligible;

        if (eligible.isEmpty) {
          return _box(_message(
            icon: Icons.explore_outlined,
            title: "You're all caught up",
            body: 'New Public Dailies will show up here as people create them',
          ));
        }

        final shown = eligible.take(controller.visibleCount).toList();
        final hasMore = shown.length < eligible.length;

        // Count these cards as shown (once per Daily per app session).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          FeedService.recordImpressions(shown);
        });

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                if (index >= shown.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.cyan, strokeWidth: 2.5),
                      ),
                    ),
                  );
                }
                final daily = shown[index];
                return DailyCover(
                  key: ValueKey('foryou_${daily.id}'),
                  daily: daily,
                  hasBeenViewed: true,
                  forYou: true,
                  onAdded: () => controller.addedHere.add(daily.id),
                  onHidden: () => controller.hide(daily.id),
                );
              },
              childCount: shown.length + (hasMore ? 1 : 0),
            ),
          ),
        );
      },
    );
  }

  /// Loading / error / empty states: a fixed-height centered block.
  Widget _box(Widget child) {
    return SliverToBoxAdapter(
      child: SizedBox(height: 360, child: Center(child: child)),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 80, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700]),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            body,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ),
        if (action != null) action,
      ],
    );
  }
}