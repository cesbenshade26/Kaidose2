import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'DailyCover.dart';
import 'FeedService.dart';

/// The For You tab of Dailies: a discovery feed of Public Dailies the viewer
/// isn't in yet. Cards are the normal cover cards in their For You form
/// (an "Add" button instead of the pin/manage/delete menu; tapping opens the
/// Daily as a guest).
///
/// Ranking comes entirely from FeedService.getRankedFeed(), so swapping in a
/// better feed later needs no changes here. This widget only filters
/// (public, not already mine) and pages what it's handed.
class DailyForYouFeed extends StatefulWidget {
  const DailyForYouFeed({Key? key}) : super(key: key);

  @override
  State<DailyForYouFeed> createState() => _DailyForYouFeedState();
}

class _DailyForYouFeedState extends State<DailyForYouFeed>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 10;

  final ScrollController _scrollController = ScrollController();

  List<DailyData> _feed = [];
  bool _isLoading = true;
  bool _hasError = false;
  int _visibleCount = _pageSize;
  // Dailies added from a card this session: they stay on screen (as
  // "Added") until the next refresh, instead of vanishing mid-scroll.
  final Set<String> _addedHere = {};
  VoidCallback? _dailyListListener;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _scrollController.addListener(_onScroll);

    // My Dailies can finish loading after the feed does (it loads in
    // parallel), so re-filter whenever it changes.
    _dailyListListener = () {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    };
    DailyList.addListener(_dailyListListener!);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (_dailyListListener != null) {
      DailyList.removeListener(_dailyListListener!);
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400 &&
        _visibleCount < _eligible.length) {
      setState(() => _visibleCount += _pageSize);
    }
  }

  Future<void> _loadFeed() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }
    try {
      final ranked = await FeedService.getRankedFeed();
      if (!mounted) return;
      setState(() {
        _feed = ranked.map((s) => s.daily).toList();
        _visibleCount = _pageSize;
        _addedHere.clear();
        _isLoading = false;
      });
    } catch (e) {
      print('DailyForYouFeed: feed load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  /// Public Dailies the viewer neither created nor joined, in feed order.
  /// Private Dailies never show here — they're only reachable through
  /// search's Request to Join.
  List<DailyData> get _eligible {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final mine = DailyList.dailies.map((d) => d.id).toSet();
    return _feed
        .where((d) =>
    d.privacy == 'Public' &&
        d.creatorUid != uid &&
        (!mine.contains(d.id) || _addedHere.contains(d.id)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }

    if (_hasError) {
      return _message(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load For You",
        body: 'Check your connection and try again',
        action: TextButton(
          onPressed: _loadFeed,
          child: const Text('Retry', style: TextStyle(color: Colors.cyan)),
        ),
      );
    }

    final eligible = _eligible;

    if (eligible.isEmpty) {
      return RefreshIndicator(
        color: Colors.cyan,
        onRefresh: _loadFeed,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: _message(
                icon: Icons.explore_outlined,
                title: "You're all caught up",
                body: 'New Public Dailies will show up here as people create them',
              ),
            ),
          ),
        ),
      );
    }

    final shown = eligible.take(_visibleCount).toList();
    final hasMore = shown.length < eligible.length;

    return RefreshIndicator(
      color: Colors.cyan,
      onRefresh: _loadFeed,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: shown.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
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
            onAdded: () => _addedHere.add(daily.id),
          );
        },
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Center(
      child: Column(
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
      ),
    );
  }
}