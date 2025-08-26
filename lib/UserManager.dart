import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// UserManager class to handle user data retrieval
class UserManager {
  static String? _globalUsername;
  static final List<VoidCallback> _listeners = [];

  // Getter
  static String? get globalUsername => _globalUsername;

  // Load username from SharedPreferences
  static Future<void> loadUsernameFromStorage() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      _globalUsername = prefs.getString('kaidose_user');

      print('Username loaded from storage: "$_globalUsername"');

      // Notify all listeners
      for (var listener in _listeners) {
        try {
          listener();
        } catch (e) {
          print('Error calling username listener: $e');
        }
      }
    } catch (e) {
      print('Error loading username: $e');
      _globalUsername = null;
    }
  }

  // Add listener for username changes
  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  // Remove listener
  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  // Force refresh username
  static Future<void> forceRefresh() async {
    print('Force refreshing username...');
    await loadUsernameFromStorage();
  }

  // Update username and notify listeners
  static Future<void> updateUsername(String newUsername) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('kaidose_user', newUsername);

      _globalUsername = newUsername;

      print('Username updated to: "$newUsername"');

      // Notify all listeners
      for (var listener in _listeners) {
        try {
          listener();
        } catch (e) {
          print('Error calling username listener: $e');
        }
      }
    } catch (e) {
      print('Error updating username: $e');
    }
  }

  // Check if user is logged in
  static Future<bool> isUserLoggedIn() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? username = prefs.getString('kaidose_user');
    String? password = prefs.getString('kaidose_pass');
    return username != null && password != null;
  }
}