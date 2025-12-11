import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'DailyList.dart';

class RolePrivilegesScreen extends StatefulWidget {
  final String tierName;
  final int tierIndex;
  final DailyData daily;

  const RolePrivilegesScreen({
    Key? key,
    required this.tierName,
    required this.tierIndex,
    required this.daily,
  }) : super(key: key);

  @override
  State<RolePrivilegesScreen> createState() => _RolePrivilegesScreenState();
}

class _RolePrivilegesScreenState extends State<RolePrivilegesScreen> {
  // Map to track checkbox states
  late Map<String, bool> _privileges;

  final List<String> _privilegesList = [
    'Invite Members',
    'Remove Members',
    'Ban Members',
    'Assign Roles',
    'Edit Daily Settings',
    'Delete Daily',
    'View History',
    'Post Content',
    'Delete Content',
    'Pin Messages',
    'Manage Roles',
    'View Analytics',
    'Send Announcements',
    'Manage Keywords',
    'Change Privacy',
  ];

  @override
  void initState() {
    super.initState();
    _loadPrivileges();
  }

  void _loadPrivileges() {
    // Load existing privileges or create default (all false)
    if (widget.daily.tierPrivileges != null &&
        widget.daily.tierPrivileges!.containsKey(widget.tierIndex)) {
      _privileges = Map<String, bool>.from(widget.daily.tierPrivileges![widget.tierIndex]!);
    } else {
      _privileges = {};
      for (var privilege in _privilegesList) {
        _privileges[privilege] = false;
      }
    }
  }

  Future<void> _savePrivileges() async {
    // Update the daily with new privileges
    final updatedTierPrivileges = Map<int, Map<String, bool>>.from(
      widget.daily.tierPrivileges ?? {},
    );
    updatedTierPrivileges[widget.tierIndex] = Map<String, bool>.from(_privileges);

    final updatedDaily = DailyData(
      id: widget.daily.id,
      title: widget.daily.title,
      description: widget.daily.description,
      privacy: widget.daily.privacy,
      keywords: widget.daily.keywords,
      managementTiers: widget.daily.managementTiers,
      icon: widget.daily.icon,
      iconColor: widget.daily.iconColor,
      customIconPath: widget.daily.customIconPath,
      invitedFriendIds: widget.daily.invitedFriendIds,
      createdAt: widget.daily.createdAt,
      isPinned: widget.daily.isPinned,
      tierAssignments: widget.daily.tierAssignments,
      tierPrivileges: updatedTierPrivileges,
    );

    await DailyList.updateDaily(updatedDaily);
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
        title: Text(
          '${widget.tierName} Privileges',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _privilegesList.length,
        itemBuilder: (context, index) {
          final privilege = _privilegesList[index];
          final isChecked = _privileges[privilege] ?? false;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey[300]!,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: CheckboxListTile(
              value: isChecked,
              onChanged: (bool? value) {
                setState(() {
                  _privileges[privilege] = value ?? false;
                });
                _savePrivileges();
              },
              title: Text(
                privilege,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              activeColor: Colors.cyan,
              checkColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              controlAffinity: ListTileControlAffinity.leading,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        },
      ),
    );
  }
}
