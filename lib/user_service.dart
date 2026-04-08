import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class KaidoseUser {
  final String uid;
  final String username;
  final String email;
  final String? birthYear;
  final String? birthMonth;
  final String? birthDay;
  final DateTime? createdAt;

  KaidoseUser({
    required this.uid,
    required this.username,
    required this.email,
    this.birthYear,
    this.birthMonth,
    this.birthDay,
    this.createdAt,
  });

  factory KaidoseUser.fromFirestore(Map<String, dynamic> data) {
    return KaidoseUser(
      uid: data['uid'] ?? '',
      username: data['username'] ?? '',
      email: data['email'] ?? '',
      birthYear: data['birthYear'],
      birthMonth: data['birthMonth'],
      birthDay: data['birthDay'],
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'username': username,
      'email': email,
      'birthYear': birthYear,
      'birthMonth': birthMonth,
      'birthDay': birthDay,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user's ID
  String? get currentUserId => _auth.currentUser?.uid;

  // Get all Kaidose users (excluding current user)
  Future<List<KaidoseUser>> getAllUsers() async {
    try {
      final currentUid = currentUserId;

      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .orderBy('username')
          .get();

      return snapshot.docs
          .where((doc) => doc.id != currentUid) // Exclude current user
          .map((doc) => KaidoseUser.fromFirestore(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error fetching users: $e');
      return [];
    }
  }

  // Search users by username
  Future<List<KaidoseUser>> searchUsers(String query) async {
    try {
      final currentUid = currentUserId;

      if (query.isEmpty) {
        return getAllUsers();
      }

      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .orderBy('username')
          .startAt([query.toLowerCase()])
          .endAt([query.toLowerCase() + '\uf8ff'])
          .get();

      return snapshot.docs
          .where((doc) => doc.id != currentUid)
          .map((doc) => KaidoseUser.fromFirestore(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  // Get user by ID
  Future<KaidoseUser?> getUserById(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();

      if (doc.exists) {
        return KaidoseUser.fromFirestore(doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      print('Error getting user: $e');
      return null;
    }
  }

  // Get user by username
  Future<KaidoseUser?> getUserByUsername(String username) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return KaidoseUser.fromFirestore(snapshot.docs.first.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      print('Error getting user by username: $e');
      return null;
    }
  }
}