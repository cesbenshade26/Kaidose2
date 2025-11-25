import 'package:flutter/material.dart';
import 'dart:io';
import 'DailyList.dart';
import 'DailyData.dart';

class DailySearchWidget extends StatefulWidget {
  final String searchQuery;

  const DailySearchWidget({Key? key, required this.searchQuery}) : super(key: key);

  @override
  State<DailySearchWidget> createState() => _DailySearchWidgetState();
}

class _DailySearchWidgetState extends State<DailySearchWidget> {
  bool _showOnlyAddedDailies = false;
  List<DailyData> _filteredDailies = [];
  VoidCallback? _dailyListListener;

  @override
  void initState() {
    super.initState();
    _loadDailies();

    _dailyListListener = () {
      if (mounted) {
        _loadDailies();
      }
    };

    DailyList.addListener(_dailyListListener!);
  }

  @override
  void dispose() {
    if (_dailyListListener != null) {
      DailyList.removeListener(_dailyListListener!);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(DailySearchWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _filterDailies();
    }
  }

  void _loadDailies() {
    setState(() {
      _filterDailies();
    });
  }

  void _filterDailies() {
    if (!_showOnlyAddedDailies) {
      setState(() {
        _filteredDailies = [];
      });
      return;
    }

    final query = widget.searchQuery.toLowerCase().trim();

    if (query.isEmpty) {
      setState(() {
        _filteredDailies = DailyList.dailies;
      });
    } else {
      setState(() {
        _filteredDailies = DailyList.dailies.where((daily) {
          return daily.title.toLowerCase().contains(query) ||
              daily.description.toLowerCase().contains(query) ||
              daily.keywords.any((keyword) => keyword.toLowerCase().contains(query));
        }).toList();
      });
    }
  }

  void _toggleCheckbox() {
    setState(() {
      _showOnlyAddedDailies = !_showOnlyAddedDailies;
      _filterDailies();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Checkbox
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: _toggleCheckbox,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _showOnlyAddedDailies ? Colors.cyan : Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _showOnlyAddedDailies ? Colors.cyan : Colors.grey[400]!,
                      width: 2,
                    ),
                  ),
                  child: _showOnlyAddedDailies
                      ? const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 14,
                  )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  'Show Added Dailies',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Content area
        Expanded(
          child: _showOnlyAddedDailies
              ? _buildDailiesList()
              : Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_box_outline_blank,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Check the box above',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Enable "Show only Added Dailies" to search your dailies',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailiesList() {
    if (_filteredDailies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              widget.searchQuery.isEmpty ? 'No Dailies Yet' : 'No Results Found',
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
                widget.searchQuery.isEmpty
                    ? 'Create a daily to see it here'
                    : 'Try searching with different keywords',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredDailies.length,
      itemBuilder: (context, index) {
        return _buildDailyCard(_filteredDailies[index]);
      },
    );
  }

  Widget _buildDailyCard(DailyData daily) {
    return GestureDetector(
      onTap: () {
        // Navigate to daily detail screen
        Navigator.pop(context); // Close search first
        // TODO: Navigate to DailyDetailScreen
        print('Open daily: ${daily.title}');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: daily.isPinned ? Colors.cyan : Colors.grey[300]!,
            width: daily.isPinned ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon on the left
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Color(daily.iconColor ?? 0xFF00BCD4).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: daily.customIconPath != null && File(daily.customIconPath!).existsSync()
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(daily.customIconPath!),
                  fit: BoxFit.cover,
                ),
              )
                  : Icon(
                daily.icon,
                color: Color(daily.iconColor ?? 0xFF00BCD4),
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            // Title and info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          daily.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (daily.isPinned)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.cyan,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.push_pin,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    daily.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Active Friends: ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(daily.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    }
  }
}