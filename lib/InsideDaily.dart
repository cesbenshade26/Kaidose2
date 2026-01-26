import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'CamRoll.dart';
import 'SendDailyMessage.dart';
import 'DrawPad.dart';
import 'MessageStorage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class InsideDaily extends StatefulWidget {
  final DailyData daily;

  const InsideDaily({
    Key? key,
    required this.daily,
  }) : super(key: key);

  @override
  State<InsideDaily> createState() => InsideDailyState();
}

class InsideDailyState extends State<InsideDaily> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  DateTime? _selectedDate; // null means "any time"
  bool _showOptionsMenu = false;
  bool _showAttachMenu = false;
  XFile? _selectedImage;
  List<DailyMessage> _messages = [];
  late AnimationController _optionsAnimationController;
  late Animation<double> _optionsAnimation;

  // Edit mode variables
  bool _isEditingMessage = false;
  String? _editingMessageId;
  XFile? _originalImage; // Store original image during edit

  @override
  void initState() {
    super.initState();
    _optionsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _optionsAnimation = CurvedAnimation(
      parent: _optionsAnimationController,
      curve: Curves.easeOutCubic,
    );

    // Load saved messages
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final messages = await MessageStorage.loadMessages(widget.daily.id);
    setState(() {
      _messages = messages;
    });

    // Scroll to bottom if there are messages
    if (messages.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _saveMessages() async {
    await MessageStorage.saveMessages(widget.daily.id, _messages);
  }

  // Method to add prompt message from daily entry overlay
  void addPromptMessage(String messageText) {
    if (messageText.trim().isEmpty) return;

    final promptMessage = DailyMessage(
      text: messageText,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(promptMessage);
    });

    // Save messages
    _saveMessages();

    // Scroll to bottom after adding message
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    print('Prompt message added: $messageText');
  }

  @override
  void dispose() {
    _messageController.dispose();
    _optionsAnimationController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    // Show custom dialog with "Any time" option first
    final result = await showDialog<dynamic>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Date'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.all_inclusive, color: Colors.cyan),
                title: const Text('Any time'),
                subtitle: const Text('Show all messages'),
                onTap: () => Navigator.pop(context, 'any_time'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.calendar_today, color: Colors.cyan),
                title: const Text('Pick a specific date'),
                onTap: () => Navigator.pop(context, 'pick_date'),
              ),
            ],
          ),
        );
      },
    );

    if (result == 'any_time') {
      setState(() {
        _selectedDate = null;
      });
    } else if (result == 'pick_date') {
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
                onSurface: Colors.black,
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.cyan,
                ),
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
  }

  void _toggleOptionsMenu() {
    setState(() {
      _showOptionsMenu = !_showOptionsMenu;
      if (_showOptionsMenu) {
        _optionsAnimationController.forward();
      } else {
        _optionsAnimationController.reverse();
      }
    });
  }

  void _toggleAttachMenu() {
    setState(() {
      _showAttachMenu = !_showAttachMenu;
    });
  }

  Future<void> _openCameraRoll() async {
    final XFile? image = await CamRoll.openCameraRoll(context);
    if (image != null) {
      setState(() {
        _selectedImage = image;
        _showAttachMenu = false;
      });
    }
  }

  Future<void> _openDrawPad() async {
    final File? drawingFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          onDrawingComplete: (file) {
            Navigator.pop(context, file);
          },
        ),
      ),
    );

    if (drawingFile != null) {
      // Convert File to XFile
      final XFile drawing = XFile(drawingFile.path);
      setState(() {
        _selectedImage = drawing;
        _showAttachMenu = false;
      });
      print('Drawing attached: ${drawingFile.path}');
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  void _startEditingMessage(String messageId) {
    // Find the message to edit
    final message = _messages.firstWhere(
          (msg) => msg.messageId == messageId,
      orElse: () => _messages.first,
    );

    setState(() {
      _isEditingMessage = true;
      _editingMessageId = messageId;
      _messageController.text = message.text ?? '';

      // Load image if present
      if (message.imagePath != null) {
        _selectedImage = XFile(message.imagePath!);
        _originalImage = _selectedImage;
      } else {
        _selectedImage = null;
        _originalImage = null;
      }
    });

    print('Editing message: $messageId');
  }

  void _cancelEditingMessage() {
    setState(() {
      _isEditingMessage = false;
      _editingMessageId = null;
      _messageController.clear();
      _selectedImage = null;
      _originalImage = null;
    });
  }

  Future<void> _updateMessage() async {
    if (_editingMessageId == null) return;

    final text = _messageController.text.trim();

    // Don't allow completely empty messages
    if (text.isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message cannot be empty'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Find and update the message
    final messageIndex = _messages.indexWhere((msg) => msg.messageId == _editingMessageId);

    if (messageIndex != -1) {
      final oldMessage = _messages[messageIndex];
      final updatedMessage = DailyMessage(
        text: text.isNotEmpty ? text : null,
        imagePath: _selectedImage?.path,
        timestamp: oldMessage.timestamp, // Keep original timestamp
        userId: oldMessage.userId,
        messageId: oldMessage.messageId,
        isLiked: oldMessage.isLiked,
        isSaved: oldMessage.isSaved,
      );

      setState(() {
        _messages[messageIndex] = updatedMessage;
        _isEditingMessage = false;
        _editingMessageId = null;
        _messageController.clear();
        _selectedImage = null;
        _originalImage = null;
      });

      // Save messages
      _saveMessages();

      // TODO: Send update to API
      // await DailyMessageService.updateMessage(updatedMessage, widget.daily.id);

      print('Message updated: ${updatedMessage.toJson()}');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message updated'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _sendMessage() async {
    // If in edit mode, update instead of send
    if (_isEditingMessage) {
      await _updateMessage();
      return;
    }

    final text = _messageController.text.trim();

    // Don't allow empty messages (no text and no image)
    if (text.isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a message or attach an image'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Create message
    final message = DailyMessage(
      text: text.isNotEmpty ? text : null,
      imagePath: _selectedImage?.path,
      timestamp: DateTime.now(),
    );

    // Add message to local list
    setState(() {
      _messages.add(message);
      _messageController.clear();
      _selectedImage = null;
    });

    // Save messages
    _saveMessages();

    // Scroll to bottom after adding message
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // TODO: Send to API when ready
    // final success = await DailyMessageService.sendMessage(message, widget.daily.id);
    // if (!success) {
    //   // Handle error - maybe show retry option
    // }

    print('Message sent: ${message.toJson()}');
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Any time';
    }

    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today';
    }

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  List<DailyMessage> _getFilteredMessages() {
    if (_selectedDate == null) {
      // Show all messages
      return _messages;
    }

    // Filter messages by selected date
    return _messages.where((message) {
      final messageDate = message.timestamp;
      return messageDate.year == _selectedDate!.year &&
          messageDate.month == _selectedDate!.month &&
          messageDate.day == _selectedDate!.day;
    }).toList();
  }

  Widget _buildOptionsMenu() {
    return Positioned(
      bottom: _selectedImage != null ? 377 : 165, // 165 + 212 (image height + margins)
      right: 16,
      child: FadeTransition(
        opacity: _optionsAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.5),
            end: Offset.zero,
          ).animate(_optionsAnimation),
          child: Container(
            width: 160,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 10,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildOptionItem(Icons.bookmark_outline, 'Saved'),
                Divider(height: 1, color: Colors.grey[300]),
                _buildOptionItem(Icons.favorite_outline, 'Liked'),
                Divider(height: 1, color: Colors.grey[300]),
                _buildOptionItem(Icons.comment_outlined, 'Comments'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionItem(IconData icon, String label) {
    return InkWell(
      onTap: () {
        // TODO: Implement functionality
        print('$label tapped');
        _toggleOptionsMenu();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachMenu() {
    return Positioned(
      bottom: 80,
      left: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAttachMenuItem(Icons.photo_library, 'Camera Roll', _openCameraRoll),
            Container(width: 1, height: 40, color: Colors.grey[300]),
            _buildAttachMenuItem(Icons.camera_alt, 'Camera', null),
            Container(width: 1, height: 40, color: Colors.grey[300]),
            _buildAttachMenuItem(Icons.edit, 'Draw', _openDrawPad),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachMenuItem(IconData icon, String label, VoidCallback? onTapCallback) {
    return InkWell(
      onTap: () {
        print('$label tapped');
        _toggleAttachMenu();
        if (onTapCallback != null) {
          onTapCallback();
        }
        // TODO: Implement functionality for other buttons
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Icon(icon, size: 24, color: Colors.black87),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Text(
          widget.daily.title,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: () => _selectDate(context),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[300]!, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDate(_selectedDate),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: Colors.grey[700],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: DailyMessageList(
                  messages: _getFilteredMessages(),
                  scrollController: _scrollController,
                  onEdit: _startEditingMessage,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedImage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!, width: 2),
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(_selectedImage!.path),
                                  width: double.infinity,
                                  height: 200,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: _removeImage,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Edit mode banner
                      if (_isEditingMessage)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            border: Border(
                              bottom: BorderSide(color: Colors.blue.withOpacity(0.3), width: 1),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.edit, color: Colors.blue, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Editing message',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _cancelEditingMessage,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.blue, width: 1),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(
                                Icons.attach_file,
                                color: Colors.grey[700],
                                size: 22,
                              ),
                              onPressed: _toggleAttachMenu,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: TextField(
                                controller: _messageController,
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 16,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                maxLines: null,
                                textCapitalization: TextCapitalization.sentences,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            decoration: const BoxDecoration(
                              color: Colors.cyan,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.send,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: _sendMessage,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_showOptionsMenu) _buildOptionsMenu(),
          if (_showAttachMenu) _buildAttachMenu(),
          Positioned(
            bottom: _selectedImage != null ? 327 : 115, // 115 + 212 (image height + margins)
            right: 16,
            child: GestureDetector(
              onTap: _toggleOptionsMenu,
              child: AnimatedRotation(
                turns: _showOptionsMenu ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.cyan,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyan.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_up,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}