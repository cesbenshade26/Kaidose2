import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => _auth.currentUser != null;

  // USERNAMES
  // Every name is reserved in `usernames/{lowercased name}` (holding the
  // owner's uid and email). That makes names unique regardless of case
  // ("Chuck" and "chuck" are the same), makes the claim atomic so two people
  // can't grab one name at the same moment, and lets sign-up and login look
  // a name up without the `users` collection being readable by signed-out
  // people.
  static String _key(String username) =>
      Uri.encodeComponent(username.trim().toLowerCase()).toLowerCase();

  /// True if someone else already holds this name. [exceptUid] lets a person
  /// keep their own name. Returns false if the check itself fails, so a
  /// network hiccup doesn't block sign-up (the reservation write is the real
  /// guard).
  Future<bool> isUsernameTaken(String username, {String? exceptUid}) async {
    if (username.trim().isEmpty) return false;
    try {
      final doc =
      await _firestore.collection('usernames').doc(_key(username)).get();
      if (!doc.exists) return false;
      return doc.data()?['uid'] != exceptUid;
    } catch (e) {
      print('AuthService.isUsernameTaken failed: $e');
      return false;
    }
  }

  /// Claims [username] for the signed-in user. Throws if it's already held.
  Future<void> reserveUsername(String username) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    await _firestore.collection('usernames').doc(_key(username)).set({
      'uid': user.uid,
      'email': user.email ?? '',
    });
  }

  /// Gives up a name the signed-in user holds.
  Future<void> releaseUsername(String username) async {
    try {
      await _firestore.collection('usernames').doc(_key(username)).delete();
    } catch (e) {
      print('AuthService.releaseUsername failed: $e');
    }
  }

  /// For accounts made before reservations existed: claims their current
  /// name if nobody holds it yet. Safe to call every time.
  Future<void> ensureUsernameReserved(String username) async {
    try {
      final ref = _firestore.collection('usernames').doc(_key(username));
      if (!(await ref.get()).exists) await reserveUsername(username);
    } catch (e) {
      print('AuthService.ensureUsernameReserved failed: $e');
    }
  }

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
        // Claim the name first. If someone got it a moment ago, undo the
        // account so nothing half-made is left behind.
        try {
          await _firestore.collection('usernames').doc(_key(username)).set({
            'uid': user.uid,
            'email': email,
          });
        } catch (_) {
          await user.delete();
          return {'success': false, 'error': 'username-taken'};
        }

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
      String email = usernameOrEmail.trim();
      if (!email.contains('@')) {
        final doc =
        await _firestore.collection('usernames').doc(_key(email)).get();
        final found = doc.data()?['email'] as String?;
        if (found == null || found.isEmpty) {
          return {'success': false, 'error': 'Username not found'};
        }
        email = found;
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
      return _auth.currentUser?.emailVerified ?? false;
    }
    return false;
  }

  // RESEND VERIFICATION
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