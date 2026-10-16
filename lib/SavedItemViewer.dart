import 'package:flutter/material.dart';
import 'dart:io';
import 'SendDailyMessage.dart';
import 'VideoClipPlayer.dart';
import 'NetworkVideoPlayer.dart';

bool _isNetworkPath(String path) =>
    path.startsWith('http://') || path.startsWith('https://');

class SavedItemViewer extends StatefulWidget {
  final List<DailyMessage> items;
  final int initialIndex;

  const SavedItemViewer({
    Key? key,
    required this.items,
    required this.initialIndex,
  }) : super(key: key);

  @override
  State<SavedItemViewer> createState() => _SavedItemViewerState();
}

class _SavedItemViewerState extends State<SavedItemViewer> {
  final ScrollController _scrollController = ScrollController();
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    // Scroll to initial item after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialIndex > 0) {
        // Estimate height per item and scroll to position
        final estimatedHeight = MediaQuery.of(context).size.height * 0.85;
        _scrollController.jumpTo(widget.initialIndex * estimatedHeight);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildVideo(String videoPath) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: _isNetworkPath(videoPath)
          ? NetworkVideoPlayer(url: videoPath)
          : VideoClipPlayer(
        videoFile: File(videoPath),
        autoPlay: true,
        looping: true,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildImage(String imagePath) {
    if (_isNetworkPath(imagePath)) {
      return Image.network(
        imagePath,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: 300,
            color: Colors.grey[100],
            child: const Center(
              child: CircularProgressIndicator(color: Colors.cyan),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: 300,
            color: Colors.grey[200],
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, color: Colors.grey[400], size: 80),
                const SizedBox(height: 16),
                Text(
                  'Image not available',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        },
      );
    }

    return Image.file(
      File(imagePath),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 300,
          color: Colors.grey[200],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image, color: Colors.grey[400], size: 80),
              const SizedBox(height: 16),
              Text(
                'Image not available',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageView(DailyMessage message, int index) {
    final hasImage = message.imagePath != null && message.imagePath!.isNotEmpty;
    final hasVideo = message.videoPath != null && message.videoPath!.isNotEmpty;
    final hasText = message.text != null && message.text!.isNotEmpty;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 20),
      child: SafeArea(
        child: Column(
          children: [
            // Header with close button and counter
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black, size: 28),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                  Text(
                    '${index + 1} / ${widget.items.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 48), // Balance for close button
                ],
              ),
            ),

            // Content area
            Column(
              children: [
                // Image (if exists)
                if (hasImage) ...[
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    child: _buildImage(message.imagePath!),
                  ),
                  const SizedBox(height: 24),
                ],

                // Video (if exists)
                if (hasVideo) ...[
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildVideo(message.videoPath!),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Text (if exists)
                if (hasText) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.cyan,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        message.text!,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.7,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Timestamp
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTimestamp(message.timestamp),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        controller: _scrollController,
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final message = widget.items[index];
          return _buildMessageView(message, index);
        },
      ),
    );
  }
}