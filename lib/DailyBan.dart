import 'package:flutter/material.dart';

enum BanType { temporary, permanent }

enum TimeUnit { minutes, hours, days }

class DailyBanDialog extends StatefulWidget {
  final String memberName;
  final String dailyId;

  const DailyBanDialog({
    Key? key,
    required this.memberName,
    required this.dailyId,
  }) : super(key: key);

  @override
  State<DailyBanDialog> createState() => _DailyBanDialogState();
}

class _DailyBanDialogState extends State<DailyBanDialog> {
  BanType? _selectedBanType;
  TimeUnit _selectedTimeUnit = TimeUnit.days;
  int _timeValue = 1;
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Confirm Ban',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to ban ${widget.memberName}?',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Ban Details',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.red[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Type: ${_selectedBanType == BanType.temporary ? 'Temporary' : 'Permanent'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red[900],
                    ),
                  ),
                  if (_selectedBanType == BanType.temporary)
                    Text(
                      'Duration: $_timeValue ${_getTimeUnitString()}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red[900],
                      ),
                    ),
                  if (_reasonController.text.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Reason: ${_reasonController.text}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red[900],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close confirm dialog
            },
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              // TODO: Implement actual ban logic here
              // For now, just stay on the confirm popup as requested
              print('Ban confirmed for ${widget.memberName}');
              print('Ban type: $_selectedBanType');
              if (_selectedBanType == BanType.temporary) {
                print('Duration: $_timeValue ${_getTimeUnitString()}');
              }
              print('Reason: ${_reasonController.text}');
            },
            child: const Text(
              'Confirm',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeUnitString() {
    switch (_selectedTimeUnit) {
      case TimeUnit.minutes:
        return _timeValue == 1 ? 'minute' : 'minutes';
      case TimeUnit.hours:
        return _timeValue == 1 ? 'hour' : 'hours';
      case TimeUnit.days:
        return _timeValue == 1 ? 'day' : 'days';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 550, maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ban Member',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.memberName,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ban Type Selection
                    const Text(
                      'Ban Type',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Temporary option
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedBanType = BanType.temporary;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _selectedBanType == BanType.temporary
                              ? Colors.red.withOpacity(0.1)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedBanType == BanType.temporary
                                ? Colors.red
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _selectedBanType == BanType.temporary
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: _selectedBanType == BanType.temporary
                                  ? Colors.red
                                  : Colors.grey[400],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Temporary',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Permanent option
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedBanType = BanType.permanent;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _selectedBanType == BanType.permanent
                              ? Colors.red.withOpacity(0.1)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedBanType == BanType.permanent
                                ? Colors.red
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _selectedBanType == BanType.permanent
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: _selectedBanType == BanType.permanent
                                  ? Colors.red
                                  : Colors.grey[400],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Permanent',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Time selection for temporary ban
                    if (_selectedBanType == BanType.temporary) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Ban Duration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            // Time value input
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Amount',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove, size: 20),
                                          onPressed: () {
                                            setState(() {
                                              if (_timeValue > 1) _timeValue--;
                                            });
                                          },
                                        ),
                                        Text(
                                          '$_timeValue',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add, size: 20),
                                          onPressed: () {
                                            setState(() {
                                              _timeValue++;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Time unit dropdown
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Unit',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: DropdownButton<TimeUnit>(
                                      value: _selectedTimeUnit,
                                      isExpanded: true,
                                      underline: const SizedBox(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black87,
                                      ),
                                      items: TimeUnit.values.map((TimeUnit unit) {
                                        return DropdownMenuItem<TimeUnit>(
                                          value: unit,
                                          child: Text(
                                            unit.toString().split('.').last.capitalize(),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (TimeUnit? newValue) {
                                        if (newValue != null) {
                                          setState(() {
                                            _selectedTimeUnit = newValue;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Reasoning text field
                    const Text(
                      'Reasoning',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reasonController,
                      decoration: InputDecoration(
                        hintText: 'Enter reason for ban (optional)...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      maxLines: 3,
                      maxLength: 300,
                      buildCounter: (context,
                          {required currentLength, required isFocused, maxLength}) {
                        return Text(
                          '$currentLength/$maxLength',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Ban button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: _selectedBanType == null
                    ? null
                    : _showConfirmDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[500],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Ban',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}