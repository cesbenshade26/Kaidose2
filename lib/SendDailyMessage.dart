import 'package:flutter/material.dart';
import 'dart:io';

class DailyMessage {
  final String? text;
  final String? imagePath;
  final DateTime timestamp;
  final String userId; // For future API integration
  final String messageId; // For future API integration
  bool isLiked;
  bool isSaved;

  DailyMessage({
    this.text,
    this.imagePath,
    required this.timestamp,
    String? userId,
    String? messageId,
    this.isLiked = false,
    this.isSaved = false,
  })  : userId = userId ?? 'current_user', // Placeholder for current user
        messageId = messageId ?? DateTime.now().millisecondsSinceEpoch.toString();

  // For future API integration - convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'message_id': messageId,
      'user_id': userId,
      'text': text,
      'image_path': imagePath,
      'timestamp': timestamp.toIso8601String(),
      'is_liked': isLiked,
      'is_saved': isSaved,
    };
  }

  // For future API integration - create from JSON
  factory DailyMessage.fromJson(Map<String, dynamic> json) {
    return DailyMessage(
      text: json['text'],
      imagePath: json['image_path'],
      timestamp: DateTime.parse(json['timestamp']),
      userId: json['user_id'],
      messageId: json['message_id'],
      isLiked: json['is_liked'] ?? false,
      isSaved: json['is_saved'] ?? false,
    );
  }

  bool get hasContent => (text != null && text!.trim().isNotEmpty) || imagePath != null;

  // Check if this message belongs to the current user
  bool isFromCurrentUser() {
    // TODO: Replace with actual current user ID from auth system
    return userId == 'current_user';
  }
}

class DailyMessageWidget extends StatefulWidget {
  final DailyMessage message;
  final bool isCurrentUser;
  final VoidCallback? onReply;
  final Function(String)? onEdit; // Callback for editing message

  const DailyMessageWidget({
    Key? key,
    required this.message,
    this.isCurrentUser = true, // Default to current user for now
    this.onReply,
    this.onEdit,
  }) : super(key: key);

  @override
  State<DailyMessageWidget> createState() => _DailyMessageWidgetState();
}

class _DailyMessageWidgetState extends State<DailyMessageWidget> {
  bool _showOptionsMenu = false;

  void _toggleLike() {
    setState(() {
      widget.message.isLiked = !widget.message.isLiked;
    });
    // TODO: Send like status to API
    print('Message ${widget.message.messageId} liked: ${widget.message.isLiked}');
  }

  void _toggleSave() {
    setState(() {
      widget.message.isSaved = !widget.message.isSaved;
    });
    // TODO: Send save status to API
    print('Message ${widget.message.messageId} saved: ${widget.message.isSaved}');
  }

  void _handleReply() {
    if (widget.onReply != null) {
      widget.onReply!();
    }
    // TODO: Implement reply functionality
    print('Reply to message ${widget.message.messageId}');
  }

  void _toggleOptionsMenu() {
    setState(() {
      _showOptionsMenu = !_showOptionsMenu;
    });
  }

  void _handleEdit() {
    setState(() {
      _showOptionsMenu = false;
    });
    if (widget.onEdit != null) {
      widget.onEdit!(widget.message.messageId);
    }
    // TODO: Implement edit functionality
    print('Edit message ${widget.message.messageId}');
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
      // Format as date
      return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Message container with card-like design
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.cyan.withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyan.withOpacity(0.1),
                      blurRadius: 8,
                      spreadRadius: 1,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image if present
                    if (widget.message.imagePath != null)
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(14),
                          topRight: Radius.circular(14),
                        ),
                        child: Image.file(
                          File(widget.message.imagePath!),
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 200,
                              color: Colors.grey[200],
                              child: Center(
                                child: Icon(
                                  Icons.error_outline,
                                  color: Colors.grey[400],
                                  size: 48,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // Text if present
                    if (widget.message.text != null && widget.message.text!.trim().isNotEmpty)
                      Padding(
                        padding: EdgeInsets.all(widget.message.imagePath != null ? 16 : 16),
                        child: Text(
                          widget.message.text!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),

                    // Timestamp and action buttons bar at bottom
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.05),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(14),
                          bottomRight: Radius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Timestamp
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 13,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatTimestamp(widget.message.timestamp),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          // Action buttons
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Like button
                              GestureDetector(
                                onTap: _toggleLike,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    widget.message.isLiked ? Icons.favorite : Icons.favorite_border,
                                    size: 20,
                                    color: widget.message.isLiked ? Colors.red : Colors.grey[600],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Reply button
                              GestureDetector(
                                onTap: _handleReply,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.reply,
                                    size: 20,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Save button
                              GestureDetector(
                                onTap: _toggleSave,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    widget.message.isSaved ? Icons.bookmark : Icons.bookmark_border,
                                    size: 20,
                                    color: widget.message.isSaved ? Colors.cyan : Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Three dots menu button (top right)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: _toggleOptionsMenu,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ),
              // Options menu dropdown
              if (_showOptionsMenu)
                Positioned(
                  top: 40,
                  right: 8,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Edit option (only for current user's messages)
                          if (widget.isCurrentUser)
                            InkWell(
                              onTap: _handleEdit,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.edit,
                                      size: 18,
                                      color: Colors.grey[700],
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Edit',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[800],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // More options will go here in the future
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Message list widget for displaying all messages
class DailyMessageList extends StatelessWidget {
  final List<DailyMessage> messages;
  final ScrollController? scrollController;
  final Function(String)? onEdit;

  const DailyMessageList({
    Key? key,
    required this.messages,
    this.scrollController,
    this.onEdit,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to share something!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        return DailyMessageWidget(
          message: messages[index],
          isCurrentUser: messages[index].isFromCurrentUser(),
          onEdit: onEdit,
        );
      },
    );
  }
}

// API Service class for future implementation
class DailyMessageService {
  // Placeholder for future API endpoint
  static const String apiEndpoint = 'YOUR_API_ENDPOINT_HERE';

  // TODO: Implement when API is ready
  static Future<bool> sendMessage(DailyMessage message, String dailyId) async {
    try {
      // Placeholder for API call
      // final response = await http.post(
      //   Uri.parse('$apiEndpoint/dailies/$dailyId/messages'),
      //   headers: {'Content-Type': 'application/json'},
      //   body: json.encode(message.toJson()),
      // );
      // return response.statusCode == 200;

      print('Sending message to API: ${message.toJson()}');
      print('Daily ID: $dailyId');
      return true; // Simulated success
    } catch (e) {
      print('Error sending message: $e');
      return false;
    }
  }

  // TODO: Implement when API is ready
  static Future<bool> updateMessage(DailyMessage message, String dailyId) async {
    try {
      // Placeholder for API call
      // final response = await http.put(
      //   Uri.parse('$apiEndpoint/dailies/$dailyId/messages/${message.messageId}'),
      //   headers: {'Content-Type': 'application/json'},
      //   body: json.encode(message.toJson()),
      // );
      // return response.statusCode == 200;

      print('Updating message in API: ${message.toJson()}');
      print('Daily ID: $dailyId');
      return true; // Simulated success
    } catch (e) {
      print('Error updating message: $e');
      return false;
    }
  }

  // TODO: Implement when API is ready
  static Future<List<DailyMessage>> fetchMessages(String dailyId) async {
    try {
      // Placeholder for API call
      // final response = await http.get(
      //   Uri.parse('$apiEndpoint/dailies/$dailyId/messages'),
      // );
      // if (response.statusCode == 200) {
      //   final List<dynamic> data = json.decode(response.body);
      //   return data.map((json) => DailyMessage.fromJson(json)).toList();
      // }

      print('Fetching messages from API for daily: $dailyId');
      return []; // Simulated empty response
    } catch (e) {
      print('Error fetching messages: $e');
      return [];
    }
  }

  // TODO: Implement image upload when API is ready
  static Future<String?> uploadImage(String imagePath, String dailyId) async {
    try {
      // Placeholder for image upload
      // This should upload the image and return the URL/path from server
      // final request = http.MultipartRequest(
      //   'POST',
      //   Uri.parse('$apiEndpoint/dailies/$dailyId/upload-image'),
      // );
      // request.files.add(await http.MultipartFile.fromPath('image', imagePath));
      // final response = await request.send();

      print('Uploading image: $imagePath for daily: $dailyId');
      return imagePath; // For now, return local path
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }
}