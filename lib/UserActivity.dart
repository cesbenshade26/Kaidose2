import 'package:flutter/material.dart';
import 'YourDailyActivity.dart';
import 'DailyPostActivity.dart';

class UserActivityWidget extends StatefulWidget {
  const UserActivityWidget({Key? key}) : super(key: key);

  @override
  State<UserActivityWidget> createState() => _UserActivityWidgetState();
}

class _UserActivityWidgetState extends State<UserActivityWidget> {
  String _selectedFilter = 'Your Daily';

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildContent(),
        Positioned(
          top: 8,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!.withOpacity(0.5), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  spreadRadius: 0,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: DropdownButton<String>(
              value: _selectedFilter,
              underline: const SizedBox(),
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600], size: 20),
              isDense: true,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
              items: const [
                DropdownMenuItem(value: 'Your Daily', child: Text('Your Daily')),
                DropdownMenuItem(value: 'Daily Posts', child: Text('Daily Posts')),
              ],
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedFilter = newValue;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_selectedFilter == 'Your Daily') {
      return const YourDailyActivity();
    } else {
      return const DailyPostActivity();
    }
  }
}