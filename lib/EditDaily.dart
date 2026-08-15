import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'DailyData.dart';
import 'DailyList.dart';
import 'ManageDaily.dart' show DailyTagPicker, kDailyTags;

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
  late TextEditingController _promptController;
  late String _selectedPrivacy;
  late Set<String> _selectedTags;
  bool _isOwner = false;
  bool _checkingOwnership = true;

  Color get _dailyColor => Color(widget.daily.iconColor ?? 0xFF00BCD4);

  @override
  void initState() {
    super.initState();
    _descriptionController =
        TextEditingController(text: widget.daily.description);
    _promptController =
        TextEditingController(text: widget.daily.dailyEntryPrompt);
    _selectedPrivacy = widget.daily.privacy;
    _selectedTags = Set<String>.from(widget.daily.keywords);
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
          .where('dailyId', isEqualTo: widget.daily.id)
          .where('toUserId', isEqualTo: uid)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();

      final isOwner = invite.docs.isEmpty;
      print('OWNERSHIP (EditDaily): uid=$uid dailyId=${widget.daily.id} inviteFound=${invite.docs.isNotEmpty} isOwner=$isOwner');
      if (mounted) setState(() { _isOwner = isOwner; _checkingOwnership = false; });
    } catch (e) {
      print('EditDaily ownership check error: $e');
      if (mounted) setState(() { _isOwner = false; _checkingOwnership = false; });
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _promptController.dispose();
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
      dailyEntryPrompt: _promptController.text.trim(),
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
    if (_checkingOwnership) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyan),
      );
    }

    return Column(
      children: [
        if (!_isOwner)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.amber[50],
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: Colors.amber[800]),
                const SizedBox(width: 8),
                Text(
                  'Only the owner can edit this Daily.',
                  style: TextStyle(fontSize: 13, color: Colors.amber[800]),
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
                _sectionLabel('Description'),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  enabled: _isOwner,
                  maxLines: 4,
                  maxLength: 200,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                  decoration: _inputDeco('Enter description...'),
                ),
                const SizedBox(height: 24),

                _sectionLabel('Daily Entry Prompt'),
                const SizedBox(height: 12),
                TextField(
                  controller: _promptController,
                  enabled: _isOwner,
                  maxLength: 100,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                  decoration: _inputDeco('Enter a prompt...'),
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
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
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
          style: TextStyle(color: Colors.grey[500], fontSize: 14));
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
          color: Colors.grey[100],
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
              color: selected ? _dailyColor : Colors.grey[400],
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(value,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
        fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
  );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 16),
    filled: true,
    fillColor: _isOwner ? Colors.grey[100] : Colors.grey[50],
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