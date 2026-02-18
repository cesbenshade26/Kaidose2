import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'SendDailyMessage.dart';

class SavedItemStorage {
  static const String _savedItemsPrefix = 'saved_items_';
  static final Map<String, List<DailyMessage>> _savedItems = {};
  static final List<VoidCallback> _listeners = [];

  static List<DailyMessage> getSavedItems(String archiveId) {
    return List.unmodifiable(_savedItems[archiveId] ?? []);
  }

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  /// Save an item to a specific archive
  static Future<void> saveItem(String archiveId, DailyMessage message) async {
    if (!_savedItems.containsKey(archiveId)) {
      _savedItems[archiveId] = [];
    }

    // Check if already saved (avoid duplicates)
    final alreadySaved = _savedItems[archiveId]!.any((item) => item.messageId == message.messageId);
    if (alreadySaved) {
      print('Item already saved to this archive');
      return;
    }

    _savedItems[archiveId]!.add(message);
    await _saveToStorage(archiveId);
    _notifyListeners();
    print('Saved item to archive: $archiveId');
  }

  /// Remove an item from an archive
  static Future<void> removeItem(String archiveId, String messageId) async {
    if (_savedItems.containsKey(archiveId)) {
      _savedItems[archiveId]!.removeWhere((item) => item.messageId == messageId);
      await _saveToStorage(archiveId);
      _notifyListeners();
      print('Removed item from archive: $archiveId');
    }
  }

  /// Save items for a specific archive to storage
  static Future<void> _saveToStorage(String archiveId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_savedItemsPrefix$archiveId';
      final items = _savedItems[archiveId] ?? [];
      final itemsJson = items.map((item) => item.toJson()).toList();
      await prefs.setString(key, jsonEncode(itemsJson));
      print('Saved ${items.length} items for archive: $archiveId');
    } catch (e) {
      print('Error saving items: $e');
    }
  }

  /// Load saved items for a specific archive
  static Future<void> loadItemsForArchive(String archiveId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_savedItemsPrefix$archiveId';
      final itemsString = prefs.getString(key);

      if (itemsString != null) {
        final List<dynamic> itemsJson = jsonDecode(itemsString);
        _savedItems[archiveId] = itemsJson.map((json) => DailyMessage.fromJson(json)).toList();
        print('Loaded ${_savedItems[archiveId]!.length} items for archive: $archiveId');
      } else {
        _savedItems[archiveId] = [];
        print('No saved items found for archive: $archiveId');
      }

      _notifyListeners();
    } catch (e) {
      print('Error loading items for archive $archiveId: $e');
      _savedItems[archiveId] = [];
    }
  }

  /// Load all saved items for all archives
  static Future<void> loadAllItems(List<String> archiveIds) async {
    for (var archiveId in archiveIds) {
      await loadItemsForArchive(archiveId);
    }
  }

  /// Clear all items from an archive
  static Future<void> clearArchive(String archiveId) async {
    _savedItems[archiveId] = [];
    await _saveToStorage(archiveId);
    _notifyListeners();
    print('Cleared archive: $archiveId');
  }
}