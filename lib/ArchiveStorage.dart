import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'SavedItemStorage.dart';

/// One Archives folder: users/{uid}/archives/{id} {name, description,
/// createdAt}. Everyone has "Your Archives" ([ArchiveStorage.defaultId]),
/// which can be renamed but not deleted.
class ArchiveData {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;

  const ArchiveData({
    required this.id,
    required this.name,
    this.description = '',
    required this.createdAt,
  });

  bool get isDefault => id == ArchiveStorage.defaultId;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory ArchiveData.fromJson(String id, Map<String, dynamic> json) {
    final raw = json['createdAt'];
    DateTime created = DateTime.now();
    if (raw is Timestamp) created = raw.toDate();
    if (raw is String) created = DateTime.tryParse(raw) ?? created; // older
    return ArchiveData(
      id: id,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name']
          : 'Folder',
      description: json['description'] as String? ?? '',
      createdAt: created,
    );
  }
}

/// Your Archives folders, kept live while you're signed in (started in
/// main.dart). What's inside each folder is in [SavedItems].
class ArchiveStorage {
  ArchiveStorage._();

  static const String defaultId = 'default_your_archives';

  /// "Your Archives" first, then the rest oldest first.
  static final ValueNotifier<List<ArchiveData>> folders =
  ValueNotifier<List<ArchiveData>>(const []);

  static List<ArchiveData> get archives => folders.value;

  static ArchiveData? byId(String id) {
    for (final f in folders.value) {
      if (f.id == id) return f;
    }
    return null;
  }

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid).collection('archives');

  static StreamSubscription<User?>? _auth;
  static StreamSubscription? _sub;
  static Completer<void> _ready = Completer<void>();

  static void start() {
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      _sub?.cancel();
      _sub = null;
      folders.value = const [];
      if (_ready.isCompleted) _ready = Completer<void>();
      if (user == null) return;
      _sub = _ref(user.uid).snapshots().listen((snap) async {
        final list =
        snap.docs.map((d) => ArchiveData.fromJson(d.id, d.data())).toList();
        if (!list.any((f) => f.isDefault)) {
          // First time: everyone gets "Your Archives".
          final def = ArchiveData(
            id: defaultId,
            name: 'Your Archives',
            createdAt: DateTime.now(),
          );
          list.add(def);
          _ref(user.uid).doc(defaultId).set(def.toJson()).catchError((_) {});
        }
        list.sort((a, b) {
          if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
          return a.createdAt.compareTo(b.createdAt);
        });
        folders.value = list;
        if (!_ready.isCompleted) _ready.complete();
      }, onError: (e) {
        print('ArchiveStorage: $e');
        if (!_ready.isCompleted) _ready.complete();
      });
    });
  }

  /// Waits (briefly) for the folder list.
  static Future<void> loadFromStorage() async {
    start();
    if (_uid == null) return;
    try {
      await _ready.future.timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<ArchiveData?> create(String name, {String description = ''}) async {
    final uid = _uid;
    if (uid == null) return null;
    final ref = _ref(uid).doc();
    final folder = ArchiveData(
      id: ref.id,
      name: name.trim(),
      description: description.trim(),
      createdAt: DateTime.now(),
    );
    try {
      await ref.set(folder.toJson());
      return folder;
    } catch (e) {
      print('ArchiveStorage.create: $e');
      return null;
    }
  }

  static Future<bool> rename(String id, String name, {String? description}) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _ref(uid).doc(id).set({
        'name': name.trim(),
        if (description != null) 'description': description.trim(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      print('ArchiveStorage.rename: $e');
      return false;
    }
  }

  /// Deletes a folder (never "Your Archives"). What was in it stays saved
  /// anywhere else it is; a clip that was only in this folder is unsaved.
  static Future<bool> delete(String id) async {
    final uid = _uid;
    if (uid == null || id == defaultId) return false;
    try {
      await SavedItems.removeFolderEverywhere(id);
      await _ref(uid).doc(id).delete();
      return true;
    } catch (e) {
      print('ArchiveStorage.delete: $e');
      return false;
    }
  }

  // Older screens listened this way.
  static void addListener(VoidCallback l) => folders.addListener(l);
  static void removeListener(VoidCallback l) => folders.removeListener(l);
}