import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class ArchiveData {
  final String id;
  final String name;
  final String description;
  final List<String> collaborators;
  final DateTime createdAt;

  ArchiveData({
    required this.id,
    required this.name,
    required this.description,
    required this.collaborators,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'collaborators': collaborators,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ArchiveData.fromJson(Map<String, dynamic> json) {
    return ArchiveData(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      collaborators: List<String>.from(json['collaborators'] ?? []),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class ArchiveStorage {
  static const String _archivesKey = 'custom_archives';
  static const String _defaultArchiveId = 'default_your_archives';
  static final List<ArchiveData> _archives = [];
  static final List<VoidCallback> _listeners = [];

  static List<ArchiveData> get archives => List.unmodifiable(_archives);

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  /// Create default "Your Archives" folder
  static ArchiveData _createDefaultArchive() {
    return ArchiveData(
      id: _defaultArchiveId,
      name: 'Your Archives',
      description: 'Saved messages, clips & more',
      collaborators: [],
      createdAt: DateTime.now(),
    );
  }

  /// Add a new archive
  static Future<void> addArchive(ArchiveData archive) async {
    _archives.add(archive);
    await _saveToStorage();
    _notifyListeners();
  }

  /// Remove an archive (cannot remove default archive)
  static Future<void> removeArchive(String archiveId) async {
    // Prevent deletion of default archive
    if (archiveId == _defaultArchiveId) {
      print('Cannot delete default "Your Archives" folder');
      return;
    }

    _archives.removeWhere((archive) => archive.id == archiveId);
    await _saveToStorage();
    _notifyListeners();
    print('Archive removed: $archiveId');
  }

  /// Update an archive
  static Future<void> updateArchive(ArchiveData updatedArchive) async {
    final index = _archives.indexWhere((archive) => archive.id == updatedArchive.id);
    if (index != -1) {
      _archives[index] = updatedArchive;
      await _saveToStorage();
      _notifyListeners();
      print('Archive updated: ${updatedArchive.name}');
    }
  }

  /// Save archives to storage
  static Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final archivesJson = _archives.map((archive) => archive.toJson()).toList();
      await prefs.setString(_archivesKey, jsonEncode(archivesJson));
      print('Saved ${_archives.length} archives to storage');
    } catch (e) {
      print('Error saving archives: $e');
    }
  }

  /// Load archives from storage
  static Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final archivesString = prefs.getString(_archivesKey);

      if (archivesString != null) {
        final List<dynamic> archivesJson = jsonDecode(archivesString);
        _archives.clear();
        _archives.addAll(archivesJson.map((json) => ArchiveData.fromJson(json)));
        print('Loaded ${_archives.length} archives from storage');
      } else {
        print('No saved archives found');
      }

      // Ensure default archive exists
      final hasDefault = _archives.any((archive) => archive.id == _defaultArchiveId);
      if (!hasDefault) {
        print('Creating default "Your Archives" folder');
        _archives.insert(0, _createDefaultArchive());
        await _saveToStorage();
      }

      _notifyListeners();
    } catch (e) {
      print('Error loading archives: $e');
    }
  }

  /// Clear all archives (for testing/debugging)
  static Future<void> clearAll() async {
    _archives.clear();
    await _saveToStorage();
    _notifyListeners();
  }
}