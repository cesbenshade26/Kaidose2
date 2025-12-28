import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'DailyData.dart';

class DailyList {
  static final List<DailyData> _dailies = [];
  static final List<VoidCallback> _listeners = [];

  static List<DailyData> get dailies => List.unmodifiable(_dailies);

  static List<DailyData> get pinnedDailies =>
      _dailies.where((d) => d.isPinned).toList();

  static List<DailyData> get unpinnedDailies =>
      _dailies.where((d) => !d.isPinned).toList();

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

  // Add a new daily
  static Future<void> addDaily(DailyData daily) async {
    _dailies.insert(0, daily); // Add to beginning of list
    await _saveToStorage();
    _notifyListeners();
  }

  // Update an existing daily
  static Future<void> updateDaily(DailyData updatedDaily) async {
    final index = _dailies.indexWhere((d) => d.id == updatedDaily.id);
    if (index != -1) {
      _dailies[index] = updatedDaily;
      await _saveToStorage();
      _notifyListeners();
    }
  }

  // Toggle pin status
  static Future<void> togglePin(String dailyId) async {
    final index = _dailies.indexWhere((d) => d.id == dailyId);
    if (index != -1) {
      final daily = _dailies[index];

      // Create a new DailyData with toggled isPinned
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
        invitedFriendIds: daily.invitedFriendIds,
        foundingMemberIds: daily.foundingMemberIds,
        createdAt: daily.createdAt,
        isPinned: !daily.isPinned,
        tierAssignments: daily.tierAssignments,
        tierPrivileges: daily.tierPrivileges,
      );

      _dailies[index] = updatedDaily;

      // Re-sort: pinned first, then unpinned (maintaining their relative order)
      final pinned = _dailies.where((d) => d.isPinned).toList();
      final unpinned = _dailies.where((d) => !d.isPinned).toList();
      _dailies.clear();
      _dailies.addAll([...pinned, ...unpinned]);

      await _saveToStorage();
      _notifyListeners();
    }
  }

  // Delete a daily
  static Future<void> deleteDaily(String dailyId) async {
    _dailies.removeWhere((d) => d.id == dailyId);
    await _saveToStorage();
    _notifyListeners();
  }

  // Save to storage
  static Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dailiesJson = _dailies.map((d) => d.toJson()).toList();
      await prefs.setString('published_dailies', jsonEncode(dailiesJson));
      print('Saved ${_dailies.length} dailies to storage');
    } catch (e) {
      print('Error saving dailies: $e');
    }
  }

  // Load from storage
  static Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dailiesString = prefs.getString('published_dailies');

      if (dailiesString != null) {
        final List<dynamic> dailiesJson = jsonDecode(dailiesString);
        _dailies.clear();
        _dailies.addAll(dailiesJson.map((json) => DailyData.fromJson(json)));
        print('Loaded ${_dailies.length} dailies from storage');
      } else {
        print('No saved dailies found');
      }

      _notifyListeners();
    } catch (e) {
      print('Error loading dailies: $e');
    }
  }

  // Clear all dailies (for testing)
  static Future<void> clearAll() async {
    _dailies.clear();
    await _saveToStorage();
    _notifyListeners();
  }
}