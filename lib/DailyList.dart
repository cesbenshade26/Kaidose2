import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'daily_service.dart';

class DailyList {
  static final DailyService _dailyService = DailyService();
  static final List<VoidCallback> _listeners = [];

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

  // Get dailies stream
  static Stream<List<DailyData>> getDailiesStream() {
    return _dailyService.getUserDailies();
  }

  // Add daily
  static Future<void> addDaily(DailyData daily) async {
    await _dailyService.addDaily(daily);
    _notifyListeners();
  }

  // Update daily
  static Future<void> updateDaily(DailyData updatedDaily) async {
    await _dailyService.updateDaily(updatedDaily);
    _notifyListeners();
  }

  // Toggle pin
  static Future<void> togglePin(String dailyId) async {
    await _dailyService.togglePin(dailyId);
    _notifyListeners();
  }

  // Delete daily
  static Future<void> deleteDaily(String dailyId) async {
    await _dailyService.deleteDaily(dailyId);
    _notifyListeners();
  }

  // Get daily by ID
  static Future<DailyData?> getDailyById(String dailyId) async {
    return await _dailyService.getDailyById(dailyId);
  }

  // Mark as viewed
  static Future<void> markAsViewed(String dailyId) async {
    await _dailyService.markAsViewedToday(dailyId);
    _notifyListeners();
  }

  // Unmark as viewed
  static Future<void> unmarkAsViewed(String dailyId) async {
    await _dailyService.unmarkAsViewedToday(dailyId);
    _notifyListeners();
  }

  // Check if viewed
  static Future<bool> hasBeenViewedToday(String dailyId) async {
    return await _dailyService.hasBeenViewedToday(dailyId);
  }

  // Get viewed dailies stream
  static Stream<Set<String>> getViewedDailiesStream() {
    return _dailyService.getViewedDailiesToday();
  }

  // Legacy compatibility - these are no longer needed but kept for backward compatibility
  static List<DailyData> dailies = [];
  static List<DailyData> get pinnedDailies => [];
  static List<DailyData> get unpinnedDailies => [];
  static Future<void> loadFromStorage() async {}
  static Future<void> clearAll() async {}
}