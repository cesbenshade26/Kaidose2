import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  final String dailyEntryPrompt;
  final String? titleFont;

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
    this.dailyEntryPrompt = '',
    this.titleFont,
  }) : foundingMemberIds = foundingMemberIds ?? List<String>.from(invitedFriendIds);

  // Convert to JSON for SharedPreferences (legacy support)
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
      'dailyEntryPrompt': dailyEntryPrompt,
      'titleFont': titleFont,
    };
  }

  // Convert to Firestore format
  Map<String, dynamic> toFirestoreJson() {
    Map<String, dynamic>? tierPrivilegesJson;
    if (tierPrivileges != null) {
      tierPrivilegesJson = tierPrivileges!.map(
            (key, value) => MapEntry(key.toString(), value),
      );
    }

    return {
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
      'createdAt': Timestamp.fromDate(createdAt),
      'isPinned': isPinned,
      'tierAssignments': tierAssignments?.map((key, value) => MapEntry(key.toString(), value)),
      'tierPrivileges': tierPrivilegesJson,
      'dailyEntryPrompt': dailyEntryPrompt,
      'titleFont': titleFont,
    };
  }

  // Create from JSON (legacy support)
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
      keywords: List<String>.from(json['keywords'] ?? []),
      managementTiers: List<String>.from(json['managementTiers'] ?? []),
      icon: IconData(json['icon'], fontFamily: 'MaterialIcons'),
      iconColor: json['iconColor'],
      customIconPath: json['customIconPath'],
      invitedFriendIds: List<String>.from(json['invitedFriendIds'] ?? []),
      foundingMemberIds: json['foundingMemberIds'] != null
          ? List<String>.from(json['foundingMemberIds'])
          : List<String>.from(json['invitedFriendIds'] ?? []),
      createdAt: DateTime.parse(json['createdAt']),
      isPinned: json['isPinned'] ?? false,
      tierAssignments: tierAssignments,
      tierPrivileges: tierPrivileges,
      dailyEntryPrompt: json['dailyEntryPrompt'] ?? '',
      titleFont: json['titleFont'],
    );
  }

  // Create from Firestore
  factory DailyData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    Map<int, List<String>>? tierAssignments;
    try {
      if (data['tierAssignments'] != null) {
        final tierAssignmentsJson = data['tierAssignments'];
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
      if (data['tierPrivileges'] != null) {
        final tierPrivilegesJson = data['tierPrivileges'];
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
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      privacy: data['privacy'] ?? 'Public',
      keywords: List<String>.from(data['keywords'] ?? []),
      managementTiers: List<String>.from(data['managementTiers'] ?? []),
      icon: IconData(data['icon'] ?? Icons.star.codePoint, fontFamily: 'MaterialIcons'),
      iconColor: data['iconColor'],
      customIconPath: data['customIconPath'],
      invitedFriendIds: List<String>.from(data['invitedFriendIds'] ?? []),
      foundingMemberIds: data['foundingMemberIds'] != null
          ? List<String>.from(data['foundingMemberIds'])
          : List<String>.from(data['invitedFriendIds'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isPinned: data['isPinned'] ?? false,
      tierAssignments: tierAssignments,
      tierPrivileges: tierPrivileges,
      dailyEntryPrompt: data['dailyEntryPrompt'] ?? '',
      titleFont: data['titleFont'],
    );
  }
}