import 'package:shared_preferences/shared_preferences.dart';

class SkipCount {
  static const String _skipsUsedKey = 'skips_used_this_week';
  static const String _lastResetDateKey = 'last_skip_reset_date';
  static const int _baseSkips = 3;
  static const int _maxSkips = 6;

  static int _skipsUsedThisWeek = 0;
  static String _lastResetDate = '';

  // Calculate total available skips based on number of dailies
  static int calculateTotalSkips(int numDailies) {
    int baseSkips = _baseSkips;
    int bonusSkips = (numDailies ~/ 2); // Integer division: 1 bonus per 2 dailies
    int totalSkips = baseSkips + bonusSkips;
    return totalSkips.clamp(_baseSkips, _maxSkips); // Min 3, max 6
  }

  // Get remaining skips for the week
  static int getRemainingSkips(int numDailies) {
    int totalSkips = calculateTotalSkips(numDailies);
    int remaining = totalSkips - _skipsUsedThisWeek;
    return remaining.clamp(0, _maxSkips);
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
    final currentWeekStart = _getWeekStartDate(now);
    final currentWeekStartString = currentWeekStart.toIso8601String().split('T')[0];

    if (_lastResetDate != currentWeekStartString) {
      // New week! Reset skips
      _skipsUsedThisWeek = 0;
      _lastResetDate = currentWeekStartString;
      await _saveToStorage();
      print('New week detected. Skips reset to 0 used.');
    }
  }

  // Get the Monday of the current week (week starts on Monday)
  static DateTime _getWeekStartDate(DateTime date) {
    // Get Monday of current week
    int daysFromMonday = date.weekday - DateTime.monday;
    if (daysFromMonday < 0) daysFromMonday += 7;

    DateTime monday = date.subtract(Duration(days: daysFromMonday));
    return DateTime(monday.year, monday.month, monday.day); // Midnight on Monday
  }

  // Save skip data to storage
  static Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_skipsUsedKey, _skipsUsedThisWeek);
      await prefs.setString(_lastResetDateKey, _lastResetDate);
    } catch (e) {
      print('Error saving skip data: $e');
    }
  }

  // Load skip data from storage
  static Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _skipsUsedThisWeek = prefs.getInt(_skipsUsedKey) ?? 0;
      _lastResetDate = prefs.getString(_lastResetDateKey) ?? '';

      // Check if we need to reset for new week
      await checkAndResetIfNewWeek();

      print('Loaded skip data: $_skipsUsedThisWeek used this week');
    } catch (e) {
      print('Error loading skip data: $e');
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
}