import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'EditDaily.dart' as edit_daily;
import 'ManageMembers.dart' as manage_members;
import 'DailyHistory.dart';
import 'dart:io';

class ManageDailyScreen extends StatefulWidget {
  final DailyData daily;

  const ManageDailyScreen({Key? key, required this.daily}) : super(key: key);

  @override
  State<ManageDailyScreen> createState() => _ManageDailyScreenState();
}

class _ManageDailyScreenState extends State<ManageDailyScreen> {
  int _selectedTabIndex = 0;
  late DailyData _currentDaily;

  @override
  void initState() {
    super.initState();
    _currentDaily = widget.daily;
  }

  void _showEditIconAndTitleDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => _EditIconAndTitleDialog(
        daily: _currentDaily,
        onSave: (updatedDaily) {
          setState(() {
            _currentDaily = updatedDaily;
          });
        },
      ),
    );
  }

  void _updateDaily(DailyData updatedDaily) {
    setState(() {
      _currentDaily = updatedDaily;
    });
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
        title: const Text(
          'Manage Daily',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Icon and Title at top
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                // Icon with edit button
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Color(_currentDaily.iconColor ?? 0xFF00BCD4).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _currentDaily.customIconPath != null && File(_currentDaily.customIconPath!).existsSync()
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(
                          File(_currentDaily.customIconPath!),
                          fit: BoxFit.cover,
                        ),
                      )
                          : Icon(
                        _currentDaily.icon,
                        color: Color(_currentDaily.iconColor ?? 0xFF00BCD4),
                        size: 50,
                      ),
                    ),
                    Positioned(
                      right: -8,
                      top: -8,
                      child: GestureDetector(
                        onTap: _showEditIconAndTitleDialog,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.cyan,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.3),
                                spreadRadius: 1,
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Title with edit button
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        _currentDaily.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _showEditIconAndTitleDialog,
                      child: Icon(
                        Icons.edit,
                        color: Colors.grey[600],
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tab section
          Container(
            width: double.infinity,
            child: Column(
              children: [
                // Tab buttons
                Row(
                  children: [
                    // Settings tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 0;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.settings,
                                size: 20,
                                color: _selectedTabIndex == 0 ? Colors.black : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Settings',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: _selectedTabIndex == 0 ? Colors.black : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Members tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 1;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people,
                                size: 20,
                                color: _selectedTabIndex == 1 ? Colors.black : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Members',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: _selectedTabIndex == 1 ? Colors.black : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // History tab
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 2;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history,
                                size: 20,
                                color: _selectedTabIndex == 2 ? Colors.black : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'History',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: _selectedTabIndex == 2 ? Colors.black : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Animated sliding indicator
                Container(
                  height: 2,
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 2,
                        color: Colors.transparent,
                      ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        left: MediaQuery.of(context).size.width * _selectedTabIndex / 3,
                        width: MediaQuery.of(context).size.width / 3,
                        child: Container(
                          height: 2,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content area based on selected tab
          Expanded(
            child: _getTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _getTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return edit_daily.EditDaily(
          daily: _currentDaily,
          onSave: _updateDaily,
        );
      case 1:
        return manage_members.ManageMembers(daily: _currentDaily);
      case 2:
        return DailyHistory(daily: _currentDaily);
      default:
        return edit_daily.EditDaily(
          daily: _currentDaily,
          onSave: _updateDaily,
        );
    }
  }
}

// Edit Icon and Title Dialog
class _EditIconAndTitleDialog extends StatefulWidget {
  final DailyData daily;
  final Function(DailyData) onSave;

  const _EditIconAndTitleDialog({
    required this.daily,
    required this.onSave,
  });

  @override
  State<_EditIconAndTitleDialog> createState() => _EditIconAndTitleDialogState();
}

class _EditIconAndTitleDialogState extends State<_EditIconAndTitleDialog> {
  late TextEditingController _titleController;
  late IconData _selectedIcon;
  late Color _selectedColor;
  File? _customIcon;
  final ImagePicker _picker = ImagePicker();

  final List<IconData> _presetIcons = [
    Icons.star,
    Icons.favorite,
    Icons.camera_alt,
    Icons.music_note,
    Icons.sports_basketball,
    Icons.restaurant,
    Icons.local_cafe,
    Icons.airplane_ticket,
    Icons.beach_access,
    Icons.fitness_center,
    Icons.book,
    Icons.palette,
    Icons.code,
    Icons.science,
    Icons.pets,
    Icons.games,
  ];

  final List<Color> _colorOptions = [
    Colors.cyan,
    Colors.blue,
    Colors.purple,
    Colors.pink,
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.teal,
    Colors.indigo,
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.daily.title);
    _selectedIcon = widget.daily.icon;
    _selectedColor = Color(widget.daily.iconColor ?? 0xFF00BCD4);
    if (widget.daily.customIconPath != null) {
      _customIcon = File(widget.daily.customIconPath!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomIcon() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _customIcon = File(image.path);
      });
    }
  }

  Future<void> _saveChanges() async {
    final updatedDaily = DailyData(
      id: widget.daily.id,
      title: _titleController.text.trim(),
      description: widget.daily.description,
      privacy: widget.daily.privacy,
      keywords: widget.daily.keywords,
      managementTiers: widget.daily.managementTiers,
      icon: _selectedIcon,
      iconColor: _selectedColor.value,
      customIconPath: _customIcon?.path,
      invitedFriendIds: widget.daily.invitedFriendIds,
      createdAt: widget.daily.createdAt,
      isPinned: widget.daily.isPinned,
    );

    await DailyList.deleteDaily(widget.daily.id);
    await DailyList.addDaily(updatedDaily);

    if (mounted) {
      Navigator.of(context).pop();
      widget.onSave(updatedDaily);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Icon and title updated!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.cyan,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Edit Icon & Title',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    const Text(
                      'Daily Title',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        hintText: 'Enter daily title...',
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
                      maxLength: 50,
                    ),
                    const SizedBox(height: 16),

                    // Icon selection
                    const Text(
                      'Select Icon',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _presetIcons.length,
                      itemBuilder: (context, index) {
                        final icon = _presetIcons[index];
                        final isSelected = _selectedIcon == icon && _customIcon == null;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedIcon = icon;
                              _customIcon = null;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? _selectedColor.withOpacity(0.1) : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? _selectedColor : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              icon,
                              color: isSelected ? _selectedColor : Colors.grey[700],
                              size: 24,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Color selection
                    const Text(
                      'Icon Color',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _colorOptions.map((color) {
                        final isSelected = _selectedColor == color;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedColor = color;
                            });
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.black : Colors.grey[300]!,
                                width: isSelected ? 3 : 1,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Custom icon upload
                    const Text(
                      'Or Upload Custom Icon',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickCustomIcon,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _customIcon != null ? Colors.cyan.withOpacity(0.1) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _customIcon != null ? Colors.cyan : Colors.grey[300]!,
                            width: _customIcon != null ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            if (_customIcon != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _customIcon!,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Icon(
                                Icons.cloud_upload_outlined,
                                size: 40,
                                color: Colors.grey[600],
                              ),
                            const SizedBox(height: 8),
                            Text(
                              _customIcon != null ? 'Custom icon selected' : 'Upload Icon',
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
                  ],
                ),
              ),
            ),

            // Save button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
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
        ),
      ),
    );
  }
}