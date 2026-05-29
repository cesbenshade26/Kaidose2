import 'package:flutter/material.dart';
import 'message_service.dart';

class ManageChatScreen extends StatefulWidget {
  final String friendUserId;
  final String friendUsername;

  const ManageChatScreen({
    Key? key,
    required this.friendUserId,
    required this.friendUsername,
  }) : super(key: key);

  @override
  State<ManageChatScreen> createState() => _ManageChatScreenState();
}

class _ManageChatScreenState extends State<ManageChatScreen> {
  final MessageService _messageService = MessageService();
  String _selectedDeleteOption = 'off';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final option = await _messageService.getChatSettings(widget.friendUserId);
    if (mounted) {
      setState(() {
        _selectedDeleteOption = option;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings(String option) async {
    await _messageService.saveChatSettings(
      recipientUserId: widget.friendUserId,
      deleteOption: option,
    );

    setState(() {
      _selectedDeleteOption = option;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            option == 'off'
                ? 'Disappearing messages turned off'
                : 'Messages will delete after ${_getOptionLabel(option)}',
          ),
          backgroundColor: Colors.cyan,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _getOptionLabel(String option) {
    switch (option) {
      case '24h':
        return '24 hours';
      case '7d':
        return '7 days';
      case 'on_close':
        return 'closing chat';
      default:
        return 'never';
    }
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
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Manage Chat',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chat info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyan.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            top: 12,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.cyan[700],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -6,
                            child: Container(
                              width: 44,
                              height: 26,
                              decoration: BoxDecoration(
                                color: Colors.cyan[700],
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(22),
                                  topRight: Radius.circular(22),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.friendUsername,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Chat settings',
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
            ),
            const SizedBox(height: 32),

            // Disappearing Messages Section
            Row(
              children: [
                Icon(Icons.timer_outlined, color: Colors.grey[700], size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Disappearing Messages',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Control how long messages stay in this chat',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 20),

            // Options
            _buildOption(
              'off',
              'Off',
              'Messages saved forever',
              Icons.all_inclusive,
            ),
            const SizedBox(height: 12),
            _buildOption(
              '24h',
              '24 Hours',
              'Delete 24h after viewing',
              Icons.schedule,
            ),
            const SizedBox(height: 12),
            _buildOption(
              '7d',
              '7 Days',
              'Delete 7 days after viewing',
              Icons.calendar_today,
            ),
            const SizedBox(height: 12),
            _buildOption(
              'on_close',
              'On Close',
              'Delete when chat closes',
              Icons.exit_to_app,
            ),

            const SizedBox(height: 32),

            // Info box
            if (_selectedDeleteOption != 'off')
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange[700],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Important',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Saved/bookmarked messages won\'t be deleted. ${widget.friendUsername} can still screenshot messages.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(String value, String title, String subtitle, IconData icon) {
    final isSelected = _selectedDeleteOption == value;

    return GestureDetector(
      onTap: () => _saveSettings(value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyan.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.cyan : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.cyan : Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.cyan[700] : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Colors.cyan,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}