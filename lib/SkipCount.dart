import 'package:shared_preferences/shared_preferences.dart';

class SkipCount {
  static const String _skipsUsedKey = 'skips_used_this_week';
  static const String _lastResetDateKey = 'last_skip_reset_date';
  static const String _firstUseDate = 'skip_system_first_use_date';
  static const int _baseSkips = 3;
  static const int _maxSkips = 6;

  static int _skipsUsedThisWeek = 0;
  static DateTime? _lastResetDate;
  static DateTime? _userStartDate;

  // Calculate total available skips based on number of dailies
  static int calculateTotalSkips(int numDailies) {
    int baseSkips = _baseSkips;
    int bonusSkips = (numDailies ~/ 2); // 1 bonus per 2 dailies
    int totalSkips = baseSkips + bonusSkips;
    return totalSkips.clamp(_baseSkips, _maxSkips); // Min 3, max 6
  }

  // Get remaining skips for the week
  static int getRemainingSkips(int numDailies) {
    int totalSkips = calculateTotalSkips(numDailies);
    int remaining = totalSkips - _skipsUsedThisWeek;
    return remaining.clamp(0, totalSkips);
  }

  // Use a skip
  static Future<bool> useSkip(int numDailies) async {
    int remaining = getRemainingSkips(numDailies);

    if (remaining <= 0) {
      return false; // No skips available
    }

    _skipsUsedThisWeek++;
    await _saveToStorage();
    return true;
  }

  // Check if a new week has started and reset if needed
  static Future<void> checkAndResetIfNewWeek() async {
    final now = DateTime.now();

    // Initialize user start date if not set
    if (_userStartDate == null) {
      _userStartDate = DateTime(now.year, now.month, now.day);
      await _saveToStorage();
    }

    final currentWeekStart = _getWeekStartDate(now, _userStartDate!);

    // Check if we need to reset
    if (_lastResetDate == null || currentWeekStart.isAfter(_lastResetDate!)) {
      // New week! Reset skips
      _skipsUsedThisWeek = 0;
      _lastResetDate = currentWeekStart;
      await _saveToStorage();
      print('New week detected. Skips reset to 0 used. Next reset: ${_getNextResetDate()}');
    }
  }

  // Get the week start date based on user's join date
  static DateTime _getWeekStartDate(DateTime now, DateTime userStart) {
    // Calculate days since user started
    int daysSinceStart = now.difference(userStart).inDays;

    // Calculate which week we're in (0-indexed)
    int weekNumber = daysSinceStart ~/ 7;

    // Calculate the start of the current week
    DateTime weekStart = userStart.add(Duration(days: weekNumber * 7));

    return DateTime(weekStart.year, weekStart.month, weekStart.day);
  }

  // Get next reset date (for display)
  static DateTime _getNextResetDate() {
    if (_userStartDate == null) {
      return DateTime.now();
    }

    final now = DateTime.now();
    final currentWeekStart = _getWeekStartDate(now, _userStartDate!);
    return currentWeekStart.add(const Duration(days: 7));
  }

  // Save skip data to storage
  static Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_skipsUsedKey, _skipsUsedThisWeek);

      if (_lastResetDate != null) {
        await prefs.setString(_lastResetDateKey, _lastResetDate!.toIso8601String());
      }

      if (_userStartDate != null) {
        await prefs.setString(_firstUseDate, _userStartDate!.toIso8601String());
      }

      print('Saved: $_skipsUsedThisWeek used, reset date: $_lastResetDate');
    } catch (e) {
      print('Error saving skip data: $e');
    }
  }

  // Load skip data from storage
  static Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _skipsUsedThisWeek = prefs.getInt(_skipsUsedKey) ?? 0;

      // MIGRATION: Handle old string format "2026-04-20"
      final lastResetStr = prefs.getString(_lastResetDateKey);
      if (lastResetStr != null && lastResetStr.isNotEmpty) {
        try {
          // Try parsing as full ISO string first
          _lastResetDate = DateTime.parse(lastResetStr);
        } catch (e) {
          // If it's just a date string like "2026-04-20", parse it
          try {
            _lastResetDate = DateTime.parse(lastResetStr + 'T00:00:00');
          } catch (e2) {
            print('Could not parse last reset date, resetting: $lastResetStr');
            _lastResetDate = null;
          }
        }
      }

      final userStartStr = prefs.getString(_firstUseDate);
      if (userStartStr != null && userStartStr.isNotEmpty) {
        try {
          _userStartDate = DateTime.parse(userStartStr);
        } catch (e) {
          try {
            _userStartDate = DateTime.parse(userStartStr + 'T00:00:00');
          } catch (e2) {
            print('Could not parse user start date, resetting: $userStartStr');
            _userStartDate = null;
          }
        }
      }

      // Check if we need to reset for new week
      await checkAndResetIfNewWeek();

      print('Loaded skip data: $_skipsUsedThisWeek used this week, user start: $_userStartDate');
    } catch (e) {
      print('Error loading skip data: $e');
      // Reset to safe defaults
      _skipsUsedThisWeek = 0;
      _lastResetDate = null;
      _userStartDate = null;

      // Clear corrupted data
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_lastResetDateKey);
        await prefs.remove(_firstUseDate);
        await prefs.setInt(_skipsUsedKey, 0);
      } catch (e2) {
        print('Error clearing corrupted skip data: $e2');
      }
    }
  }

  // Get current skips used (for debugging/display)
  static int getSkipsUsed() {
    return _skipsUsedThisWeek;
  }

  // Reset skips (for testing purposes)
  static Future<void> resetSkips() async {
    _skipsUsedThisWeek = 0;
    await _saveToStorage();
  }

  // Get days until next reset (for UI display)
  static int getDaysUntilReset() {
    if (_userStartDate == null) return 0;

    final now = DateTime.now();
    final nextReset = _getNextResetDate();
    final diff = nextReset.difference(now).inDays;
    return diff.clamp(0, 7);
  }
}