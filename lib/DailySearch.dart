import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'FeedService.dart';
import 'InsideDaily.dart';
import 'daily_join_request_service.dart';

class DailySearchWidget extends StatefulWidget {
  final String searchQuery;

  const DailySearchWidget({Key? key, required this.searchQuery}) : super(key: key);

  @override
  State<DailySearchWidget> createState() => _DailySearchWidgetState();
}

class _DailySearchWidgetState extends State<DailySearchWidget> {
  List<DailyData> _searchResults = [];
  List<ScoredDaily> _feedResults = [];
  bool _isLoadingFeed = true;
  VoidCallback? _dailyListListener;

  final DailyJoinRequestService _joinRequestService = DailyJoinRequestService();
  final Set<String> _myOwnedDailyIds = {};
  final Set<String> _myMemberDailyIds = {};
  final Set<String> _pendingJoinDailyIds = {};

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _loadMembershipInfo();

    _dailyListListener = () {
      if (mounted) {
        _filterSearch();
        _loadMembershipInfo();
      }
    };
    DailyList.addListener(_dailyListListener!);
  }

  @override
  void dispose() {
    if (_dailyListListener != null) {
      DailyList.removeListener(_dailyListListener!);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(DailySearchWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _filterSearch();
    }
  }

  /// Tracks which dailies the current user already owns or belongs to,
  /// so we don't show a Join button on something they're already in.
  Future<void> _loadMembershipInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _myOwnedDailyIds.clear();
    _myMemberDailyIds.clear();

    for (final daily in DailyList.dailies) {
      if (daily.creatorUid == uid) {
        _myOwnedDailyIds.add(daily.id);
      } else {
        _myMemberDailyIds.add(daily.id);
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _loadFeed() async {
    setState(() => _isLoadingFeed = true);
    try {
      final ranked = await FeedService.getRankedFeed();
      if (mounted) {
        setState(() {
          _feedResults = ranked;
          _isLoadingFeed = false;
        });
      }
    } catch (e) {
      print('DailySearchWidget: feed load error: $e');
      if (mounted) setState(() => _isLoadingFeed = false);
    }
  }

  void _filterSearch() {
    final query = widget.searchQuery.toLowerCase().trim();

    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    final pool = <DailyData>{
      ..._feedResults.map((s) => s.daily),
      ...DailyList.dailies,
    }.toList();

    setState(() {
      _searchResults = pool.where((daily) {
        return daily.title.toLowerCase().contains(query) ||
            daily.description.toLowerCase().contains(query) ||
            daily.keywords.any((tag) => tag.toLowerCase().contains(query));
      }).toList();
    });
  }

  void _openDaily(DailyData daily) {
    FeedService.recordInteraction(daily);
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => InsideDaily(daily: daily)),
    );
  }

  Future<void> _joinPublicDaily(DailyData daily) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailies')
          .doc(daily.id)
          .set({
        ...daily.toFirestoreJson(),
        'creatorUid': daily.creatorUid,
      });

      setState(() => _myMemberDailyIds.add(daily.id));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Joined "${daily.title}"!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('DailySearchWidget: join error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error joining: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _requestToJoinPrivateDaily(DailyData daily) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || daily.creatorUid == null) return;

    try {
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final myUsername = userDoc.data()?['username'] ?? 'Someone';

      final result = await _joinRequestService.sendJoinRequest(
        dailyId: daily.id,
        dailyTitle: daily.title,
        ownerUid: daily.creatorUid!,
        fromUsername: myUsername,
      );

      if (!mounted) return;

      if (result['success']) {
        setState(() => _pendingJoinDailyIds.add(daily.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request sent to join "${daily.title}"'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Could not send request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('DailySearchWidget: request to join error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = widget.searchQuery.trim().isNotEmpty;
    return isSearching ? _buildSearchResults() : _buildFeed();
  }

  // ─── Feed ───────────────────────────────────────────────────────────────────

  Widget _buildFeed() {
    if (_isLoadingFeed) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }

    if (_feedResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Dailies to Discover Yet',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Public Dailies will show up here as people create them',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: Colors.cyan,
      onRefresh: () async {
        await _loadFeed();
        await _loadMembershipInfo();
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _feedResults.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 4),
              child: Text(
                'For You',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                  letterSpacing: 0.5,
                ),
              ),
            );
          }
          final scored = _feedResults[index - 1];
          return _buildDailyCard(scored.daily, matchScore: scored.score);
        },
      ),
    );
  }

  // ─── Search results ─────────────────────────────────────────────────────────

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Results Found',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Try searching with different keywords',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) => _buildDailyCard(_searchResults[index]),
    );
  }

  // ─── Card ───────────────────────────────────────────────────────────────────

  Widget _buildDailyCard(DailyData daily, {double? matchScore}) {
    final isOwned = _myOwnedDailyIds.contains(daily.id);
    final isMember = _myMemberDailyIds.contains(daily.id);
    final isPending = _pendingJoinDailyIds.contains(daily.id);
    final isPublic = daily.privacy == 'Public';
    final showActionButton = !isOwned && !isMember;

    return GestureDetector(
      onTap: () => _openDaily(daily),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: daily.isPinned ? Colors.cyan : Colors.grey[300]!,
            width: daily.isPinned ? 2 : 1,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Color(daily.iconColor ?? 0xFF00BCD4).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: daily.customIconPath != null &&
                      File(daily.customIconPath!).existsSync()
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(daily.customIconPath!), fit: BoxFit.cover),
                  )
                      : Icon(daily.icon, color: Color(daily.iconColor ?? 0xFF00BCD4), size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              daily.title,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
                            ),
                          ),
                          Icon(
                            isPublic ? Icons.public : Icons.lock_outline,
                            size: 14,
                            color: Colors.grey[400],
                          ),
                          if (matchScore != null && matchScore > 0.5)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.cyan.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Match',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.cyan),
                              ),
                            ),
                          if (daily.isPinned)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Colors.cyan, shape: BoxShape.circle),
                              child: const Icon(Icons.push_pin, size: 14, color: Colors.white),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        daily.description,
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (daily.keywords.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: daily.keywords.take(3).map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        _formatDate(daily.createdAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Join / Request to Join button row
            if (showActionButton) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: isPublic
                    ? ElevatedButton.icon(
                  onPressed: () => _joinPublicDaily(daily),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Join'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                )
                    : isPending
                    ? OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.schedule, size: 16),
                  label: const Text('Request Pending'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[500],
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                )
                    : OutlinedButton.icon(
                  onPressed: () => _requestToJoinPrivateDaily(daily),
                  icon: const Icon(Icons.lock_outline, size: 16),
                  label: const Text('Request to Join'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) return 'today';
    if (difference.inDays == 1) return 'yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    }
    final months = (difference.inDays / 30).floor();
    return months == 1 ? '1 month ago' : '$months months ago';
  }
}