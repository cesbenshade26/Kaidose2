import 'package:flutter/material.dart';

class DailyData {
  final String id;
  final String title;
  final String description;
  final String privacy;
  final List<String> keywords;
  final List<String> managementTiers;
  final IconData icon;
  final int? iconColor;
  final String? customIconPath;
  final List<String> invitedFriendIds;
  final List<String> foundingMemberIds;
  final DateTime createdAt;
  final bool isPinned;
  final Map<int, List<String>>? tierAssignments;
  final Map<int, Map<String, bool>>? tierPrivileges;
  final String dailyEntryPrompt; // NEW FIELD

  DailyData({
    required this.id,
    required this.title,
    required this.description,
    required this.privacy,
    required this.keywords,
    required this.managementTiers,
    required this.icon,
    this.iconColor,
    this.customIconPath,
    required this.invitedFriendIds,
    List<String>? foundingMemberIds,
    required this.createdAt,
    this.isPinned = false,
    this.tierAssignments,
    this.tierPrivileges,
    this.dailyEntryPrompt = '', // NEW FIELD WITH DEFAULT
  }) : foundingMemberIds = foundingMemberIds ?? List<String>.from(invitedFriendIds);

  Map<String, dynamic> toJson() {
    Map<String, dynamic>? tierPrivilegesJson;
    if (tierPrivileges != null) {
      tierPrivilegesJson = tierPrivileges!.map(
            (key, value) => MapEntry(key.toString(), value),
      );
    }

    return {
      'id': id,
      'title': title,
      'description': description,
      'privacy': privacy,
      'keywords': keywords,
      'managementTiers': managementTiers,
      'icon': icon.codePoint,
      'iconColor': iconColor,
      'customIconPath': customIconPath,
      'invitedFriendIds': invitedFriendIds,
      'foundingMemberIds': foundingMemberIds,
      'createdAt': createdAt.toIso8601String(),
      'isPinned': isPinned,
      'tierAssignments': tierAssignments?.map((key, value) => MapEntry(key.toString(), value)),
      'tierPrivileges': tierPrivilegesJson,
      'dailyEntryPrompt': dailyEntryPrompt, // NEW FIELD
    };
  }

  factory DailyData.fromJson(Map<String, dynamic> json) {
    Map<int, List<String>>? tierAssignments;
    try {
      if (json['tierAssignments'] != null) {
        final tierAssignmentsJson = json['tierAssignments'];
        if (tierAssignmentsJson is Map) {
          tierAssignments = {};
          tierAssignmentsJson.forEach((key, value) {
            try {
              final intKey = key is int ? key : int.parse(key.toString());
              final listValue = value is List ? List<String>.from(value) : <String>[];
              tierAssignments![intKey] = listValue;
            } catch (e) {
              print('Error parsing tier assignment entry: $e');
            }
          });
        }
      }
    } catch (e) {
      print('Error parsing tierAssignments: $e');
      tierAssignments = null;
    }

    Map<int, Map<String, bool>>? tierPrivileges;
    try {
      if (json['tierPrivileges'] != null) {
        final tierPrivilegesJson = json['tierPrivileges'];
        if (tierPrivilegesJson is Map) {
          tierPrivileges = {};
          tierPrivilegesJson.forEach((key, value) {
            try {
              final intKey = key is int ? key : int.parse(key.toString());
              if (value is Map) {
                final privilegesMap = Map<String, bool>.from(value);
                tierPrivileges![intKey] = privilegesMap;
              }
            } catch (e) {
              print('Error parsing tier privileges entry: $e');
            }
          });
        }
      }
    } catch (e) {
      print('Error parsing tierPrivileges: $e');
      tierPrivileges = null;
    }

    return DailyData(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      privacy: json['privacy'],
      keywords: List<String>.from(json['keywords']),
      managementTiers: List<String>.from(json['managementTiers']),
      icon: IconData(json['icon'], fontFamily: 'MaterialIcons'),
      iconColor: json['iconColor'],
      customIconPath: json['customIconPath'],
      invitedFriendIds: List<String>.from(json['invitedFriendIds']),
      foundingMemberIds: json['foundingMemberIds'] != null
          ? List<String>.from(json['foundingMemberIds'])
          : List<String>.from(json['invitedFriendIds']),
      createdAt: DateTime.parse(json['createdAt']),
      isPinned: json['isPinned'] ?? false,
      tierAssignments: tierAssignments,
      tierPrivileges: tierPrivileges,
      dailyEntryPrompt: json['dailyEntryPrompt'] ?? '', // NEW FIELD WITH DEFAULT
    );
  }
}