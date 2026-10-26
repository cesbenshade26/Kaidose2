import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'DailyList.dart';
import 'DailyData.dart';
import 'FeedService.dart';
import 'SearchService.dart';
import 'InsideDaily.dart';
import 'daily_join_request_service.dart';
import 'DailyMembershipService.dart';

/// Dailies in Search. Typed queries are ranked by how well they match AND how
/// well they fit the user's feed profile (see SearchService); with nothing
/// typed it shows Dailies suggested from the user's taste.
///
/// [embedded] renders a plain Column of at most [limit] cards (for the All
/// tab) instead of a scrolling list, with an optional [onSeeAll].
class DailySearchWidget extends StatefulWidget {
  final String searchQuery;

  /// True when Search is its own pushed screen, so opening a result first
  /// closes it. False in the Search tab, where there is nothing to close.
  final bool closeSearchOnOpen;

  final bool embedded;
  final int limit;
  final VoidCallback? onSeeAll;

  const DailySearchWidget({
    Key? key,
    required this.searchQuery,
    this.closeSearchOnOpen = true,
    this.embedded = false,
    this.limit = 4,
    this.onSeeAll,
  }) : super(key: key);

  @override
  State<DailySearchWidget> createState() => _DailySearchWidgetState();
}

class _DailySearchWidgetState extends State<DailySearchWidget> {
  List<DailyData> _searchResults = [];
  bool _isLoading = true;
  int _requestId = 0; // drops answers to outdated keystrokes
  VoidCallback? _dailyListListener;

  final DailyJoinRequestService _joinRequestService = DailyJoinRequestService();
  final Set<String> _myDailyIds = {};
  final Set<String> _pendingJoinDailyIds = {};
  final Set<String> _addingDailyIds = {};

  @override
  void initState() {
    super.initState();
    _filterSearch();
    _loadMembershipInfo();

    _dailyListListener = () {
      if (mounted) {
        _loadMembershipInfo();
        _filterSearch();
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

  /// Every Daily the user already owns or has joined, so they get no Join
  /// button on those.
  void _loadMembershipInfo() {
    _myDailyIds
      ..clear()
      ..addAll(DailyList.dailies.map((d) => d.id));
    if (mounted) setState(() {});
  }

  Future<void> _filterSearch() async {
    final id = ++_requestId;
    final query = widget.searchQuery.trim();
    try {
      final results = query.isEmpty
          ? await SearchService.suggestedDailies(
          limit: widget.embedded ? widget.limit : 12)
          : await SearchService.searchDailies(query);
      if (!mounted || id != _requestId) return;
      setState(() {
        _searchResults = results.map((r) => r.daily).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('DailySearchWidget: search error: $e');
      if (mounted && id == _requestId) setState(() => _isLoading = false);
    }
  }

  void _openDaily(DailyData daily) {
    final isMine = _myDailyIds.contains(daily.id);
    if (daily.privacy != 'Public' && !isMine) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This Daily is private — request to join to see it'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    FeedService.recordInteraction(daily);
    if (widget.closeSearchOnOpen) Navigator.pop(context);
    // Not in the user's Dailies → InsideDaily treats them as a guest.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => InsideDaily(daily: daily)),
    );
  }

  Future<void> _addPublicDaily(DailyData daily) async {
    if (_addingDailyIds.contains(daily.id)) return;
    setState(() => _addingDailyIds.add(daily.id));

    final result = await DailyMembershipService.addToMyDailies(daily);
    if (!mounted) return;

    final ok = result['success'] == true;
    setState(() {
      _addingDailyIds.remove(daily.id);
      if (ok) _myDailyIds.add(daily.id);
    });
    if (ok) {
      FeedService.recordInteraction(daily);
      SearchService.invalidate();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Added "${daily.title}" to My Dailies'
            : (result['error']?.toString() ?? 'Could not add')),
        backgroundColor: ok ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
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
    final typed = widget.searchQuery.trim().isNotEmpty;

    if (widget.embedded) {
      if (_isLoading && _searchResults.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
              child: CircularProgressIndicator(color: Colors.cyan, strokeWidth: 2)),
        );
      }
      if (_searchResults.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            typed ? 'No Dailies match' : 'Nothing to suggest yet',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        );
      }
      final shown = _searchResults.take(widget.limit).toList();
      return Column(
        children: [
          ...shown.map(_buildDailyCard),
          if (widget.onSeeAll != null && _searchResults.length > shown.length)
            TextButton(
              onPressed: widget.onSeeAll,
              child: Text('See all ${_searchResults.length} Dailies',
                  style: const TextStyle(
                      color: Colors.cyan, fontWeight: FontWeight.w600)),
            ),
        ],
      );
    }

    if (_isLoading && _searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }
    if (_searchResults.isEmpty) {
      return typed
          ? _centerMessage(Icons.search_off, 'No Results Found',
          'Try different words — Dailies are matched on title, topic and description')
          : _centerMessage(Icons.explore_outlined, 'Nothing to suggest yet',
          'Search for a Daily by title, topic or description');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _searchResults.length + (typed ? 0 : 1),
      itemBuilder: (context, index) {
        if (!typed) {
          if (index == 0) return _sectionTitle('Suggested for you');
          return _buildDailyCard(_searchResults[index - 1]);
        }
        return _buildDailyCard(_searchResults[index]);
      },
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12, left: 2),
    child: Text(text,
        style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.grey[800])),
  );

  Widget _centerMessage(IconData icon, String title, String body) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(body,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyCard(DailyData daily) {
    final isMine = _myDailyIds.contains(daily.id);
    final isPending = _pendingJoinDailyIds.contains(daily.id);
    final isAdding = _addingDailyIds.contains(daily.id);
    final isPublic = daily.privacy == 'Public';
    final showActionButton = !isMine;

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
                    color: Color(daily.iconColor ?? 0xFF00BCD4)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: daily.customIconPath != null &&
                      File(daily.customIconPath!).existsSync()
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(daily.customIconPath!),
                        fit: BoxFit.cover),
                  )
                      : Icon(daily.icon,
                      color: Color(daily.iconColor ?? 0xFF00BCD4),
                      size: 32),
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87),
                            ),
                          ),
                          Icon(
                            isPublic ? Icons.public : Icons.lock_outline,
                            size: 14,
                            color: Colors.grey[400],
                          ),
                          if (daily.isPinned)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                  color: Colors.cyan, shape: BoxShape.circle),
                              child: const Icon(Icons.push_pin,
                                  size: 14, color: Colors.white),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        daily.description,
                        style:
                        TextStyle(fontSize: 14, color: Colors.grey[700]),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        _formatDate(daily.createdAt),
                        style:
                        TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Add to My Dailies / Request to Join
            if (showActionButton) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: isPublic
                    ? ElevatedButton.icon(
                  onPressed:
                  isAdding ? null : () => _addPublicDaily(daily),
                  icon: isAdding
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                      : const Icon(Icons.add, size: 18),
                  label: const Text('Add to My Dailies'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )
                    : OutlinedButton.icon(
                  onPressed: () => _requestToJoinPrivateDaily(daily),
                  icon: const Icon(Icons.lock_outline, size: 16),
                  label: const Text('Request to Join'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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