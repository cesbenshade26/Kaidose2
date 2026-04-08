import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;

  // SIGN UP
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String username,
    required String birthYear,
    required String birthMonth,
    required String birthDay,
  }) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = userCredential.user;
      if (user != null) {
        await user.sendEmailVerification();
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': email,
          'username': username,
          'birthYear': birthYear,
          'birthMonth': birthMonth,
          'birthDay': birthDay,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return {'success': true, 'user': user};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': e.code};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // LOGIN
  Future<Map<String, dynamic>> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    try {
      String email = usernameOrEmail;
      if (!usernameOrEmail.contains('@')) {
        QuerySnapshot query = await _firestore
            .collection('users')
            .where('username', isEqualTo: usernameOrEmail)
            .limit(1)
            .get();
        if (query.docs.isEmpty) return {'success': false, 'error': 'Username not found'};
        email = query.docs.first.get('email');
      }
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return {'success': true, 'user': userCredential.user};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': e.code};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // PASSWORD RESET
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // VERIFICATION STATUS
  Future<bool> checkVerificationStatus() async {
    User? user = _auth.currentUser;
    if (user != null) {
      await user.reload();
      return _auth.currentUser!.emailVerified;
    }
    return false;
  }

  // RESEND VERIFICATION (FIXED TYPE)
  Future<String?> resendVerificationEmail() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
      return null; // Success
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}