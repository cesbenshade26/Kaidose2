import 'package:flutter/material.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'dart:io';

class AddToDailyScreen extends StatefulWidget {
  final String friendName;

  const AddToDailyScreen({Key? key, required this.friendName}) : super(key: key);

  @override
  State<AddToDailyScreen> createState() => _AddToDailyScreenState();
}

class _AddToDailyScreenState extends State<AddToDailyScreen> {
  List<DailyData> _allDailies = [];
  List<DailyData> _filteredDailies = [];
  final TextEditingController _searchController = TextEditingController();
  Set<String> _pendingInvites = {}; // Track which dailies have pending invites for this friend
  VoidCallback? _dailyListListener;

  @override
  void initState() {
    super.initState();
    _loadDailies();

    _searchController.addListener(_filterDailies);

    _dailyListListener = () {
      if (mounted) {
        _loadDailies();
      }
    };

    DailyList.addListener(_dailyListListener!);
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_dailyListListener != null) {
      DailyList.removeListener(_dailyListListener!);
    }
    super.dispose();
  }

  void _loadDailies() {
    setState(() {
      _allDailies = DailyList.dailies;
      _filteredDailies = List.from(_allDailies);

      // Check which dailies already have this friend invited
      for (var daily in _allDailies) {
        if (daily.invitedFriendIds.contains(widget.friendName)) {
          _pendingInvites.add(daily.id);
        }
      }
    });
  }

  void _filterDailies() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredDailies = List.from(_allDailies);
      } else {
        _filteredDailies = _allDailies.where((daily) {
          return daily.title.toLowerCase().contains(query) ||
              daily.description.toLowerCase().contains(query) ||
              daily.keywords.any((keyword) => keyword.toLowerCase().contains(query));
        }).toList();
      }
    });
  }

  Future<void> _inviteFriendToDaily(DailyData daily) async {
    // Check if already invited
    if (daily.invitedFriendIds.contains(widget.friendName)) {
      return;
    }

    // Add friend to invited list
    final updatedInvitedFriends = List<String>.from(daily.invitedFriendIds);
    updatedInvitedFriends.add(widget.friendName);

    final updatedDaily = DailyData(
      id: daily.id,
      title: daily.title,
      description: daily.description,
      privacy: daily.privacy,
      keywords: daily.keywords,
      managementTiers: daily.managementTiers,
      icon: daily.icon,
      iconColor: daily.iconColor,
      customIconPath: daily.customIconPath,
      invitedFriendIds: updatedInvitedFriends,
      createdAt: daily.createdAt,
      isPinned: daily.isPinned,
      tierAssignments: daily.tierAssignments,
      tierPrivileges: daily.tierPrivileges,
    );

    await DailyList.updateDaily(updatedDaily);

    setState(() {
      _pendingInvites.add(daily.id);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.friendName} invited to ${daily.title}!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add to Daily',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.friendName,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search dailies...',
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.grey[600],
                  size: 24,
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
            ),
          ),

          // Dailies list
          Expanded(
            child: _filteredDailies.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _searchController.text.isEmpty
                        ? Icons.photo_camera_outlined
                        : Icons.search_off,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchController.text.isEmpty
                        ? 'No Dailies Yet'
                        : 'No Results Found',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      _searchController.text.isEmpty
                          ? 'Create a daily to invite ${widget.friendName}'
                          : 'Try searching for a different daily',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filteredDailies.length,
              itemBuilder: (context, index) {
                final daily = _filteredDailies[index];
                final isPending = _pendingInvites.contains(daily.id);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
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
                        blurRadius: 3,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Daily icon
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Color(daily.iconColor ?? 0xFF00BCD4)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: daily.customIconPath != null &&
                            File(daily.customIconPath!)
                                .existsSync()
                            ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(daily.customIconPath!),
                            fit: BoxFit.cover,
                          ),
                        )
                            : Icon(
                          daily.icon,
                          color: Color(
                              daily.iconColor ?? 0xFF00BCD4),
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Daily info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              daily.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              daily.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Invite button
                      GestureDetector(
                        onTap: isPending
                            ? null
                            : () => _inviteFriendToDaily(daily),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isPending
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.cyan,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isPending
                                  ? Colors.orange
                                  : Colors.cyan,
                              width: isPending ? 1.5 : 0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isPending) ...[
                                Icon(
                                  Icons.schedule,
                                  size: 16,
                                  color: Colors.orange[700],
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                isPending ? 'Pending' : 'Invite',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isPending
                                      ? Colors.orange[700]
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}