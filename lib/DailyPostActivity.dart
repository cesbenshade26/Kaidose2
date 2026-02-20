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
  DateTime? _selectedDate; // null = show all

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

  Future<void> _selectDate() async {
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
              surface: Colors.white,
              onSurface: Colors.black,
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

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
    });
  }

  List<_PostItem> _getFilteredPosts() {
    if (_selectedDate == null) return _posts;

    final dateStr = _selectedDate!.toIso8601String().split('T')[0];
    return _posts.where((post) {
      final postDateStr = post.message.timestamp.toIso8601String().split('T')[0];
      return postDateStr == dateStr;
    }).toList();
  }

  Future<void> _loadPublicPosts() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    final publicDailies = DailyList.dailies
        .where((daily) => daily.privacy == 'Public')
        .toList();

    List<_PostItem> allPosts = [];

    for (final daily in publicDailies) {
      final messages = await MessageStorage.loadMessages(daily.id);

      for (final message in messages) {
        allPosts.add(_PostItem(
          message: message,
          dailyTitle: daily.title,
        ));
      }
    }

    // Sort by newest first
    allPosts.sort((a, b) =>
        b.message.timestamp.compareTo(a.message.timestamp));

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

    final filteredPosts = _getFilteredPosts();

    return Stack(
      children: [
        GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
            childAspectRatio: 1,
          ),
          itemCount: filteredPosts.length,
          itemBuilder: (context, index) {
            final post = filteredPosts[index];
            final message = post.message;

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DailyPostViewer(
                      posts: filteredPosts,
                      initialIndex: index,
                    ),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                ),
                child: message.imagePath != null
                    ? Image.file(
                  File(message.imagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: Icon(Icons.error, color: Colors.grey[600]),
                    );
                  },
                )
                    : Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.grey[100],
                  child: Center(
                    child: Text(
                      message.text ?? '',
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),

        // Floating date filter button
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Clear filter button (if date selected)
              if (_selectedDate != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: _clearDateFilter,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.clear,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              // Date picker button
              GestureDetector(
                onTap: _selectDate,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.95),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        controller: ScrollController(
          initialScrollOffset: initialIndex * MediaQuery.of(context).size.height,
        ),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          return _buildPostItem(context, post);
        },
      ),
    );
  }

  Widget _buildPostItem(BuildContext context, _PostItem post) {
    final message = post.message;

    return Container(
      height: MediaQuery.of(context).size.height -
          AppBar().preferredSize.height -
          MediaQuery.of(context).padding.top,
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image if present
          if (message.imagePath != null)
            Expanded(
              child: Center(
                child: Image.file(
                  File(message.imagePath!),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[900],
                      child: const Center(
                        child: Icon(
                          Icons.error_outline,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Text and info section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Daily name
                Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: Colors.cyan),
                    const SizedBox(width: 8),
                    Text(
                      post.dailyTitle,
                      style: const TextStyle(
                        color: Colors.cyan,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                if (message.text != null && message.text!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    message.text!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Timestamp
                Text(
                  _formatTimestamp(message.timestamp),
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[timestamp.month - 1]} ${timestamp.day}';
  }
}