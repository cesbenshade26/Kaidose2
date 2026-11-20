import 'dart:async';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'DailyFonts.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'DailyModeration.dart';
import 'DailyIcon.dart';
export 'DailyIcon.dart' show DailyIconTile;
import 'EditDaily.dart' as edit_daily;
import 'ManageMembers.dart' as manage_members;
import 'dart:io';

/// Dark grey used instead of black on the Manage Daily screens.
Color get kManageInk => kc.adapt(const Color(0xFF2E2E2E));

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
  // Two tabs: Settings and Members.
  static const int _tabCount = 2;

  int _selectedTabIndex = 0;
  late DailyData _currentDaily;

  // Owner / moderator / member, kept live (a moderator added or removed
  // while this is open updates right away).
  DailyPermissions? _perms;
  StreamSubscription<DailyPermissions>? _permsSub;

  @override
  void initState() {
    super.initState();
    _currentDaily = widget.daily;
    _permsSub = DailyModeration.watchPermissions(_currentDaily).listen((p) {
      if (mounted) setState(() => _perms = p);
    }, onError: (e) {
      print('ManageDaily: permissions error: $e');
      if (mounted) setState(() => _perms = DailyPermissions.none);
    });
  }

  @override
  void dispose() {
    _permsSub?.cancel();
    super.dispose();
  }

  bool get _canEdit => _perms?.canEditDetails == true;

  Future<void> _editIconAndTitle() async {
    if (!_canEdit) return;
    final updated = await showModalBottomSheet<DailyData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditIconAndTitleSheet(daily: _currentDaily),
    );
    if (updated == null || !mounted) return;
    setState(() => _currentDaily = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Updated for everyone'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _updateDaily(DailyData updatedDaily) {
    setState(() => _currentDaily = updatedDaily);
  }

  String _formatCreatedDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final perms = _perms;
    return Scaffold(
      backgroundColor: kc.background,
      appBar: AppBar(
        backgroundColor: kc.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: kManageInk, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Manage Daily',
            style: TextStyle(
                color: kManageInk,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: perms == null
          ? Center(
          child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))))
          : Column(
        children: [
          _header(perms),
          _tabs(),
          Expanded(child: _getTabContent(perms)),
        ],
      ),
    );
  }

  /// Icon, title, created date and your role. The owner taps the icon or
  /// the title to change them.
  Widget _header(DailyPermissions perms) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        children: [
          GestureDetector(
            onTap: _canEdit ? _editIconAndTitle : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DailyIconTile(
                  icon: _currentDaily.icon,
                  customIconPath: _currentDaily.customIconPath,
                  size: 88,
                  radius: 20,
                ),
                if (_canEdit)
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.cyan,
                        shape: BoxShape.circle,
                        border: Border.all(color: kc.background, width: 2.5),
                      ),
                      child: const Icon(Icons.edit,
                          color: Colors.white, size: 14),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _canEdit ? _editIconAndTitle : null,
            child: Text(
              _currentDaily.title,
              textAlign: TextAlign.center,
              // Plain here: the Daily's own font is only for its card and
              // the inside of the Daily.
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: kManageInk,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Created ${_formatCreatedDate(_currentDaily.createdAt)}',
            style: TextStyle(fontSize: 13, color: kc.grey(500)),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kc.grey(100),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  perms.isOwner
                      ? Icons.star_rounded
                      : perms.isModerator
                      ? Icons.shield_rounded
                      : Icons.visibility_outlined,
                  size: 14,
                  color: kc.grey(700),
                ),
                const SizedBox(width: 5),
                Text(perms.label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: kc.grey(700))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    return Column(
      children: [
        Row(
          children: [
            _buildTab(0, Icons.settings_outlined, 'Settings'),
            _buildTab(1, Icons.people_outline, 'Members'),
          ],
        ),
        LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth / _tabCount;
          return SizedBox(
            height: 2,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(color: kc.grey(200)),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  left: w * _selectedTabIndex,
                  width: w,
                  top: 0,
                  bottom: 0,
                  child: Container(color: kc.text),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTab(int index, IconData icon, String label) {
    final active = _selectedTabIndex == index;
    final color = active ? kManageInk : kc.grey(500);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getTabContent(DailyPermissions perms) {
    switch (_selectedTabIndex) {
      case 1:
        return manage_members.ManageMembers(daily: _currentDaily);
      case 0:
      default:
        return edit_daily.EditDaily(
          daily: _currentDaily,
          permissions: perms,
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
              color: sel ? accentColor : kc.grey(100),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: sel ? accentColor : kc.grey(300),
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
                        color: sel ? Colors.white : kManageInk)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Edit icon & title ───────────────────────────────────────────────────────

/// Bottom sheet to change the title, its font and the icon (a preset or
/// your own picture), with a live preview at the top. Returns the updated
/// Daily, or null if closed without saving.
class _EditIconAndTitleSheet extends StatefulWidget {
  final DailyData daily;

  const _EditIconAndTitleSheet({required this.daily});

  @override
  State<_EditIconAndTitleSheet> createState() => _EditIconAndTitleSheetState();
}

class _EditIconAndTitleSheetState extends State<_EditIconAndTitleSheet> {
  late final TextEditingController _title =
  TextEditingController(text: widget.daily.title);
  late IconData _icon = widget.daily.icon;
  late String _font = DailyFonts.normalize(widget.daily.titleFont);
  // The custom picture: its Storage URL, or a file just picked from the
  // phone (uploaded on Save). Null = a preset icon.
  late String? _custom = _usable(widget.daily.customIconPath);
  bool _saving = false;
  final ImagePicker _picker = ImagePicker();


  static const List<IconData> _icons = [
    Icons.star, Icons.favorite, Icons.camera_alt, Icons.music_note,
    Icons.sports_basketball, Icons.restaurant, Icons.local_cafe,
    Icons.airplane_ticket, Icons.beach_access, Icons.fitness_center,
    Icons.book, Icons.palette, Icons.code, Icons.science,
    Icons.pets, Icons.games, Icons.sports_soccer, Icons.landscape,
  ];

  static String? _usable(String? path) {
    if (path == null) return null;
    if (DailyIconStore.isRemote(path)) return path;
    return File(path).existsSync() ? path : null;
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    final image = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 600, imageQuality: 85);
    if (image != null && mounted) setState(() => _custom = image.path);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    final d = widget.daily;
    // A newly picked picture goes up to Storage first, so everyone sees it.
    String? iconUrl;
    try {
      iconUrl = _custom == null
          ? null
          : await DailyIconStore.upload(d.id, _custom!);
    } catch (e) {
      print('ManageDaily: icon upload failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't upload the picture. Try again.")),
      );
      return;
    }
    final updated = DailyData(
      id: d.id,
      title: title,
      description: d.description,
      privacy: d.privacy,
      keywords: d.keywords,
      managementTiers: d.managementTiers,
      icon: _icon,
      // Icon colors aren't used anymore; whatever was saved stays.
      iconColor: d.iconColor,
      customIconPath: iconUrl,
      invitedFriendIds: d.invitedFriendIds,
      foundingMemberIds: d.foundingMemberIds,
      createdAt: d.createdAt,
      isPinned: d.isPinned,
      tierAssignments: d.tierAssignments,
      tierPrivileges: d.tierPrivileges,
      titleFont: _font,
      dailyEntryPrompt: d.dailyEntryPrompt,
      creatorUid: d.creatorUid,
    );
    try {
      await DailyList.updateDaily(updated);
      await _syncPublicCopy(updated);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      print('ManageDaily: save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.88;
    final title = _title.text.trim();

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: kc.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kc.grey(300),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Live preview: exactly how it'll look.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Row(
                    children: [
                      DailyIconTile(
                        icon: _icon,
                        customIconPath: _custom,
                        size: 52,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title.isEmpty ? 'Daily name' : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DailyFonts.style(_font,
                              fontWeight: FontWeight.w700)
                              .copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: title.isEmpty
                                ? kc.grey(400)
                                : kManageInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Name'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _title,
                          maxLength: 50,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Daily name',
                            hintStyle: TextStyle(color: kc.grey(400)),
                            filled: true,
                            fillColor: kc.grey(100),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 13),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _label('Font'),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: DailyFonts.options.length,
                            separatorBuilder: (_, __) =>
                            const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final f = DailyFonts.options[i];
                              final sel = f == _font;
                              return GestureDetector(
                                onTap: () => setState(() => _font = f),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: sel ? Colors.cyan : kc.grey(100),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    f,
                                    style: DailyFonts.style(f).copyWith(
                                      fontSize: 15,
                                      color: sel ? Colors.white : kManageInk,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 22),
                        _label('Icon'),
                        const SizedBox(height: 10),
                        _iconGrid(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: title.isEmpty || _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.cyan.withOpacity(0.4),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                          : const Text('Save',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// For You cards are drawn from the Daily's public copy
  /// (public_dailies), so a new name, font or icon goes there too and
  /// everyone sees it. update() fails on purpose for a Daily that isn't
  /// public (no copy), so a private Daily never gets one.
  Future<void> _syncPublicCopy(DailyData d) async {
    try {
      final data = d.toFirestoreJson()..removeWhere((_, v) => v == null);
      await FirebaseFirestore.instance
          .collection('public_dailies')
          .doc(d.id)
          .update(data);
    } catch (_) {
      // Not a public Daily: nothing to update.
    }
  }

  /// Your own picture first, then the preset icons. Every cell is the same
  /// fixed square, so nothing can overflow.
  Widget _iconGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _icons.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          final custom = _custom;
          return _cell(
            selected: custom != null,
            onTap: _pickPicture,
            child: custom != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: DailyIconPicture(
                path: custom,
                fallback: Icon(Icons.add_photo_alternate_outlined,
                    color: kc.grey(700)),
              ),
            )
                : Icon(Icons.add_photo_alternate_outlined,
                color: kc.grey(700), size: 22),
          );
        }
        final icon = _icons[i - 1];
        return _cell(
          selected: _custom == null && _icon == icon,
          onTap: () => setState(() {
            _icon = icon;
            _custom = null;
          }),
          child: Icon(icon, color: kc.grey(800), size: 22),
        );
      },
    );
  }

  Widget _cell({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: kc.grey(100),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.cyan : Colors.transparent,
            width: 2,
          ),
        ),
        padding: EdgeInsets.all(selected ? 1 : 3),
        child: Center(child: child),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
  );
}