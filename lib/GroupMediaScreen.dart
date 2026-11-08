import 'package:flutter/material.dart';
import 'ChatTarget.dart';
import 'NetworkVideoPlayer.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December'
];

/// Every photo sent in the group, newest first, grouped by month.
class GroupMediaScreen extends StatelessWidget {
  final ChatTarget target;

  const GroupMediaScreen({Key? key, required this.target}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Media',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<ChatMediaEntry>>(
        stream: target.watchMedia(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.cyan));
          }
          final media = snapshot.data!;

          if (media.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 72, color: Colors.grey[400]),
                  const SizedBox(height: 14),
                  Text('No media yet',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                  const SizedBox(height: 6),
                  Text('Photos and videos sent in this chat show up here',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            );
          }

          final items = media
              .map((m) => GroupMediaItem(
            url: m.url,
            previewUrl: m.previewUrl,
            isVideo: m.isVideo,
          ))
              .toList();

          // Group by month, keeping the newest-first order.
          final slivers = <Widget>[];
          int i = 0;
          while (i < media.length) {
            final t = media[i].time;
            int j = i;
            while (j < media.length &&
                media[j].time.year == t.year &&
                media[j].time.month == t.month) {
              j++;
            }
            final start = i;
            final end = j;
            slivers.add(SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '${_months[t.month - 1]} ${t.year}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ));
            slivers.add(SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                delegate: SliverChildBuilderDelegate(
                      (context, k) {
                    final index = start + k;
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        PageRouteBuilder(
                          opaque: false,
                          pageBuilder: (_, __, ___) => GroupImageViewer(
                              items: items, initialIndex: index),
                          transitionsBuilder: (_, a, __, child) =>
                              FadeTransition(opacity: a, child: child),
                        ),
                      ),
                      child: Hero(
                        tag: 'group_media_${items[index].url}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (items[index].previewUrl != null)
                                Image.network(
                                  items[index].previewUrl!,
                                  fit: BoxFit.cover,
                                  frameBuilder: (c, child, frame, sync) =>
                                  frame == null && !sync
                                      ? Container(color: Colors.grey[200])
                                      : child,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey[200],
                                    child: Icon(Icons.broken_image_outlined,
                                        color: Colors.grey[400]),
                                  ),
                                )
                              else
                                Container(color: Colors.grey[800]),
                              if (items[index].isVideo)
                                const Center(
                                  child: Icon(Icons.play_circle_fill,
                                      color: Colors.white, size: 34),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: end - start,
                ),
              ),
            ));
            i = j;
          }
          slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 32)));

          return CustomScrollView(slivers: slivers);
        },
      ),
    );
  }
}

class GroupMediaItem {
  final String url;
  final String? previewUrl;
  final bool isVideo;

  GroupMediaItem({required this.url, this.previewUrl, required this.isVideo});
}

/// Full-screen swipeable viewer for photos and videos. Pinch to zoom photos,
/// tap a photo to close.
class GroupImageViewer extends StatefulWidget {
  final List<GroupMediaItem> items;
  final int initialIndex;

  const GroupImageViewer(
      {Key? key, required this.items, required this.initialIndex})
      : super(key: key);

  @override
  State<GroupImageViewer> createState() => _GroupImageViewerState();
}

class _GroupImageViewerState extends State<GroupImageViewer> {
  late final PageController _controller =
  PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.95),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final item = widget.items[i];
              if (item.isVideo) {
                return Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: NetworkVideoPlayer(url: item.url),
                  ),
                );
              }
              return GestureDetector(
                onTap: () => Navigator.pop(context),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Hero(
                      tag: 'group_media_${item.url}',
                      child: Image.network(
                        item.url,
                        fit: BoxFit.contain,
                        loadingBuilder: (c, child, p) => p == null
                            ? child
                            : const Center(
                            child: CircularProgressIndicator(
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (widget.items.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text('${_index + 1} / ${widget.items.length}',
                          style: const TextStyle(color: Colors.white70)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}