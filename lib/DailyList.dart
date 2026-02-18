import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'DailyData.dart';

class DailyList {
  static final List<DailyData> _dailies = [];
  static final List<VoidCallback> _listeners = [];
  static final Set<String> _viewedTodayIds = {};
  static String _lastViewedDate = '';

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

  static bool hasBeenViewedToday(String dailyId) {
    _checkAndResetViewedIfNewDay();
    return _viewedTodayIds.contains(dailyId);
  }

  static Future<void> markAsViewed(String dailyId) async {
    _checkAndResetViewedIfNewDay();
    _viewedTodayIds.add(dailyId);
    await _saveViewedToStorage();
    _notifyListeners();
  }

  static Future<void> unmarkAsViewed(String dailyId) async {
    _checkAndResetViewedIfNewDay();
    _viewedTodayIds.remove(dailyId);
    await _saveViewedToStorage();
    _notifyListeners();
  }

  static void _checkAndResetViewedIfNewDay() {
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (_lastViewedDate != today) {
      _viewedTodayIds.clear();
      _lastViewedDate = today;
    }
  }

  static Future<void> _saveViewedToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('viewed_dailies_today', _viewedTodayIds.toList());
      await prefs.setString('last_viewed_date', _lastViewedDate);
    } catch (e) {
      print('Error saving viewed dailies: $e');
    }
  }

  static Future<void> _loadViewedFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDate = prefs.getString('last_viewed_date') ?? '';
      final today = DateTime.now().toIso8601String().split('T')[0];

      if (savedDate == today) {
        final viewedList = prefs.getStringList('viewed_dailies_today') ?? [];
        _viewedTodayIds.clear();
        _viewedTodayIds.addAll(viewedList);
        _lastViewedDate = savedDate;
      } else {
        _viewedTodayIds.clear();
        _lastViewedDate = today;
      }
    } catch (e) {
      print('Error loading viewed dailies: $e');
    }
  }

  static Future<void> addDaily(DailyData daily) async {
    _dailies.insert(0, daily);
    await _saveToStorage();
    _notifyListeners();
  }

  static Future<void> updateDaily(DailyData updatedDaily) async {
    final index = _dailies.indexWhere((d) => d.id == updatedDaily.id);
    if (index != -1) {
      _dailies[index] = updatedDaily;
      await _saveToStorage();
      _notifyListeners();
    }
  }

  static Future<void> togglePin(String dailyId) async {
    final index = _dailies.indexWhere((d) => d.id == dailyId);
    if (index != -1) {
      final daily = _dailies[index];

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
        dailyEntryPrompt: daily.dailyEntryPrompt,
      );

      _dailies[index] = updatedDaily;

      final pinned = _dailies.where((d) => d.isPinned).toList();
      final unpinned = _dailies.where((d) => !d.isPinned).toList();
      _dailies.clear();
      _dailies.addAll([...pinned, ...unpinned]);

      await _saveToStorage();
      _notifyListeners();
    }
  }

  static Future<void> deleteDaily(String dailyId) async {
    _dailies.removeWhere((d) => d.id == dailyId);
    await _saveToStorage();
    _notifyListeners();
  }

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

      await _loadViewedFromStorage();

      _notifyListeners();
    } catch (e) {
      print('Error loading dailies: $e');
    }
  }

  static Future<void> clearAll() async {
    _dailies.clear();
    await _saveToStorage();
    _notifyListeners();
  }
}