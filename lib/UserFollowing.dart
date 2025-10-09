import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

class FollowingData {
  final String userId;
  final String username;
  final DateTime followedDate;

  FollowingData({
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

  factory FollowingData.fromJson(Map<String, dynamic> json) {
    return FollowingData(
      userId: json['userId'],
      username: json['username'],
      followedDate: DateTime.parse(json['followedDate']),
    );
  }
}

class UserFollowing {
  static List<FollowingData> _following = [];
  static final List<VoidCallback> _listeners = [];
  static const String _followingFileName = 'user_following_data.json';

  static int get followingCount => _following.length;
  static List<FollowingData> get following => List.unmodifiable(_following);

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    print('UserFollowing: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      listener();
    }
  }

  static Future<void> followUser(String userId, String username) async {
    if (_following.any((f) => f.userId == userId)) {
      print('Already following user $userId');
      return;
    }

    final newFollowing = FollowingData(
      userId: userId,
      username: username,
      followedDate: DateTime.now(),
    );

    _following.add(newFollowing);
    await _saveFollowingToStorage();
    _notifyListeners();
    print('Now following: $username (${_following.length} total)');
  }

  static Future<void> unfollowUser(String userId) async {
    final initialCount = _following.length;
    _following.removeWhere((f) => f.userId == userId);

    if (_following.length < initialCount) {
      await _saveFollowingToStorage();
      _notifyListeners();
      print('Unfollowed user $userId (${_following.length} total)');
    } else {
      print('User $userId not found in following list');
    }
  }

  static bool isFollowing(String userId) {
    return _following.any((f) => f.userId == userId);
  }

  static FollowingData? getFollowing(String userId) {
    try {
      return _following.firstWhere((f) => f.userId == userId);
    } catch (e) {
      return null;
    }
  }

  static Future<void> loadFollowingCountFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_followingFileName');

      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> data = jsonDecode(contents);

        _following = data.map((json) => FollowingData.fromJson(json)).toList();
        print('Following loaded: ${_following.length} users');

        _notifyListeners();
      } else {
        print('No saved following found, starting with empty list');
        _following = [];
      }
    } catch (e) {
      print('Error loading following: $e');
      _following = [];
    }
  }

  static Future<void> _saveFollowingToStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_followingFileName');

      final List<Map<String, dynamic>> data = _following.map((f) => f.toJson()).toList();
      await file.writeAsString(jsonEncode(data));

      print('Following saved: ${_following.length} users');
    } catch (e) {
      print('Error saving following: $e');
    }
  }

  static Future<void> resetFollowing() async {
    _following.clear();
    await _saveFollowingToStorage();
    _notifyListeners();
    print('All following reset');
  }

  static List<FollowingData> getFollowingSortedByDate({bool ascending = false}) {
    final sorted = List<FollowingData>.from(_following);
    sorted.sort((a, b) {
      final comparison = a.followedDate.compareTo(b.followedDate);
      return ascending ? comparison : -comparison;
    });
    return sorted;
  }

  static List<FollowingData> getFollowingSortedByUsername({bool ascending = true}) {
    final sorted = List<FollowingData>.from(_following);
    sorted.sort((a, b) {
      final comparison = a.username.toLowerCase().compareTo(b.username.toLowerCase());
      return ascending ? comparison : -comparison;
    });
    return sorted;
  }
}