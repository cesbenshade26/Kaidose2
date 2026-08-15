import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'EditDaily.dart' as edit_daily;
import 'ManageMembers.dart' as manage_members;
import 'DailyHistory.dart';
import 'dart:io';

const List<Map<String, dynamic>> kDailyTags = [
  {'label': 'Sports',      'emoji': '🏆'},
  {'label': 'Music',       'emoji': '🎵'},
  {'label': 'Gaming',      'emoji': '🎮'},
  {'label': 'Fitness',     'emoji': '💪'},
  {'label': 'Food',        'emoji': '🍕'},
  {'label': 'Travel',      'emoji': '✈️'},
  {'label': 'Art',         'emoji': '🎨'},
  {'label': 'Fashion',     'emoji': '👗'},
  {'label': 'Nature',      'emoji': '🌿'},
  {'label': 'Tech',        'emoji': '💻'},
  {'label': 'Movies / TV', 'emoji': '🎬'},
  {'label': 'Books',       'emoji': '📚'},
  {'label': 'Health',      'emoji': '🧘'},
  {'label': 'Finance',     'emoji': '💰'},
  {'label': 'Science',     'emoji': '🔬'},
  {'label': 'Comedy',      'emoji': '😂'},
];

class ManageDailyScreen extends StatefulWidget {
  final DailyData daily;

  const ManageDailyScreen({Key? key, required this.daily}) : super(key: key);

  @override
  State<ManageDailyScreen> createState() => _ManageDailyScreenState();
}

class _ManageDailyScreenState extends State<ManageDailyScreen> {
  int _selectedTabIndex = 0;
  late DailyData _currentDaily;
  bool _isOwner = false;
  bool _checkingOwnership = true;

  Color get _dailyColor => Color(_currentDaily.iconColor ?? 0xFF00BCD4);

  @override
  void initState() {
    super.initState();
    _currentDaily = widget.daily;
    _checkOwnership();
  }

  Future<void> _checkOwnership() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() { _isOwner = false; _checkingOwnership = false; });
      return;
    }

    try {
      // If an accepted invitation exists for this user + daily,
      // they joined via invite — they are NOT the owner.
      final invite = await FirebaseFirestore.instance
          .collection('daily_invitations')
          .where('dailyId', isEqualTo: _currentDaily.id)
          .where('toUserId', isEqualTo: uid)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();

      final isOwner = invite.docs.isEmpty;
      print('OWNERSHIP (ManageDaily): uid=$uid dailyId=${_currentDaily.id} inviteFound=${invite.docs.isNotEmpty} isOwner=$isOwner');
      if (mounted) setState(() { _isOwner = isOwner; _checkingOwnership = false; });
    } catch (e) {
      print('ManageDaily ownership check error: $e');
      if (mounted) setState(() { _isOwner = false; _checkingOwnership = false; });
    }
  }

  void _showEditIconAndTitleDialog() {
    if (!_isOwner) return;
    showDialog(
      context: context,
      builder: (BuildContext context) => _EditIconAndTitleDialog(
        daily: _currentDaily,
        onSave: (updatedDaily) =>
            setState(() => _currentDaily = updatedDaily),
      ),
    );
  }

  void _updateDaily(DailyData updatedDaily) {
    setState(() => _currentDaily = updatedDaily);
  }

  TextStyle _getFontForDaily(DailyData daily) {
    switch (daily.titleFont ?? 'Default') {
      case 'Roboto':           return GoogleFonts.roboto();
      case 'Playfair Display': return GoogleFonts.playfairDisplay();
      case 'Pacifico':         return GoogleFonts.pacifico();
      case 'Bebas Neue':       return GoogleFonts.bebasNeue();
      case 'Caveat':           return GoogleFonts.caveat();
      case 'Permanent Marker': return GoogleFonts.permanentMarker();
      case 'Righteous':        return GoogleFonts.righteous();
      case 'Lobster':          return GoogleFonts.lobster();
      case 'Dancing Script':   return GoogleFonts.dancingScript();
      case 'Bangers':          return GoogleFonts.bangers();
      default:                 return const TextStyle();
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
        title: const Text('Manage Daily',
            style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _checkingOwnership
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: _dailyColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _currentDaily.customIconPath != null &&
                          File(_currentDaily.customIconPath!)
                              .existsSync()
                          ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.file(
                              File(_currentDaily.customIconPath!),
                              fit: BoxFit.cover))
                          : Icon(_currentDaily.icon,
                          color: _dailyColor, size: 50),
                    ),
                    if (_isOwner)
                      Positioned(
                        right: -8,
                        top: -8,
                        child: GestureDetector(
                          onTap: _showEditIconAndTitleDialog,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _dailyColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.grey.withOpacity(0.3),
                                    spreadRadius: 1,
                                    blurRadius: 3)
                              ],
                            ),
                            child: const Icon(Icons.edit,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        _currentDaily.title,
                        style:
                        _getFontForDaily(_currentDaily).copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (_isOwner) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _showEditIconAndTitleDialog,
                        child: Icon(Icons.edit,
                            color: Colors.grey[600], size: 20),
                      ),
                    ],
                  ],
                ),
                if (!_isOwner)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'View only — you are not the owner',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),

          SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                Row(
                  children: [
                    _buildTab(0, Icons.settings, 'Settings'),
                    _buildTab(1, Icons.people, 'Members'),
                    _buildTab(2, Icons.history, 'History'),
                  ],
                ),
                SizedBox(
                  height: 2,
                  child: Stack(
                    children: [
                      Container(
                          width: double.infinity,
                          height: 2,
                          color: Colors.transparent),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        left: MediaQuery.of(context).size.width *
                            _selectedTabIndex / 3,
                        width:
                        MediaQuery.of(context).size.width / 3,
                        child: Container(
                            height: 2, color: _dailyColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(child: _getTabContent()),
        ],
      ),
    );
  }

  Widget _buildTab(int index, IconData icon, String label) {
    final active = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 20,
                  color: active ? Colors.black : Colors.grey),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: active ? Colors.black : Colors.grey)),
            ],
          ),
        ),
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

// ─── Tag picker ───────────────────────────────────────────────────────────────

class DailyTagPicker extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final Color accentColor;

  const DailyTagPicker({
    Key? key,
    required this.selected,
    required this.onToggle,
    this.accentColor = Colors.cyan,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kDailyTags.map((tag) {
        final label = tag['label'] as String;
        final sel = selected.contains(label);
        return GestureDetector(
          onTap: () => onToggle(label),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? accentColor : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: sel ? accentColor : Colors.grey[300]!,
                  width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tag['emoji'] as String,
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.black87)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Edit icon & title dialog ─────────────────────────────────────────────────

class _EditIconAndTitleDialog extends StatefulWidget {
  final DailyData daily;
  final Function(DailyData) onSave;

  const _EditIconAndTitleDialog(
      {required this.daily, required this.onSave});

  @override
  State<_EditIconAndTitleDialog> createState() =>
      _EditIconAndTitleDialogState();
}

class _EditIconAndTitleDialogState
    extends State<_EditIconAndTitleDialog> {
  late TextEditingController _titleController;
  late IconData _selectedIcon;
  late Color _selectedColor;
  late String _selectedFont;
  File? _customIcon;
  final ImagePicker _picker = ImagePicker();

  final List<String> _fontOptions = [
    'Default', 'Roboto', 'Playfair Display', 'Pacifico',
    'Bebas Neue', 'Caveat', 'Permanent Marker', 'Righteous',
    'Lobster', 'Dancing Script', 'Bangers',
  ];

  final List<IconData> _presetIcons = [
    Icons.star, Icons.favorite, Icons.camera_alt, Icons.music_note,
    Icons.sports_basketball, Icons.restaurant, Icons.local_cafe,
    Icons.airplane_ticket, Icons.beach_access, Icons.fitness_center,
    Icons.book, Icons.palette, Icons.code, Icons.science,
    Icons.pets, Icons.games,
  ];

  final List<Color> _colorOptions = [
    Colors.cyan, Colors.blue, Colors.purple, Colors.pink,
    Colors.red, Colors.orange, Colors.amber, Colors.green,
    Colors.teal, Colors.indigo,
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.daily.title);
    _selectedIcon = widget.daily.icon;
    _selectedColor = Color(widget.daily.iconColor ?? 0xFF00BCD4);
    _selectedFont = widget.daily.titleFont ?? 'Default';
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
    final XFile? image =
    await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _customIcon = File(image.path));
  }

  TextStyle _getFontStyle(String f) {
    switch (f) {
      case 'Roboto':           return GoogleFonts.roboto();
      case 'Playfair Display': return GoogleFonts.playfairDisplay();
      case 'Pacifico':         return GoogleFonts.pacifico();
      case 'Bebas Neue':       return GoogleFonts.bebasNeue();
      case 'Caveat':           return GoogleFonts.caveat();
      case 'Permanent Marker': return GoogleFonts.permanentMarker();
      case 'Righteous':        return GoogleFonts.righteous();
      case 'Lobster':          return GoogleFonts.lobster();
      case 'Dancing Script':   return GoogleFonts.dancingScript();
      case 'Bangers':          return GoogleFonts.bangers();
      default:                 return const TextStyle();
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
      foundingMemberIds: widget.daily.foundingMemberIds,
      createdAt: widget.daily.createdAt,
      isPinned: widget.daily.isPinned,
      tierAssignments: widget.daily.tierAssignments,
      tierPrivileges: widget.daily.tierPrivileges,
      titleFont: _selectedFont,
      dailyEntryPrompt: widget.daily.dailyEntryPrompt,
      creatorUid: widget.daily.creatorUid,
    );

    await DailyList.updateDaily(updatedDaily);

    if (mounted) {
      Navigator.of(context).pop();
      widget.onSave(updatedDaily);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Updated for everyone!'),
          backgroundColor: _selectedColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _selectedColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Edit Icon & Title',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Daily Title'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      maxLength: 50,
                      style: _getFontStyle(_selectedFont)
                          .copyWith(fontSize: 16, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Enter daily title...',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: _selectedColor, width: 2)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _label('Title Font'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedFont,
                        isExpanded: true,
                        underline: const SizedBox(),
                        items: _fontOptions
                            .map((f) => DropdownMenuItem(
                            value: f,
                            child: Text(f,
                                style: _getFontStyle(f).copyWith(
                                    fontSize: 16,
                                    color: Colors.black87))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedFont = v);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    _label('Select Icon'),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8),
                      itemCount: _presetIcons.length,
                      itemBuilder: (context, i) {
                        final icon = _presetIcons[i];
                        final sel =
                            _selectedIcon == icon && _customIcon == null;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedIcon = icon;
                            _customIcon = null;
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: sel
                                  ? _selectedColor.withOpacity(0.1)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: sel
                                      ? _selectedColor
                                      : Colors.grey[300]!,
                                  width: sel ? 2 : 1),
                            ),
                            child: Icon(icon,
                                color: sel
                                    ? _selectedColor
                                    : Colors.grey[700],
                                size: 24),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _label('Icon Color'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _colorOptions.map((color) {
                        final sel = _selectedColor == color;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedColor = color),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: sel
                                      ? Colors.black
                                      : Colors.grey[300]!,
                                  width: sel ? 3 : 1),
                            ),
                            child: sel
                                ? const Icon(Icons.check,
                                color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    _label('Or Upload Custom Icon'),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickCustomIcon,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _customIcon != null
                              ? _selectedColor.withOpacity(0.1)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _customIcon != null
                                  ? _selectedColor
                                  : Colors.grey[300]!,
                              width: _customIcon != null ? 2 : 1),
                        ),
                        child: Column(
                          children: [
                            if (_customIcon != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(_customIcon!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover),
                              )
                            else
                              Icon(Icons.cloud_upload_outlined,
                                  size: 40, color: Colors.grey[600]),
                            const SizedBox(height: 8),
                            Text(
                              _customIcon != null
                                  ? 'Custom icon selected'
                                  : 'Upload Icon',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Save Changes',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.black87));
}