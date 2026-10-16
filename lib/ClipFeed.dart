import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple persisted preferences for the Clips feed. Currently just one
/// toggle — whether the feed should only show clips from friends — but
/// this is the natural home for future feed-level settings, as opposed to
/// per-clip actions like hiding or reporting a single clip (which this is
/// deliberately not — no Interested/Not Interested, no Report, for now).
class ClipFeedPreferences {
  static const String _friendsOnlyKey = 'clip_feed_friends_only';
  static bool friendsOnly = false;
  static final List<VoidCallback> _listeners = [];

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static void _notifyListeners() {
    for (final l in _listeners) {
      try {
        l();
      } catch (e) {
        print('ClipFeedPreferences: listener error: $e');
      }
    }
  }

  /// Load the saved preference. Call once, e.g. when the Clips tab first
  /// loads.
  static Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      friendsOnly = prefs.getBool(_friendsOnlyKey) ?? false;
      _notifyListeners();
    } catch (e) {
      print('ClipFeedPreferences: load error: $e');
    }
  }

  static Future<void> setFriendsOnly(bool value) async {
    friendsOnly = value;
    _notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_friendsOnlyKey, value);
    } catch (e) {
      print('ClipFeedPreferences: save error: $e');
    }
  }
}

/// Opens the Clips feed preferences sheet — replaces the old "..." menu
/// on ClipSideBar. This is about the feed as a whole (what it shows and
/// why), not per-clip actions.
Future<void> showClipFeedPreferencesSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const ClipFeedPreferencesSheet(),
  );
}

class ClipFeedPreferencesSheet extends StatefulWidget {
  const ClipFeedPreferencesSheet({Key? key}) : super(key: key);

  @override
  State<ClipFeedPreferencesSheet> createState() => _ClipFeedPreferencesSheetState();
}

class _ClipFeedPreferencesSheetState extends State<ClipFeedPreferencesSheet> {
  @override
  void initState() {
    super.initState();
    ClipFeedPreferences.loadFromStorage().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Feed Preferences',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close, color: Colors.grey[600], size: 22),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEEEEEE)),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Your feed shows clips from other Kaidose users, newest first.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),

            SwitchListTile(
              value: ClipFeedPreferences.friendsOnly,
              onChanged: (val) {
                setState(() {
                  ClipFeedPreferences.setFriendsOnly(val);
                });
              },
              title: const Text(
                'Only show clips from friends',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              subtitle: Text(
                "Hide clips from people you don't follow",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              activeColor: Colors.cyan,
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}