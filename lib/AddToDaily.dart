import 'package:flutter/material.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'dart:io';
import 'NewDaily.dart';

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
  Set<String> _pendingInvites = {};
  VoidCallback? _dailyListListener;

  @override
  void initState() {
    super.initState();
    _loadDailies();
    _searchController.addListener(_filterDailies);
    _dailyListListener = () {
      if (mounted) _loadDailies();
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
      _filteredDailies = query.isEmpty
          ? List.from(_allDailies)
          : _allDailies.where((daily) {
        return daily.title.toLowerCase().contains(query) ||
            daily.description.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _inviteFriendToDaily(DailyData daily) async {
    if (daily.invitedFriendIds.contains(widget.friendName)) return;

    final updatedInvitedFriends = List<String>.from(daily.invitedFriendIds)..add(widget.friendName);
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
      dailyEntryPrompt: daily.dailyEntryPrompt,
    );

    await DailyList.updateDaily(updatedDaily);
    setState(() => _pendingInvites.add(daily.id));
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
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.friendName,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NewDailyScreen(),
                  ),
                );
              },
              child: const Text(
                "Create New",
                style: TextStyle(
                  color: Colors.cyan,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search dailies...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _filteredDailies.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filteredDailies.length,
              itemBuilder: (context, index) => _buildDailyItem(_filteredDailies[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "No Dailies found",
            style: TextStyle(color: Colors.grey[600], fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyItem(DailyData daily) {
    final isPending = _pendingInvites.contains(daily.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Color(daily.iconColor ?? 0xFF00BCD4).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: daily.customIconPath != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(daily.customIconPath!),
                fit: BoxFit.cover,
              ),
            )
                : Icon(
              daily.icon,
              color: Color(daily.iconColor ?? 0xFF00BCD4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  daily.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  daily.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: isPending ? null : () => _inviteFriendToDaily(daily),
            style: ElevatedButton.styleFrom(
              backgroundColor: isPending ? Colors.grey[300] : Colors.cyan,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              isPending ? "Pending" : "Invite",
              style: TextStyle(
                color: isPending ? Colors.black54 : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}