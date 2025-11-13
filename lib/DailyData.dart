import 'package:flutter/material.dart';

class DailyData {
  final String id;
  final String title;
  final String description;
  final String privacy;
  final List<String> keywords;
  final IconData icon;
  final int? iconColor; // Store color as int value (nullable for backward compatibility)
  final String? customIconPath; // For uploaded icons
  final List<String> invitedFriendIds;
  final DateTime createdAt;
  bool isPinned;

  DailyData({
    required this.id,
    required this.title,
    required this.description,
    required this.privacy,
    required this.keywords,
    required this.icon,
    this.iconColor, // Optional parameter
    this.customIconPath,
    required this.invitedFriendIds,
    required this.createdAt,
    this.isPinned = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'privacy': privacy,
      'keywords': keywords,
      'iconCodePoint': icon.codePoint,
      'iconColor': iconColor,
      'customIconPath': customIconPath,
      'invitedFriendIds': invitedFriendIds,
      'createdAt': createdAt.toIso8601String(),
      'isPinned': isPinned,
    };
  }

  factory DailyData.fromJson(Map<String, dynamic> json) {
    return DailyData(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      privacy: json['privacy'],
      keywords: List<String>.from(json['keywords']),
      icon: IconData(json['iconCodePoint'], fontFamily: 'MaterialIcons'),
      iconColor: json['iconColor'],
      customIconPath: json['customIconPath'],
      invitedFriendIds: List<String>.from(json['invitedFriendIds']),
      createdAt: DateTime.parse(json['createdAt']),
      isPinned: json['isPinned'] ?? false,
    );
  }
}