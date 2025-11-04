import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'UserFollowers.dart';
import 'UserFollowing.dart';

class FriendData {
  final String userId;
  final String username;
  final String? profilePicPath;
  final DateTime addedDate;
  final bool isFollower;
  final bool isFollowing;

  FriendData({
    required this.userId,
    required this.username,
    this.profilePicPath,
    required this.addedDate,
    required this.isFollower,
    required this.isFollowing,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'profilePicPath': profilePicPath,
      'addedDate': addedDate.toIso8601String(),
      'isFollower': isFollower,
      'isFollowing': isFollowing,
    };
  }

  factory FriendData.fromJson(Map<String, dynamic> json) {
    return FriendData(
      userId: json['userId'],
      username: json['username'],
      profilePicPath: json['profilePicPath'],
      addedDate: DateTime.parse(json['addedDate']),
      isFollower: json['isFollower'] ?? false,
      isFollowing: json['isFollowing'] ?? false,
    );
  }

  // Check if this is a mutual friend (both following and follower)
  bool get isMutual => isFollower && isFollowing;
}

class UserFriends {
  static List<FriendData> _friends = [];
  static final List<VoidCallback> _listeners = [];
  static const String _friendsFileName = 'user_friends_data.json';

  static int get friendsCount => _friends.length;
  static List<FriendData> get friends => List.unmodifiable(_friends);

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    print('UserFriends: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      listener();
    }
  }

  // Initialize friends list by combining followers and following
  static Future<void> initializeFriends() async {
    await loadFriendsFromStorage();
    await _syncWithFollowersAndFollowing();
  }

  // Sync friends list with current followers and following
  static Future<void> _syncWithFollowersAndFollowing() async {
    print('Syncing friends with followers and following...');

    Set<String> existingUserIds = _friends.map((f) => f.userId).toSet();
    List<FriendData> newFriends = [];

    // Add all followers
    for (var follower in UserFollowers.followers) {
      if (!existingUserIds.contains(follower.userId)) {
        newFriends.add(FriendData(
          userId: follower.userId,
          username: follower.username,
          addedDate: follower.followedDate,
          isFollower: true,
          isFollowing: UserFollowing.isFollowing(follower.userId),
        ));
        existingUserIds.add(follower.userId);
      }
    }

    // Add all following
    for (var following in UserFollowing.following) {
      if (!existingUserIds.contains(following.userId)) {
        newFriends.add(FriendData(
          userId: following.userId,
          username: following.username,
          addedDate: following.followedDate,
          isFollower: UserFollowers.isFollower(following.userId),
          isFollowing: true,
        ));
        existingUserIds.add(following.userId);
      }
    }

    if (newFriends.isNotEmpty) {
      _friends.addAll(newFriends);
      await _saveFriendsToStorage();
      _notifyListeners();
      print('Added ${newFriends.length} new friends from sync');
    }

    // Update existing friends' follower/following status
    bool hasChanges = false;
    for (int i = 0; i < _friends.length; i++) {
      final friend = _friends[i];
      final isFollower = UserFollowers.isFollower(friend.userId);
      final isFollowing = UserFollowing.isFollowing(friend.userId);

      if (friend.isFollower != isFollower || friend.isFollowing != isFollowing) {
        _friends[i] = FriendData(
          userId: friend.userId,
          username: friend.username,
          profilePicPath: friend.profilePicPath,
          addedDate: friend.addedDate,
          isFollower: isFollower,
          isFollowing: isFollowing,
        );
        hasChanges = true;
      }
    }

    if (hasChanges) {
      await _saveFriendsToStorage();
      _notifyListeners();
      print('Updated friend statuses');
    }
  }

  // Add a friend manually
  static Future<void> addFriend(String userId, String username, {String? profilePicPath}) async {
    if (_friends.any((f) => f.userId == userId)) {
      print('Friend $userId already exists');
      return;
    }

    final newFriend = FriendData(
      userId: userId,
      username: username,
      profilePicPath: profilePicPath,
      addedDate: DateTime.now(),
      isFollower: UserFollowers.isFollower(userId),
      isFollowing: UserFollowing.isFollowing(userId),
    );

    _friends.add(newFriend);
    await _saveFriendsToStorage();
    _notifyListeners();
    print('Added friend: $username (${_friends.length} total)');
  }

  // Remove a friend
  static Future<void> removeFriend(String userId) async {
    final initialCount = _friends.length;
    _friends.removeWhere((f) => f.userId == userId);

    if (_friends.length < initialCount) {
      await _saveFriendsToStorage();
      _notifyListeners();
      print('Removed friend $userId (${_friends.length} total)');
    }
  }

  // Check if a user is a friend
  static bool isFriend(String userId) {
    return _friends.any((f) => f.userId == userId);
  }

  // Get a specific friend
  static FriendData? getFriend(String userId) {
    try {
      return _friends.firstWhere((f) => f.userId == userId);
    } catch (e) {
      return null;
    }
  }

  // Get only mutual friends (both follower and following)
  static List<FriendData> getMutualFriends() {
    return _friends.where((f) => f.isMutual).toList();
  }

  // Get friends sorted by date
  static List<FriendData> getFriendsSortedByDate({bool ascending = false}) {
    final sorted = List<FriendData>.from(_friends);
    sorted.sort((a, b) {
      final comparison = a.addedDate.compareTo(b.addedDate);
      return ascending ? comparison : -comparison;
    });
    return sorted;
  }

  // Get friends sorted by username
  static List<FriendData> getFriendsSortedByUsername({bool ascending = true}) {
    final sorted = List<FriendData>.from(_friends);
    sorted.sort((a, b) {
      final comparison = a.username.toLowerCase().compareTo(b.username.toLowerCase());
      return ascending ? comparison : -comparison;
    });
    return sorted;
  }

  // Load friends from storage
  static Future<void> loadFriendsFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_friendsFileName');

      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> data = jsonDecode(contents);

        _friends = data.map((json) => FriendData.fromJson(json)).toList();
        print('Friends loaded: ${_friends.length} friends');

        _notifyListeners();
      } else {
        print('No saved friends found, starting with empty list');
        _friends = [];
      }
    } catch (e) {
      print('Error loading friends: $e');
      _friends = [];
    }
  }

  // Save friends to storage
  static Future<void> _saveFriendsToStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_friendsFileName');

      final List<Map<String, dynamic>> data = _friends.map((f) => f.toJson()).toList();
      await file.writeAsString(jsonEncode(data));

      print('Friends saved: ${_friends.length} friends');
    } catch (e) {
      print('Error saving friends: $e');
    }
  }

  // Reset all friends
  static Future<void> resetFriends() async {
    _friends.clear();
    await _saveFriendsToStorage();
    _notifyListeners();
    print('All friends reset');
  }

  // Refresh friends list (call after following/unfollowing or gaining/losing followers)
  static Future<void> refreshFriends() async {
    await _syncWithFollowersAndFollowing();
  }
}