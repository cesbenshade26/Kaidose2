import 'package:flutter/material.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'MessageStorage.dart';
import 'SendDailyMessage.dart';

class SelectDailiesScreen extends StatefulWidget {
  final String? messageText;
  final String? imagePath;
  final String? videoPath;

  const SelectDailiesScreen({
    Key? key,
    this.messageText,
    this.imagePath,
    this.videoPath,
  }) : super(key: key);

  @override
  State<SelectDailiesScreen> createState() => _SelectDailiesScreenState();
}

class _SelectDailiesScreenState extends State<SelectDailiesScreen> {
  final Set<String> _selectedDailyIds = {};
  List<DailyData> _dailies = [];

  @override
  void initState() {
    super.initState();
    _loadDailies();
  }

  Future<void> _loadDailies() async {
    await DailyList.loadFromStorage();
    setState(() {
      _dailies = DailyList.dailies;
    });
  }

  void _toggleDaily(String dailyId) {
    setState(() {
      if (_selectedDailyIds.contains(dailyId)) {
        _selectedDailyIds.remove(dailyId);
      } else {
        _selectedDailyIds.add(dailyId);
      }
    });
  }

  Future<void> _sendToSelectedDailies() async {
    if (_selectedDailyIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one daily'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Send message to each selected daily
    for (final dailyId in _selectedDailyIds) {
      final message = DailyMessage(
        text: widget.messageText,
        imagePath: widget.imagePath,
        videoPath: widget.videoPath,
        timestamp: DateTime.now(),
        dailyId: dailyId,
      );

      // Load existing messages
      final messages = await MessageStorage.loadMessages(dailyId);
      messages.add(message);

      // Save updated messages
      await MessageStorage.saveMessages(dailyId, messages);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message sent to ${_selectedDailyIds.length} ${_selectedDailyIds.length == 1 ? 'daily' : 'dailies'}!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Go back to compose screen (pop twice)
      Navigator.pop(context);
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
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Select Dailies',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _dailies.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No Dailies Available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a daily first to send messages',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      )
          : Column(
        children: [
          // Header with selection count
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.1),
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.checklist,
                  color: Colors.cyan,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  _selectedDailyIds.isEmpty
                      ? 'Select dailies to send to'
                      : '${_selectedDailyIds.length} selected',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _selectedDailyIds.isEmpty ? Colors.grey[700] : Colors.cyan,
                  ),
                ),
              ],
            ),
          ),

          // Dailies list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _dailies.length,
              itemBuilder: (context, index) {
                final daily = _dailies[index];
                final isSelected = _selectedDailyIds.contains(daily.id);

                return GestureDetector(
                  onTap: () => _toggleDaily(daily.id),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                        // Checkbox
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.cyan : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? Colors.cyan : Colors.grey[400]!,
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          )
                              : null,
                        ),

                        const SizedBox(width: 16),

                        // Icon
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: daily.iconColor != null
                                ? Color(daily.iconColor!)
                                : Colors.cyan.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            daily.icon,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Title and privacy
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                daily.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    daily.privacy == 'Public'
                                        ? Icons.public
                                        : Icons.lock,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    daily.privacy,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
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
                );
              },
            ),
          ),

          // Send button
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _sendToSelectedDailies,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.send, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        _selectedDailyIds.isEmpty
                            ? 'Send to Chosen Dailies'
                            : 'Send to ${_selectedDailyIds.length} ${_selectedDailyIds.length == 1 ? 'Daily' : 'Dailies'}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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