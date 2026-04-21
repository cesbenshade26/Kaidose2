import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'CamRoll.dart';
import 'SendDailyMessage.dart';
import 'DrawPad.dart';
import 'MessageStorage.dart';
import 'DailySaved.dart';
import 'DailyComments.dart';
import 'DailyLikes.dart';
import 'UseCam.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';

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
  DateTime? _selectedDate;
  bool _showOptionsMenu = false;
  bool _showAttachMenu = false;
  bool _filterOnlyPromptMessages = false;
  XFile? _selectedImage;
  XFile? _selectedVideo;
  VideoPlayerController? _videoController;
  List<DailyMessage> _messages = [];
  late AnimationController _optionsAnimationController;
  late Animation<double> _optionsAnimation;
  Function()? _messageStorageListener;

  bool _isEditingMessage = false;
  String? _editingMessageId;
  XFile? _originalImage;

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

    _loadMessages();

    _messageStorageListener = () {
      if (mounted) _loadMessages();
    };
    MessageStorage.addListener(_messageStorageListener!);
  }

  Future<void> _loadMessages() async {
    final messages = await MessageStorage.loadMessages(widget.daily.id);
    setState(() {
      _messages = messages;
    });

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

  void addPromptMessage(String messageText) {
    if (messageText.trim().isEmpty) return;

    final promptMessage = DailyMessage(
      text: messageText,
      timestamp: DateTime.now(),
      dailyId: widget.daily.id,
      isFromPrompt: true,
    );

    setState(() {
      _messages.add(promptMessage);
    });

    _saveMessages();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void addPromptMessageWithMedia(String messageText, String? imagePath, String? videoPath) {
    final promptMessage = DailyMessage(
      text: messageText.trim().isNotEmpty ? messageText : null,
      imagePath: imagePath,
      videoPath: videoPath,
      timestamp: DateTime.now(),
      dailyId: widget.daily.id,
      isFromPrompt: true,
    );

    setState(() {
      _messages.add(promptMessage);
    });

    _saveMessages();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _optionsAnimationController.dispose();
    _videoController?.dispose();
    if (_messageStorageListener != null) {
      MessageStorage.removeListener(_messageStorageListener!);
    }
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
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

  Future<void> _openCamera() async {
    final XFile? image = await UseCam.openCamera(context);
    if (image != null) {
      setState(() {
        _selectedImage = image;
        _selectedVideo = null;
        _showAttachMenu = false;
      });
      await _videoController?.dispose();
      _videoController = null;
    }
  }

  Future<void> _selectVideo() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? video = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        await _videoController?.dispose();
        _videoController = null;

        final videoFile = File(video.path);
        _videoController = VideoPlayerController.file(videoFile);

        try {
          await _videoController!.initialize();
          if (mounted) {
            _videoController!.setLooping(true);
            _videoController!.play();
          }
        } catch (e) {
          print('Error initializing video: $e');
        }

        setState(() {
          _selectedVideo = video;
          _selectedImage = null;
          _showAttachMenu = false;
        });
      }
    } catch (e) {
      print('Error selecting video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
    final message = _messages.firstWhere(
          (msg) => msg.messageId == messageId,
      orElse: () => _messages.first,
    );

    setState(() {
      _isEditingMessage = true;
      _editingMessageId = messageId;
      _messageController.text = message.text ?? '';

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

    final messageIndex = _messages.indexWhere((msg) => msg.messageId == _editingMessageId);

    if (messageIndex != -1) {
      final oldMessage = _messages[messageIndex];
      final updatedMessage = DailyMessage(
        text: text.isNotEmpty ? text : null,
        imagePath: _selectedImage?.path,
        timestamp: oldMessage.timestamp,
        userId: oldMessage.userId,
        messageId: oldMessage.messageId,
        dailyId: oldMessage.dailyId,
        isSaved: oldMessage.isSaved,
        reactions: oldMessage.reactions,
      );

      setState(() {
        _messages[messageIndex] = updatedMessage;
        _isEditingMessage = false;
        _editingMessageId = null;
        _messageController.clear();
        _selectedImage = null;
        _originalImage = null;
      });

      _saveMessages();

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
    if (_isEditingMessage) {
      await _updateMessage();
      return;
    }

    final text = _messageController.text.trim();

    if (text.isEmpty && _selectedImage == null && _selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a message or attach media'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final message = DailyMessage(
      text: text.isNotEmpty ? text : null,
      imagePath: _selectedImage?.path,
      videoPath: _selectedVideo?.path,
      timestamp: DateTime.now(),
      dailyId: widget.daily.id,
    );

    setState(() {
      _messages.add(message);
      _messageController.clear();
      _selectedImage = null;
      _selectedVideo = null;
    });

    await _videoController?.dispose();
    _videoController = null;

    _saveMessages();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

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
    List<DailyMessage> filtered = _messages;

    if (_selectedDate != null) {
      filtered = filtered.where((message) {
        final messageDate = message.timestamp;
        return messageDate.year == _selectedDate!.year &&
            messageDate.month == _selectedDate!.month &&
            messageDate.day == _selectedDate!.day;
      }).toList();
    }

    if (_filterOnlyPromptMessages) {
      filtered = filtered.where((message) => message.isFromPrompt).toList();
    }

    return filtered;
  }

  Widget _buildOptionsMenu() {
    return Positioned(
      bottom: _selectedImage != null || _selectedVideo != null ? 407 : 195,
      left: 16,
      child: FadeTransition(
        opacity: _optionsAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.5),
            end: Offset.zero,
          ).animate(_optionsAnimation),
          child: Container(
            width: 210,
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
                _buildOptionItem(Icons.add_reaction_outlined, 'Reacted'),
                Divider(height: 1, color: Colors.grey[300]),
                _buildOptionItem(Icons.comment_outlined, 'Comments'),
                Divider(height: 1, color: Colors.grey[300]),
                _buildFilterOptionItem(),
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
        _toggleOptionsMenu();

        if (label == 'Saved') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DailySavedScreen(daily: widget.daily),
            ),
          );
        } else if (label == 'Reacted') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DailyLikesScreen(daily: widget.daily),
            ),
          );
        } else if (label == 'Comments') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DailyCommentsScreen(daily: widget.daily),
            ),
          );
        } else {
          print('$label tapped');
        }
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

  Widget _buildFilterOptionItem() {
    return InkWell(
      onTap: () {
        setState(() {
          _filterOnlyPromptMessages = !_filterOnlyPromptMessages;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.filter_list, size: 20, color: Colors.black87),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Entry Messages Only',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            Checkbox(
              value: _filterOnlyPromptMessages,
              onChanged: (val) {
                setState(() {
                  _filterOnlyPromptMessages = val ?? false;
                });
              },
              activeColor: Colors.cyan,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
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
            _buildAttachMenuItem(Icons.videocam, 'Video', _selectVideo),
            Container(width: 1, height: 40, color: Colors.grey[300]),
            _buildAttachMenuItem(Icons.camera_alt, 'Camera', _openCamera),
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
                  onMessageUpdate: _saveMessages,
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
                      if (_selectedVideo != null)
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
                                child: _videoController != null && _videoController!.value.isInitialized
                                    ? SizedBox(
                                  width: double.infinity,
                                  height: 200,
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: _videoController!.value.size.width,
                                      height: _videoController!.value.size.height,
                                      child: VideoPlayer(_videoController!),
                                    ),
                                  ),
                                )
                                    : Container(
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: CircularProgressIndicator(color: Colors.cyan),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedVideo = null;
                                    });
                                    _videoController?.dispose();
                                    _videoController = null;
                                  },
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
            bottom: _selectedImage != null || _selectedVideo != null ? 347 : 135,
            left: 16,
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

          Positioned(
            bottom: _selectedImage != null || _selectedVideo != null ? 347 : 135,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_selectedDate != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDate = null;
                        });
                        _loadMessages();
                      },
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
                GestureDetector(
                  onTap: () => _selectDate(context),
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
      ),
    );
  }
}

class DailyMessageList extends StatelessWidget {
  final List<DailyMessage> messages;
  final ScrollController scrollController;
  final Function(String)? onEdit;
  final VoidCallback? onMessageUpdate;

  const DailyMessageList({
    Key? key,
    required this.messages,
    required this.scrollController,
    this.onEdit,
    this.onMessageUpdate,
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
              'Send a message to get started!',
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
        final message = messages[index];
        return DailyMessageWidget(
          message: message,
          isCurrentUser: message.isFromCurrentUser(),
          onEdit: onEdit,
          onSaveToggle: onMessageUpdate,
          onReactionAdded: (emoji) {
            if (onMessageUpdate != null) {
              onMessageUpdate!();
            }
          },
        );
      },
    );
  }
}