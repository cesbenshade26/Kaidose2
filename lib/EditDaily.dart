import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'DailyList.dart';

class EditDaily extends StatefulWidget {
  final DailyData daily;
  final Function(DailyData) onSave;

  const EditDaily({
    Key? key,
    required this.daily,
    required this.onSave,
  }) : super(key: key);

  @override
  State<EditDaily> createState() => _EditDailyState();
}

class _EditDailyState extends State<EditDaily> {
  late TextEditingController _descriptionController;
  late String _selectedPrivacy;
  late List<TextEditingController> _keywordControllers;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.daily.description);
    _selectedPrivacy = widget.daily.privacy;
    _keywordControllers = widget.daily.keywords
        .map((keyword) => TextEditingController(text: keyword))
        .toList();
    if (_keywordControllers.isEmpty) {
      _keywordControllers = [
        TextEditingController(),
        TextEditingController(),
        TextEditingController(),
      ];
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    for (var controller in _keywordControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addKeywordField() {
    setState(() {
      _keywordControllers.add(TextEditingController());
    });
  }

  Future<void> _saveChanges() async {
    // Collect keywords
    List<String> keywords = _keywordControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    // Create updated daily
    final updatedDaily = DailyData(
      id: widget.daily.id,
      title: widget.daily.title,
      description: _descriptionController.text.trim(),
      privacy: _selectedPrivacy,
      keywords: keywords,
      managementTiers: widget.daily.managementTiers,
      icon: widget.daily.icon,
      iconColor: widget.daily.iconColor,
      customIconPath: widget.daily.customIconPath,
      invitedFriendIds: widget.daily.invitedFriendIds,
      createdAt: widget.daily.createdAt,
      isPinned: widget.daily.isPinned,
    );

    // Delete old and add updated
    await DailyList.deleteDaily(widget.daily.id);
    await DailyList.addDaily(updatedDaily);

    widget.onSave(updatedDaily);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Changes saved successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description
                const Text(
                  'Description',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    hintText: 'Enter description...',
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
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
                        color: Colors.cyan,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  maxLines: 4,
                  maxLength: 200,
                ),
                const SizedBox(height: 24),

                // Privacy
                const Text(
                  'Privacy',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPrivacy = 'Public';
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedPrivacy == 'Public' ? Colors.cyan : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedPrivacy == 'Public'
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: _selectedPrivacy == 'Public' ? Colors.cyan : Colors.grey[400],
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Public',
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
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPrivacy = 'Private';
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedPrivacy == 'Private' ? Colors.cyan : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedPrivacy == 'Private'
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: _selectedPrivacy == 'Private' ? Colors.cyan : Colors.grey[400],
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Private',
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
                const SizedBox(height: 24),

                // Keywords
                const Text(
                  'Keywords',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: _keywordControllers.length > 3 ? 200 : null,
                  decoration: _keywordControllers.length > 3
                      ? BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  )
                      : null,
                  child: _keywordControllers.length > 3
                      ? Scrollbar(
                    thumbVisibility: true,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _keywordControllers.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildKeywordField(index),
                        );
                      },
                    ),
                  )
                      : Column(
                    children: List.generate(
                      _keywordControllers.length,
                          (index) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildKeywordField(index),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _addKeywordField,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add,
                          size: 16,
                          color: Colors.grey[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Add another',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // Save button at bottom
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
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
          child: ElevatedButton(
            onPressed: _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Save Changes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeywordField(int index) {
    return TextField(
      controller: _keywordControllers[index],
      decoration: InputDecoration(
        hintText: 'Keyword ${index + 1}',
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontSize: 14,
        ),
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: Colors.cyan,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
      style: const TextStyle(
        fontSize: 14,
        color: Colors.black87,
      ),
      maxLength: 20,
      buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
        return const SizedBox.shrink();
      },
    );
  }
}