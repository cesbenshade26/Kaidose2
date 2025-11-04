import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

enum LinkStatus {
  pending,    // Request sent, waiting for acceptance
  accepted,   // Request accepted, friend is linked
  rejected    // Request was rejected
}

class LinkedFriend {
  final String name;
  final String? phoneNumber;
  final String? userId; // For when you have a database
  final DateTime linkedDate;
  final LinkStatus status;

  LinkedFriend({
    required this.name,
    this.phoneNumber,
    this.userId,
    required this.linkedDate,
    this.status = LinkStatus.pending,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      'userId': userId,
      'linkedDate': linkedDate.toIso8601String(),
      'status': status.toString().split('.').last,
    };
  }

  factory LinkedFriend.fromJson(Map<String, dynamic> json) {
    return LinkedFriend(
      name: json['name'],
      phoneNumber: json['phoneNumber'],
      userId: json['userId'],
      linkedDate: DateTime.parse(json['linkedDate']),
      status: LinkStatus.values.firstWhere(
            (e) => e.toString().split('.').last == json['status'],
        orElse: () => LinkStatus.pending,
      ),
    );
  }

  // Create a copy with updated status
  LinkedFriend copyWith({
    String? name,
    String? phoneNumber,
    String? userId,
    DateTime? linkedDate,
    LinkStatus? status,
  }) {
    return LinkedFriend(
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      userId: userId ?? this.userId,
      linkedDate: linkedDate ?? this.linkedDate,
      status: status ?? this.status,
    );
  }
}

class LinkedFriends {
  static List<LinkedFriend> _linkedFriends = [];
  static final List<VoidCallback> _listeners = [];
  static const String _fileName = 'linked_friends.json';

  static List<LinkedFriend> get linkedFriends => List.unmodifiable(_linkedFriends);
  static List<LinkedFriend> get acceptedFriends =>
      _linkedFriends.where((f) => f.status == LinkStatus.accepted).toList();
  static List<LinkedFriend> get pendingRequests =>
      _linkedFriends.where((f) => f.status == LinkStatus.pending).toList();
  static int get count => _linkedFriends.length;
  static int get acceptedCount => acceptedFriends.length;
  static int get pendingCount => pendingRequests.length;

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    print('LinkedFriends: Notifying ${_listeners.length} listeners');
    for (var listener in _listeners) {
      listener();
    }
  }

  // Send a link request (initially pending)
  static Future<void> linkFriend(String name, {String? phoneNumber, String? userId}) async {
    // Check if already linked or pending
    if (_linkedFriends.any((f) => f.name == name || (userId != null && f.userId == userId))) {
      print('Friend $name is already linked or has pending request');
      return;
    }

    final newFriend = LinkedFriend(
      name: name,
      phoneNumber: phoneNumber,
      userId: userId,
      linkedDate: DateTime.now(),
      status: LinkStatus.pending,
    );

    _linkedFriends.add(newFriend);
    await _saveToStorage();
    _notifyListeners();
    print('Link request sent to: $name (Status: pending)');

    // TODO: When you have a database, send notification here:
    // await _sendLinkNotification(userId, name);
  }

  // Accept a link request (when other user accepts)
  static Future<void> acceptLinkRequest(String name) async {
    final friendIndex = _linkedFriends.indexWhere((f) => f.name == name);

    if (friendIndex != -1) {
      _linkedFriends[friendIndex] = _linkedFriends[friendIndex].copyWith(
        status: LinkStatus.accepted,
      );
      await _saveToStorage();
      _notifyListeners();
      print('Link request accepted from: $name');
    }
  }

  // Reject a link request
  static Future<void> rejectLinkRequest(String name) async {
    final friendIndex = _linkedFriends.indexWhere((f) => f.name == name);

    if (friendIndex != -1) {
      _linkedFriends[friendIndex] = _linkedFriends[friendIndex].copyWith(
        status: LinkStatus.rejected,
      );
      await _saveToStorage();
      _notifyListeners();
      print('Link request rejected from: $name');
    }
  }

  // Remove a linked friend completely
  static Future<void> unlinkFriend(String name) async {
    final initialCount = _linkedFriends.length;
    _linkedFriends.removeWhere((f) => f.name == name);

    if (_linkedFriends.length < initialCount) {
      await _saveToStorage();
      _notifyListeners();
      print('Unlinked friend $name (${_linkedFriends.length} total)');

      // TODO: When you have a database, send unlink notification here:
      // await _sendUnlinkNotification(userId);
    }
  }

  // Check if a friend is linked (and accepted)
  static bool isLinked(String name) {
    return _linkedFriends.any((f) => f.name == name && f.status == LinkStatus.accepted);
  }

  // Check if there's a pending request for this friend
  static bool isPending(String name) {
    return _linkedFriends.any((f) => f.name == name && f.status == LinkStatus.pending);
  }

  // Get a specific linked friend
  static LinkedFriend? getLinkedFriend(String name) {
    try {
      return _linkedFriends.firstWhere((f) => f.name == name);
    } catch (e) {
      return null;
    }
  }

  // Load linked friends from storage
  static Future<void> loadFromStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');

      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> data = jsonDecode(contents);

        _linkedFriends = data.map((json) => LinkedFriend.fromJson(json)).toList();
        print('Linked friends loaded: ${_linkedFriends.length} friends');
        print('Accepted: ${acceptedCount}, Pending: ${pendingCount}');

        _notifyListeners();
      } else {
        print('No saved linked friends found');
        _linkedFriends = [];
      }
    } catch (e) {
      print('Error loading linked friends: $e');
      _linkedFriends = [];
    }
  }

  // Save linked friends to storage
  static Future<void> _saveToStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');

      final List<Map<String, dynamic>> data = _linkedFriends.map((f) => f.toJson()).toList();
      await file.writeAsString(jsonEncode(data));

      print('Linked friends saved: ${_linkedFriends.length} friends');
    } catch (e) {
      print('Error saving linked friends: $e');
    }
  }

  // Get linked friends sorted by date (newest first)
  static List<LinkedFriend> getSortedByDate({bool ascending = false, LinkStatus? filterStatus}) {
    var friends = filterStatus != null
        ? _linkedFriends.where((f) => f.status == filterStatus).toList()
        : List<LinkedFriend>.from(_linkedFriends);

    friends.sort((a, b) {
      final comparison = a.linkedDate.compareTo(b.linkedDate);
      return ascending ? comparison : -comparison;
    });
    return friends;
  }

  // Get linked friends sorted by name
  static List<LinkedFriend> getSortedByName({bool ascending = true, LinkStatus? filterStatus}) {
    var friends = filterStatus != null
        ? _linkedFriends.where((f) => f.status == filterStatus).toList()
        : List<LinkedFriend>.from(_linkedFriends);

    friends.sort((a, b) {
      final comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return ascending ? comparison : -comparison;
    });
    return friends;
  }

  // Reset all linked friends
  static Future<void> resetAll() async {
    _linkedFriends.clear();
    await _saveToStorage();
    _notifyListeners();
    print('All linked friends reset');
  }

// TODO: Implement when you have a database
// static Future<void> _sendLinkNotification(String? userId, String senderName) async {
//   if (userId == null) return;
//
//   // Send notification to user's account
//   // Example:
//   // await DatabaseService.sendNotification(
//   //   userId: userId,
//   //   type: 'link_request',
//   //   message: '$senderName wants to link with you',
//   //   data: {'senderId': currentUserId, 'senderName': senderName},
//   // );
// }

// TODO: Implement when you have a database
// static Future<void> _sendUnlinkNotification(String? userId) async {
//   if (userId == null) return;
//
//   // Notify user they've been unlinked
//   // await DatabaseService.sendNotification(...);
// }

// TODO: Call this when receiving notification from database
// static Future<void> handleIncomingLinkRequest(String userId, String userName) async {
//   await linkFriend(userName, userId: userId);
// }
}