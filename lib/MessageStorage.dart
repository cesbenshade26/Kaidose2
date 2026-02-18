import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'SendDailyMessage.dart';

class MessageStorage {
  static const String _messagesPrefix = 'daily_messages_';
  static final List<Function()> _listeners = [];

  static void addListener(Function() listener) => _listeners.add(listener);
  static void removeListener(Function() listener) => _listeners.remove(listener);
  static void _notifyListeners() {
    for (final l in _listeners) l();
  }

  /// Save messages for a specific daily
  static Future<void> saveMessages(String dailyId, List<DailyMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String key = '$_messagesPrefix$dailyId';

      // Convert messages to JSON (includes isLiked and isSaved)
      final List<Map<String, dynamic>> messagesJson = messages.map((msg) => msg.toJson()).toList();
      final String jsonString = json.encode(messagesJson);

      await prefs.setString(key, jsonString);
      print('Saved ${messages.length} messages for daily: $dailyId (with like/save states)');
      _notifyListeners();
    } catch (e) {
      print('Error saving messages: $e');
    }
  }

  /// Load messages for a specific daily
  static Future<List<DailyMessage>> loadMessages(String dailyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String key = '$_messagesPrefix$dailyId';

      final String? jsonString = prefs.getString(key);

      if (jsonString == null) {
        print('No saved messages found for daily: $dailyId');
        return [];
      }

      final List<dynamic> messagesJson = json.decode(jsonString);
      final List<DailyMessage> messages = messagesJson.map((json) => DailyMessage.fromJson(json)).toList();

      print('Loaded ${messages.length} messages for daily: $dailyId');
      return messages;
    } catch (e) {
      print('Error loading messages: $e');
      return [];
    }
  }

  /// Delete all messages for a specific daily
  static Future<void> deleteMessages(String dailyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String key = '$_messagesPrefix$dailyId';

      await prefs.remove(key);
      print('Deleted messages for daily: $dailyId');
    } catch (e) {
      print('Error deleting messages: $e');
    }
  }

  /// Get all daily IDs that have saved messages
  static Future<List<String>> getAllDailyIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Set<String> keys = prefs.getKeys();

      final List<String> dailyIds = keys
          .where((key) => key.startsWith(_messagesPrefix))
          .map((key) => key.replaceFirst(_messagesPrefix, ''))
          .toList();

      return dailyIds;
    } catch (e) {
      print('Error getting daily IDs: $e');
      return [];
    }
  }

  /// Clear all messages (for debugging/testing)
  static Future<void> clearAllMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Set<String> keys = prefs.getKeys();

      for (String key in keys) {
        if (key.startsWith(_messagesPrefix)) {
          await prefs.remove(key);
        }
      }

      print('Cleared all messages');
    } catch (e) {
      print('Error clearing all messages: $e');
    }
  }
}