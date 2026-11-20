import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Opening a Daily from its cover takes you to the post the cover came
/// from, once. After that (or if you'd already seen that post), the Daily
/// opens at the newest messages like normal.
///
/// Remembers, per Daily, the last cover post you were taken to. Kept on the
/// phone and loaded at launch ([load], from main.dart), so deciding is
/// instant when a card is tapped.
class CoverJump {
  CoverJump._();

  static const String _prefsKey = 'cover_jump_seen_v1';
  static const int _maxKept = 300;

  // dailyId -> message id of the cover post already seen.
  static Map<String, String> _seen = {};
  static Future<void>? _loading;

  static Future<void> load() {
    return _loading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw != null) {
          _seen = Map<String, String>.from(jsonDecode(raw) as Map);
        }
      } catch (_) {}
    }();
  }

  /// Should opening this Daily jump to [messageId]?
  static bool shouldJump(String dailyId, String? messageId) =>
      messageId != null && messageId.isNotEmpty && _seen[dailyId] != messageId;

  /// Seen it: next time this Daily opens at the bottom (until a new cover).
  static Future<void> markSeen(String dailyId, String messageId) async {
    if (_seen[dailyId] == messageId) return;
    _seen.remove(dailyId); // re-insert at the end (newest)
    _seen[dailyId] = messageId;
    while (_seen.length > _maxKept) {
      _seen.remove(_seen.keys.first);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_seen));
    } catch (_) {}
  }
}