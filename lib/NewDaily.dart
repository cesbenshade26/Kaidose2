import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'InviteFriends.dart';

class NewDailyScreen extends StatefulWidget {
  const NewDailyScreen({Key? key}) : super(key: key);

  @override
  State<NewDailyScreen> createState() => _NewDailyScreenState();
}

class _NewDailyScreenState extends State<NewDailyScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedPrivacy = 'Public';
  List<TextEditingController> _keywordControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  List<TextEditingController> _tierControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (var controller in _keywordControllers) {
      controller.dispose();
    }
    for (var controller in _tierControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addKeywordField() {
    setState(() {
      _keywordControllers.add(TextEditingController());
    });
  }

  void _addTierField() {
    setState(() {
      _tierControllers.add(TextEditingController());
    });
  }

  void _goToNextScreen() {
    List<String> keywords = _keywordControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    List<String> tiers = _tierControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewDailyNextScreen(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          privacy: _selectedPrivacy,
          keywords: keywords,
          tiers: tiers,
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
        title: const Text(
          'Create Daily',
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
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                        return Text(
                          '$currentLength/$maxLength',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
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
                    const Text(
                      'Add Description!',
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
                      buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                        return Text(
                          '$currentLength/$maxLength',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Add some Keywords',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '(This will help us connect you with some users)',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
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
                    const SizedBox(height: 24),

                    // Management Tiers Section
                    const Text(
                      'Management Tiers',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: _tierControllers.length > 3 ? 200 : null,
                      decoration: _tierControllers.length > 3
                          ? BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      )
                          : null,
                      child: _tierControllers.length > 3
                          ? Scrollbar(
                        thumbVisibility: true,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _tierControllers.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildTierField(index),
                            );
                          },
                        ),
                      )
                          : Column(
                        children: List.generate(
                          _tierControllers.length,
                              (index) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildTierField(index),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _addTierField,
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
          ),
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
              onPressed: _goToNextScreen,
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
                'Next',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildTierField(int index) {
    return TextField(
      controller: _tierControllers[index],
      decoration: InputDecoration(
        hintText: 'Tier ${index + 1}',
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
      maxLength: 30,
      buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
        return const SizedBox.shrink();
      },
    );
  }
}

class NewDailyNextScreen extends StatefulWidget {
  final String title;
  final String description;
  final String privacy;
  final List<String> keywords;
  final List<String> tiers;

  const NewDailyNextScreen({
    Key? key,
    required this.title,
    required this.description,
    required this.privacy,
    required this.keywords,
    required this.tiers,
  }) : super(key: key);

  @override
  State<NewDailyNextScreen> createState() => _NewDailyNextScreenState();
}

class _NewDailyNextScreenState extends State<NewDailyNextScreen> {
  Set<String> _invitedFriendNames = {};

  void _handleInvitedFriendsChanged(Set<String> invitedNames) {
    setState(() {
      _invitedFriendNames = invitedNames;
    });
  }

  void _handleNext() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewDailyFinalScreen(
          title: widget.title,
          description: widget.description,
          privacy: widget.privacy,
          keywords: widget.keywords,
          tiers: widget.tiers,
          selectedFriendIds: _invitedFriendNames.toList(),
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
        title: const Text(
          'Invite Friends',
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
          Expanded(
            child: InviteFriends(
              onInvitedFriendsChanged: _handleInvitedFriendsChanged,
            ),
          ),
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
              onPressed: _handleNext,
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
                'Next',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NewDailyFinalScreen extends StatefulWidget {
  final String title;
  final String description;
  final String privacy;
  final List<String> keywords;
  final List<String> tiers;
  final List<String> selectedFriendIds;

  const NewDailyFinalScreen({
    Key? key,
    required this.title,
    required this.description,
    required this.privacy,
    required this.keywords,
    required this.tiers,
    required this.selectedFriendIds,
  }) : super(key: key);

  @override
  State<NewDailyFinalScreen> createState() => _NewDailyFinalScreenState();
}

class _NewDailyFinalScreenState extends State<NewDailyFinalScreen> {
  IconData _selectedIcon = Icons.star;
  File? _customIcon;
  Color _selectedColor = Colors.cyan;
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

  Future<void> _pickCustomIcon() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _customIcon = File(image.path);
      });
    }
  }

  Future<void> _publishDaily() async {
    final daily = DailyData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: widget.title,
      description: widget.description,
      privacy: widget.privacy,
      keywords: widget.keywords,
      managementTiers: widget.tiers,
      icon: _selectedIcon,
      iconColor: _selectedColor.value,
      customIconPath: _customIcon?.path,
      invitedFriendIds: widget.selectedFriendIds,
      createdAt: DateTime.now(),
    );

    await DailyList.addDaily(daily);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Daily published successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.of(context).popUntil((route) => route.isFirst);
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
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Choose Icon',
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
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select an Icon',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
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
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? _selectedColor : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              icon,
                              color: isSelected ? _selectedColor : Colors.grey[700],
                              size: 32,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Icon Color',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _colorOptions.map((color) {
                        final isSelected = _selectedColor == color;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedColor = color;
                            });
                          },
                          child: Container(
                            width: 50,
                            height: 50,
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
                              size: 24,
                            )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Or Upload Custom Icon',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _pickCustomIcon,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
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
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Icon(
                                Icons.cloud_upload_outlined,
                                size: 48,
                                color: Colors.grey[600],
                              ),
                            const SizedBox(height: 8),
                            Text(
                              _customIcon != null ? 'Custom icon selected' : 'Upload Icon',
                              style: TextStyle(
                                fontSize: 16,
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
          ),
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
              onPressed: _publishDaily,
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
                'Publish Daily',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}