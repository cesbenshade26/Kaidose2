import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      'name': name,
      'description': description,
      'collaborators': collaborators,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ArchiveData.fromJson(String id, Map<String, dynamic> json) {
    return ArchiveData(
      id: id,
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      collaborators: List<String>.from(json['collaborators'] ?? []),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

/// Firestore-backed archive folders, one per user, at
/// users/{uid}/archives/{archiveId}. Public API (archives getter,
/// loadFromStorage, addArchive, etc.) is unchanged from the old
/// SharedPreferences version, so ArchivesView/CreateArchiveScreen/
/// SelectArchiveFolderScreen/InsideArchiveScreen don't need any changes —
/// only what happens inside these methods.
class ArchiveStorage {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _defaultArchiveId = 'default_your_archives';

  static final List<ArchiveData> _archives = [];
  static final List<VoidCallback> _listeners = [];

  static List<ArchiveData> get archives => List.unmodifiable(_archives);

  static String? get _uid => _auth.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>> get _archivesRef {
    final uid = _uid;
    if (uid == null) throw Exception('No signed-in user');
    return _firestore.collection('users').doc(uid).collection('archives');
  }

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
    if (_uid == null) return;
    try {
      await _archivesRef.doc(archive.id).set(archive.toJson());
      _archives.add(archive);
      _notifyListeners();
      print('Archive added: ${archive.name}');
    } catch (e) {
      print('ArchiveStorage: addArchive error: $e');
    }
  }

  /// Remove an archive (cannot remove default archive)
  static Future<void> removeArchive(String archiveId) async {
    // Prevent deletion of default archive
    if (archiveId == _defaultArchiveId) {
      print('Cannot delete default "Your Archives" folder');
      return;
    }
    if (_uid == null) return;

    try {
      await _archivesRef.doc(archiveId).delete();
      _archives.removeWhere((archive) => archive.id == archiveId);
      _notifyListeners();
      print('Archive removed: $archiveId');
    } catch (e) {
      print('ArchiveStorage: removeArchive error: $e');
    }
  }

  /// Update an archive
  static Future<void> updateArchive(ArchiveData updatedArchive) async {
    if (_uid == null) return;
    try {
      await _archivesRef
          .doc(updatedArchive.id)
          .set(updatedArchive.toJson(), SetOptions(merge: true));

      final index = _archives.indexWhere((archive) => archive.id == updatedArchive.id);
      if (index != -1) {
        _archives[index] = updatedArchive;
      }
      _notifyListeners();
      print('Archive updated: ${updatedArchive.name}');
    } catch (e) {
      print('ArchiveStorage: updateArchive error: $e');
    }
  }

  /// Load archives from Firestore, ensuring the default "Your Archives"
  /// folder exists.
  static Future<void> loadFromStorage() async {
    final uid = _uid;
    if (uid == null) {
      _archives.clear();
      _notifyListeners();
      return;
    }

    try {
      final snapshot = await _archivesRef.get();
      _archives.clear();
      _archives.addAll(
        snapshot.docs.map((doc) => ArchiveData.fromJson(doc.id, doc.data())),
      );
      print('Loaded ${_archives.length} archives from Firestore');

      // Ensure default archive exists
      final hasDefault = _archives.any((archive) => archive.id == _defaultArchiveId);
      if (!hasDefault) {
        print('Creating default "Your Archives" folder');
        final defaultArchive = _createDefaultArchive();
        await _archivesRef.doc(_defaultArchiveId).set(defaultArchive.toJson());
        _archives.insert(0, defaultArchive);
      }

      _notifyListeners();
    } catch (e) {
      print('Error loading archives: $e');
    }
  }

  /// Clear all archives (for testing/debugging)
  static Future<void> clearAll() async {
    if (_uid == null) return;
    try {
      final snapshot = await _archivesRef.get();
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      _archives.clear();
      _notifyListeners();
    } catch (e) {
      print('Error clearing archives: $e');
    }
  }
}