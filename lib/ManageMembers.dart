import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'DailyBan.dart';
import 'AssignMemberRole.dart';

class ManageMembers extends StatefulWidget {
  final DailyData daily;

  const ManageMembers({Key? key, required this.daily}) : super(key: key);

  @override
  State<ManageMembers> createState() => _ManageMembersState();
}

class _ManageMembersState extends State<ManageMembers> {
  Map<int, List<String>> _tierAssignments = {};
  final ScrollController _scrollController = ScrollController();
  bool _isDragging = false;
  double _lastDragY = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleDragUpdate(double globalY) {
    if (!_isDragging) return;

    final screenHeight = MediaQuery.of(context).size.height;
    const scrollZoneHeight = 100.0;
    const scrollSpeed = 5.0;

    // Calculate position relative to screen
    final localY = globalY;

    if (localY < scrollZoneHeight + 200) {
      // Scroll up (near top of screen)
      final newOffset = _scrollController.offset - scrollSpeed;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
            newOffset.clamp(0.0, _scrollController.position.maxScrollExtent)
        );
      }
    } else if (localY > screenHeight - scrollZoneHeight) {
      // Scroll down (near bottom of screen)
      final newOffset = _scrollController.offset + scrollSpeed;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
            newOffset.clamp(0.0, _scrollController.position.maxScrollExtent)
        );
      }
    }

    _lastDragY = globalY;
  }

  void _handleMemberDropped(String memberName, int tierIndex) {
    setState(() {
      // Remove member from all tiers first
      _tierAssignments.forEach((key, value) {
        value.remove(memberName);
      });

      // Add to new tier
      if (!_tierAssignments.containsKey(tierIndex)) {
        _tierAssignments[tierIndex] = [];
      }
      _tierAssignments[tierIndex]!.add(memberName);

      _isDragging = false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$memberName assigned to ${widget.daily.managementTiers[tierIndex]}'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    });
  }

  void _enterAssignMode() {
    setState(() {
      AssignMemberRole.enterAssignMode();
    });
  }

  void _exitAssignMode() {
    setState(() {
      AssignMemberRole.exitAssignMode();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: (PointerMoveEvent event) {
        if (_isDragging) {
          _handleDragUpdate(event.position.dy);
        }
      },
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Assign mode banner
                const AssignModeBanner(),
                if (AssignMemberRole.isAssignMode) const SizedBox(height: 16),

                // Invited Friends Section
                Row(
                  children: [
                    Icon(
                      Icons.people,
                      color: Colors.cyan,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Invited Friends',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.daily.invitedFriendIds.length} friend${widget.daily.invitedFriendIds.length != 1 ? 's' : ''} invited',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 16),

                // Friends List
                widget.daily.invitedFriendIds.isEmpty
                    ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey[300]!,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_add_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No friends invited yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Invite friends to join this daily',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
                    : Column(
                  children: widget.daily.invitedFriendIds.map((friendName) {
                    return WiggleMemberCard(
                      memberName: friendName,
                      onDragStarted: () {
                        setState(() {
                          _isDragging = true;
                        });
                      },
                      onDragEnd: () {
                        setState(() {
                          _isDragging = false;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
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
                        child: Row(
                          children: [
                            // Profile picture
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                shape: BoxShape.circle,
                              ),
                              child: ClipOval(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Head circle
                                    Positioned(
                                      top: 12,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                    // Body/shoulders
                                    Positioned(
                                      bottom: -6,
                                      child: Container(
                                        width: 44,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[600],
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(22),
                                            topRight: Radius.circular(22),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Friend info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    friendName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.schedule,
                                              size: 12,
                                              color: Colors.orange[700],
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Pending',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.orange[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Three dots menu
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                color: Colors.grey[600],
                                size: 24,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onSelected: (value) {
                                if (value == 'assign_role') {
                                  _enterAssignMode();
                                } else if (value == 'ban') {
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext dialogContext) => DailyBanDialog(
                                      memberName: friendName,
                                      dailyId: widget.daily.id,
                                    ),
                                  );
                                }
                              },
                              itemBuilder: (BuildContext menuContext) => [
                                const PopupMenuItem<String>(
                                  value: 'assign_role',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.admin_panel_settings_outlined,
                                        size: 20,
                                        color: Colors.black87,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Assign Role',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'ban',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.block,
                                        size: 20,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Ban',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 24),

                // Management Tiers Section
                Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings,
                      color: Colors.cyan,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Management Tiers',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                widget.daily.managementTiers.isEmpty
                    ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey[300]!,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No management tiers',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create tiers to organize members',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.daily.managementTiers.asMap().entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Tier header
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey[300]!,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.cyan,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.cyan.withOpacity(0.3),
                                        spreadRadius: 1,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${entry.key + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.value,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tier ${entry.key + 1}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.admin_panel_settings,
                                  color: Colors.cyan[700],
                                  size: 24,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Text box under tier - now a drop zone
                          WiggleTierDropZone(
                            tierName: entry.value,
                            tierIndex: entry.key,
                            onMemberDropped: _handleMemberDropped,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.people,
                                        color: Colors.grey[600],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _tierAssignments[entry.key]?.isEmpty ?? true
                                              ? 'Members assigned to this tier will appear here'
                                              : 'Assigned members:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                            fontStyle: _tierAssignments[entry.key]?.isEmpty ?? true
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                            fontWeight: _tierAssignments[entry.key]?.isEmpty ?? true
                                                ? FontWeight.normal
                                                : FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_tierAssignments[entry.key]?.isNotEmpty ?? false) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _tierAssignments[entry.key]!.map((memberName) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.cyan.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: Colors.cyan,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                memberName,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    _tierAssignments[entry.key]!.remove(memberName);
                                                  });
                                                },
                                                child: const Icon(
                                                  Icons.close,
                                                  size: 14,
                                                  color: Colors.cyan,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          // Exit assign mode button
          ExitAssignModeButton(
            onExit: _exitAssignMode,
          ),
        ],
      ),
    );
  }
}