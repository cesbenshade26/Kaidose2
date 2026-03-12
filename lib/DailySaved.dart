import 'package:flutter/material.dart';
import 'dart:io';
import 'SendDailyMessage.dart';
import 'SavedItemViewer.dart';
import 'DailyData.dart';
import 'MessageStorage.dart';

class DailySavedScreen extends StatefulWidget {
  final DailyData daily;

  const DailySavedScreen({
    Key? key,
    required this.daily,
  }) : super(key: key);

  @override
  State<DailySavedScreen> createState() => _DailySavedScreenState();
}

class _DailySavedScreenState extends State<DailySavedScreen> {
  List<DailyMessage> _savedItems = [];
  bool _isLoading = true;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadSavedItems();
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

  List<DailyMessage> _getFilteredItems() {
    if (_selectedDate == null) return _savedItems;

    final dateStr = _selectedDate!.toIso8601String().split('T')[0];
    return _savedItems.where((msg) {
      final msgDateStr = msg.timestamp.toIso8601String().split('T')[0];
      return msgDateStr == dateStr;
    }).toList();
  }

  Future<void> _loadSavedItems() async {
    // Load messages for this daily
    final messages = await MessageStorage.loadMessages(widget.daily.id);

    // Filter to only saved messages
    final savedMessages = messages.where((msg) => msg.isSaved).toList();

    if (mounted) {
      setState(() {
        _savedItems = savedMessages;
        _isLoading = false;
      });
    }
  }

  Widget _buildGridItem(DailyMessage message, int index) {
    final hasImage = message.imagePath != null && message.imagePath!.isNotEmpty;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SavedItemViewer(
              items: _savedItems,
              initialIndex: index,
            ),
          ),
        );
      },
      child: hasImage
          ? Image.file(
        File(message.imagePath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[200],
            child: Icon(
              Icons.broken_image,
              color: Colors.grey[400],
              size: 40,
            ),
          );
        },
      )
          : Container(
        color: Colors.grey[100],
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          message.text ?? '',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
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
          'Saved from ${widget.daily.title}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Colors.cyan,
        ),
      )
          : _savedItems.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Saved Items',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Save messages from this daily to see them here',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      )
          : Stack(
        children: [
          GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 0,
              mainAxisSpacing: 0,
              childAspectRatio: 1,
            ),
            itemCount: _getFilteredItems().length,
            itemBuilder: (context, index) {
              final filteredItems = _getFilteredItems();
              return _buildGridItem(filteredItems[index], index);
            },
          ),

          // Floating date button
          Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
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
      ),
    );
  }
}