import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

class FollowerData {
  final String userId;
  final String username;
  final DateTime followedDate;

  FollowerData({
    required this.userId,
    required this.username,
    required this.followedDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'followedDate': followedDate.toIso8601String(),
    };
  }

  factory FollowerData.fromJson(Map<String, dynamic> json) {
    return FollowerData(
      userId: json['userId'],
      username: json['username'],
      followedDate: DateTime.parse(json['followedDate']),
    );
  }
}

class UserFollowers {
  static List<FollowerData> _followers = [];
  static final List<VoidCallback> _listeners = [];
  static const String _followersFileName = 'user_followers_data.json';

  static int get followersCount => _followers.length;
  static List<FollowerData> get followers => List.unmodifiable(_followers);

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    print('UserFollowers: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      listener();
    }
  }

  // Add a follower
  static Future<void> addFollower(String userId, String username) async {
    // Check if already following
    if (_followers.any((f) => f.userId == userId)) {
      print('User $userId is already a follower');
      return;
    }

    final newFollower = FollowerData(
      userId: userId,
      username: username,
      followedDate: DateTime.now(),
    );

    _followers.add(newFollower);
    await _saveFollowersToStorage();
    _notifyListeners();
    print('Added follower: $username (${_followers.length} total)');
  }

  // Remove a follower
  static Future<void> removeFollower(String userId) async {
    final initialCount = _followers.length;
    _followers.removeWhere((f) => f.userId == userId);

    if (_followers.length < initialCount) {
      await _saveFollowersToStorage();
      _notifyListeners();
      print('Removed follower $userId (${_followers.length} total)');
    } else {
      print('Follower $userId not found');
    }
  }

  // Check if a user is a follower
  static bool isFollower(String userId) {
    return _followers.any((f) => f.userId == userId);
  }

  // Get a specific follower
  static FollowerData? getFollower(String userId) {
    try {
      return _followers.firstWhere((f) => f.userId == userId);
    } catch (e) {
      return null;
    }
  }

  // Load followers from local storage
  static Future<void> loadFollowersCountFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_followersFileName');

      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> data = jsonDecode(contents);

        _followers = data.map((json) => FollowerData.fromJson(json)).toList();
        print('Followers loaded: ${_followers.length} followers');

        _notifyListeners();
      } else {
        print('No saved followers found, starting with empty list');
        _followers = [];
      }
    } catch (e) {
      print('Error loading followers: $e');
      _followers = [];
    }
  }

  // Save followers to local storage
  static Future<void> _saveFollowersToStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_followersFileName');

      final List<Map<String, dynamic>> data = _followers.map((f) => f.toJson()).toList();
      await file.writeAsString(jsonEncode(data));

      print('Followers saved: ${_followers.length} followers');
    } catch (e) {
      print('Error saving followers: $e');
    }
  }

  // Reset all followers
  static Future<void> resetFollowers() async {
    _followers.clear();
    await _saveFollowersToStorage();
    _notifyListeners();
    print('All followers reset');
  }

  // Get followers sorted by date (newest first)
  static List<FollowerData> getFollowersSortedByDate({bool ascending = false}) {
    final sorted = List<FollowerData>.from(_followers);
    sorted.sort((a, b) {
      final comparison = a.followedDate.compareTo(b.followedDate);
      return ascending ? comparison : -comparison;
    });
    return sorted;
  }

  // Get followers sorted by username
  static List<FollowerData> getFollowersSortedByUsername({bool ascending = true}) {
    final sorted = List<FollowerData>.from(_followers);
    sorted.sort((a, b) {
      final comparison = a.username.toLowerCase().compareTo(b.username.toLowerCase());
      return ascending ? comparison : -comparison;
    });
    return sorted;
  }
}