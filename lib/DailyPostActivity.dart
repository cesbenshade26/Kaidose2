import 'package:flutter/material.dart';
import 'dart:io';
import 'DailyList.dart';
import 'DailyData.dart';
import 'MessageStorage.dart';
import 'SendDailyMessage.dart';

// A message paired with its daily title for display
class _PostItem {
  final DailyMessage message;
  final String dailyTitle;

  _PostItem({required this.message, required this.dailyTitle});
}

class DailyPostActivity extends StatefulWidget {
  const DailyPostActivity({Key? key}) : super(key: key);

  @override
  State<DailyPostActivity> createState() => _DailyPostActivityState();
}

class _DailyPostActivityState extends State<DailyPostActivity> {
  List<_PostItem> _posts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  VoidCallback? _messageListener;

  @override
  void initState() {
    super.initState();
    _loadPublicPosts();

    _messageListener = () {
      if (mounted && !_isRefreshing) _loadPublicPosts();
    };
    MessageStorage.addListener(_messageListener!);
  }

  @override
  void dispose() {
    if (_messageListener != null) MessageStorage.removeListener(_messageListener!);
    super.dispose();
  }

  Future<void> _loadPublicPosts() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    final publicDailies = DailyList.dailies
        .where((d) => d.privacy.toLowerCase() == 'public')
        .toList();

    List<_PostItem> allPosts = [];

    for (final daily in publicDailies) {
      final messages = await MessageStorage.loadMessages(daily.id);
      for (final msg in messages) {
        if (msg.hasContent) {
          allPosts.add(_PostItem(message: msg, dailyTitle: daily.title));
        }
      }
    }

    allPosts.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));

    if (mounted) {
      setState(() {
        _posts = allPosts;
        _isLoading = false;
      });
    }

    _isRefreshing = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyan),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.public, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Public Posts Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Posts from public dailies will appear here',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 0,
        mainAxisSpacing: 0,
        childAspectRatio: 1,
      ),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DailyPostViewer(
                  posts: _posts,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: _buildGridThumbnail(post),
        );
      },
    );
  }

  Widget _buildGridThumbnail(_PostItem post) {
    final msg = post.message;

    // Image post
    if (msg.imagePath != null) {
      final file = File(msg.imagePath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _textThumbnail(msg.text),
        );
      }
    }

    // Text-only post
    return _textThumbnail(msg.text);
  }

  Widget _textThumbnail(String? text) {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(8),
      child: Center(
        child: Text(
          text ?? '',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[800],
          ),
        ),
      ),
    );
  }
}

// Full scroll viewer for posts
class DailyPostViewer extends StatelessWidget {
  final List<_PostItem> posts;
  final int initialIndex;

  const DailyPostViewer({
    Key? key,
    required this.posts,
    required this.initialIndex,
  }) : super(key: key);

  String _formatDate(DateTime dt) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final dayName = days[dt.weekday - 1];
    return '$dayName, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final ScrollController scrollController = ScrollController(
      initialScrollOffset: initialIndex * 420.0,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Daily Posts',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          final msg = post.message;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.public, color: Colors.cyan, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.dailyTitle,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            _formatDate(msg.timestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Image
              if (msg.imagePath != null && File(msg.imagePath!).existsSync())
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(msg.imagePath!),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                ),

              // Text
              if (msg.text != null && msg.text!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text(
                    msg.text!,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                ),

              // Divider
              if (index < posts.length - 1)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Divider(color: Colors.grey[200], height: 1),
                ),
            ],
          );
        },
      ),
    );
  }
}