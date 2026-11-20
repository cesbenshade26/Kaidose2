import 'dart:async';
import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'DailyData.dart';
import 'DailyModeration.dart';
import 'DailyList.dart';
import 'DailyScheduleEditor.dart';
import 'ManageDaily.dart' show DailyTagPicker, kDailyTags, kManageInk;

/// Settings tab of Manage Daily.
///   Owner      everything here
///   Moderator  the schedule (covers + entry prompts) only
///   Member     view only
class EditDaily extends StatefulWidget {
  final DailyData daily;
  final Function(DailyData) onSave;

  /// Who's looking. Left out, it's worked out here.
  final DailyPermissions? permissions;

  const EditDaily({
    Key? key,
    required this.daily,
    required this.onSave,
    this.permissions,
  }) : super(key: key);

  @override
  State<EditDaily> createState() => _EditDailyState();
}

class _EditDailyState extends State<EditDaily> {
  late TextEditingController _descriptionController;
  late String _selectedPrivacy;
  late Set<String> _selectedTags;
  DailyPermissions? _ownPerms;
  StreamSubscription<DailyPermissions>? _permsSub;

  DailyPermissions? get _perms => widget.permissions ?? _ownPerms;
  // Description, privacy and tags: owner only.
  bool get _isOwner => _perms?.canEditDetails == true;
  // Covers and prompts: owner and moderators.
  bool get _canSchedule => _perms?.canSchedule == true;

  // Accent for buttons, selections and the schedule editor.
  Color get _dailyColor => Colors.cyan;

  @override
  void initState() {
    super.initState();
    _descriptionController =
        TextEditingController(text: widget.daily.description);
    _selectedPrivacy = widget.daily.privacy;
    _selectedTags = Set<String>.from(widget.daily.keywords);
    if (widget.permissions == null) {
      _permsSub = DailyModeration.watchPermissions(widget.daily).listen((p) {
        if (mounted) setState(() => _ownPerms = p);
      });
    }
  }

  @override
  void dispose() {
    _permsSub?.cancel();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_isOwner) return;

    final updatedDaily = DailyData(
      id: widget.daily.id,
      title: widget.daily.title,
      description: _descriptionController.text.trim(),
      privacy: _selectedPrivacy,
      keywords: _selectedTags.toList(),
      managementTiers: widget.daily.managementTiers,
      icon: widget.daily.icon,
      iconColor: widget.daily.iconColor,
      customIconPath: widget.daily.customIconPath,
      invitedFriendIds: widget.daily.invitedFriendIds,
      foundingMemberIds: widget.daily.foundingMemberIds,
      createdAt: widget.daily.createdAt,
      isPinned: widget.daily.isPinned,
      tierAssignments: widget.daily.tierAssignments,
      tierPrivileges: widget.daily.tierPrivileges,
      // The prompt editor was removed from this screen (a scheduling
      // section is replacing it), so this carries the existing prompt
      // through untouched — otherwise saving would wipe it.
      dailyEntryPrompt: widget.daily.dailyEntryPrompt,
      titleFont: widget.daily.titleFont,
      creatorUid: widget.daily.creatorUid,
    );

    await DailyList.updateDaily(updatedDaily);
    widget.onSave(updatedDaily);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Changes saved for everyone!'),
          backgroundColor: _dailyColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_perms == null) {
      return Center(
        child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))),
      );
    }

    return Column(
      children: [
        if (!_isOwner)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: kc.grey(100),
            child: Row(
              children: [
                Icon(_canSchedule ? Icons.shield_outlined : Icons.lock_outline,
                    size: 16, color: kc.grey(700)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _canSchedule
                        ? 'As a moderator you can schedule covers and prompts. '
                        'The rest is up to the owner.'
                        : 'Only the owner and moderators can change this Daily.',
                    style: TextStyle(fontSize: 13, color: kc.grey(700)),
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DailyScheduleEditor(
                  daily: widget.daily,
                  // Moderators can schedule too.
                  isOwner: _canSchedule,
                  accentColor: _dailyColor,
                ),
                const SizedBox(height: 28),

                _sectionLabel('Description'),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  enabled: _isOwner,
                  maxLines: 4,
                  maxLength: 200,
                  style: TextStyle(fontSize: 16, color: kManageInk),
                  decoration: _inputDeco('Enter description...'),
                ),
                const SizedBox(height: 24),

                _sectionLabel('Privacy'),
                const SizedBox(height: 12),
                _privacyOption('Public'),
                const SizedBox(height: 12),
                _privacyOption('Private'),
                const SizedBox(height: 24),

                _sectionLabel('Tags'),
                const SizedBox(height: 4),
                Text(
                  'Topics that describe this Daily.',
                  style: TextStyle(fontSize: 13, color: kc.grey(500)),
                ),
                const SizedBox(height: 12),
                _isOwner
                    ? DailyTagPicker(
                  selected: _selectedTags,
                  accentColor: _dailyColor,
                  onToggle: (label) => setState(() {
                    if (_selectedTags.contains(label)) {
                      _selectedTags.remove(label);
                    } else {
                      _selectedTags.add(label);
                    }
                  }),
                )
                    : _readOnlyTags(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        if (_isOwner)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kc.surface,
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
                backgroundColor: _dailyColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Save Changes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Widget _readOnlyTags() {
    if (_selectedTags.isEmpty) {
      return Text('No tags set.',
          style: TextStyle(color: kc.grey(500), fontSize: 14));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _selectedTags.map((label) {
        final tag = kDailyTags.firstWhere(
              (t) => t['label'] == label,
          orElse: () => {'label': label, 'emoji': '🏷️'},
        );
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _dailyColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: _dailyColor.withOpacity(0.4), width: 1.5),
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
                      color: _dailyColor)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _privacyOption(String value) {
    final selected = _selectedPrivacy == value;
    return GestureDetector(
      onTap: _isOwner ? () => setState(() => _selectedPrivacy = value) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kc.grey(100),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _dailyColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              color: selected ? _dailyColor : kc.grey(400),
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: kManageInk)),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w600, color: kManageInk),
  );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: kc.grey(400), fontSize: 16),
    filled: true,
    fillColor: _isOwner ? kc.grey(100) : kc.grey(50),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _dailyColor, width: 2)),
    disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none),
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}