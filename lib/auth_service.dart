import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  // Use getters to ensure we always use the current, active Firebase instance.
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Check if logged in
  bool get isLoggedIn => _auth.currentUser != null;

  // Sign up
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String username,
    required String birthYear,
    required String birthMonth,
    required String birthDay,
  }) async {
    try {
      print('Auth Service: Starting signup for $email...');

      // 1. Create user in Firebase Auth
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('Auth Service: User created in Firebase Auth (UID: ${userCredential.user!.uid})');

      // 2. Create user document in Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': email,
        'username': username,
        'birthYear': birthYear,
        'birthMonth': birthMonth,
        'birthDay': birthDay,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('Auth Service: User document created in Firestore');
      return {'success': true, 'user': userCredential.user};
    } on FirebaseAuthException catch (e) {
      print('Auth Service: FirebaseAuthException - ${e.code}');
      print('Message: ${e.message}');
      return {'success': false, 'error': _getErrorMessage(e.code)};
    } catch (e) {
      print('Auth Service: Generic error during signup - $e');
      return {'success': false, 'error': 'An unexpected error occurred: $e'};
    }
  }

  // Login
  Future<Map<String, dynamic>> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    try {
      print('Auth Service: Starting login for $usernameOrEmail...');
      String email = usernameOrEmail;

      // If username provided (no @), look up email in Firestore
      if (!usernameOrEmail.contains('@')) {
        print('Auth Service: Looking up username in Firestore...');

        try {
          QuerySnapshot query = await _firestore
              .collection('users')
              .where('username', isEqualTo: usernameOrEmail)
              .limit(1)
              .get();

          if (query.docs.isEmpty) {
            print('Auth Service: Username not found');
            return {'success': false, 'error': 'Username not found'};
          }

          email = query.docs.first.get('email');
          print('Auth Service: Found email: $email');
        } catch (e) {
          print('Auth Service: Firestore lookup failed (Is the database created?) - $e');
          return {'success': false, 'error': 'Database error. Please check your connection.'};
        }
      }

      // Login with email
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('Auth Service: Login successful');
      return {'success': true, 'user': userCredential.user};
    } on FirebaseAuthException catch (e) {
      print('Auth Service: FirebaseAuthException - ${e.code}: ${e.message}');
      return {'success': false, 'error': _getErrorMessage(e.code)};
    } catch (e) {
      print('Auth Service: Generic error - $e');
      return {'success': false, 'error': 'Login failed: $e'};
    }
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
  }

  // Get user data
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
      return doc.data() as Map<String, dynamic>?;
    } catch (e) {
      print('Auth Service: Error getting user data - $e');
      return null;
    }
  }

  // Error messages
  String _getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered';
      case 'weak-password':
        return 'Password should be at least 6 characters';
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-not-found':
        return 'No account found with this email/username';
      case 'wrong-password':
        return 'Incorrect password';
      case 'internal-error':
        return 'Firebase connection error (Internal). Check project configuration.';
      default:
        return 'Authentication failed: $code';
    }
  }
}