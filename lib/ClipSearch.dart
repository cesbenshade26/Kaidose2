import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'clip_service.dart';
import 'Clips.dart';
import 'FeedService.dart';
import 'SearchService.dart';

/// Clips in Search. Clips have no names to look up, so this screen always
/// shows clips:
///  - nothing typed: clips picked from the user's feed (topics they like,
///    creators they watch, friends). A brand-new user with no feed history
///    yet just sees the latest clips.
///  - typed: clips whose caption or generated keywords match, blended with
///    how well each fits the user's feed.
///
/// [embedded] renders a single horizontal strip (for the All tab).
/// Tapping a clip opens a vertical viewer of the whole list, starting there.
class ClipSearchWidget extends StatefulWidget {
  final String searchQuery;
  final bool embedded;

  /// Tapping a topic chip (full view only) — Search puts it in the box.
  final void Function(String topic)? onTopicTap;

  const ClipSearchWidget({
    Key? key,
    required this.searchQuery,
    this.embedded = false,
    this.onTopicTap,
  }) : super(key: key);

  @override
  State<ClipSearchWidget> createState() => _ClipSearchWidgetState();
}

class _ClipSearchWidgetState extends State<ClipSearchWidget> {
  List<ClipData> _clips = [];
  List<String> _topics = [];
  bool _hasTaste = false;
  bool _isLoading = true;
  int _requestId = 0;

  bool get _typed => widget.searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    if (!widget.embedded) _loadTopics();
  }

  @override
  void didUpdateWidget(ClipSearchWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) _load();
  }

  Future<void> _loadTopics() async {
    try {
      final results = await Future.wait([
        FeedService.getTopTopics(limit: 8),
        SearchService.hasFeedTaste(),
      ]);
      if (!mounted) return;
      setState(() {
        _topics = results[0] as List<String>;
        _hasTaste = results[1] as bool;
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    final id = ++_requestId;
    try {
      final clips = _typed
          ? await SearchService.searchClips(widget.searchQuery)
          : await SearchService.suggestedClips(limit: widget.embedded ? 8 : 18);
      if (!mounted || id != _requestId) return;
      setState(() {
        _clips = clips;
        _isLoading = false;
      });
    } catch (e) {
      print('ClipSearchWidget: load error: $e');
      if (mounted && id == _requestId) setState(() => _isLoading = false);
    }
  }

  void _open(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClipsWidget(pinnedClips: _clips, startIndex: index),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _clips.isEmpty) {
      return widget.embedded
          ? const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: CircularProgressIndicator(
                color: Colors.cyan, strokeWidth: 2)),
      )
          : const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }

    if (widget.embedded) return _buildStrip();

    if (_clips.isEmpty) {
      return _typed
          ? _message(Icons.search_off, 'No clips match',
          'Clips are found by their caption and topic — try different words')
          : _message(Icons.play_circle_outline, 'No clips yet',
          'Clips from other people will show up here');
    }

    final title = _typed
        ? 'Clips for "${widget.searchQuery.trim()}"'
        : (_hasTaste ? 'Picked for you' : 'Latest clips');

    return CustomScrollView(
      slivers: [
        if (!_typed && _topics.isNotEmpty)
          SliverToBoxAdapter(child: _topicChips()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800])),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 9 / 14,
            ),
            delegate: SliverChildBuilderDelegate(
                  (context, i) => _tile(_clips[i], i),
              childCount: _clips.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStrip() {
    if (_clips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(_typed ? 'No clips match' : 'No clips to show yet',
            style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      );
    }
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _clips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => SizedBox(
          width: 112,
          child: _tile(_clips[i], i),
        ),
      ),
    );
  }

  Widget _topicChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in _topics)
            ActionChip(
              label: Text(t),
              labelStyle: const TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.w500),
              backgroundColor: Colors.cyan.withOpacity(0.1),
              side: BorderSide.none,
              onPressed: widget.onTopicTap == null
                  ? null
                  : () => widget.onTopicTap!(t),
            ),
        ],
      ),
    );
  }

  Widget _tile(ClipData clip, int index) {
    final thumb = clip.thumbnailUrl ?? (clip.isPhoto ? clip.photoUrl : null);
    return GestureDetector(
      onTap: () => _open(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.grey[900]),
            if (thumb != null && thumb.isNotEmpty)
              CachedNetworkImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            // Bottom fade so the caption stays readable on any thumbnail.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  ),
                ),
                child: Text(
                  clip.caption.isNotEmpty
                      ? clip.caption
                      : '@${clip.creatorUsername}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
            if (!clip.isPhoto)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  Widget _message(IconData icon, String title, String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}