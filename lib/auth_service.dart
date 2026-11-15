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

  // PHONE NUMBERS
  // Phone accounts have no password: signing up and logging in are both
  // "enter your number, type the code we text you" (Firebase phone auth).
  // Each number can only ever belong to one account.

  /// True if what's typed so far looks like the start of a phone number
  /// (digits, optionally a leading +, spaces/dashes/brackets allowed).
  static bool looksLikePhoneInput(String input) {
    final s = input.trim();
    if (s.isEmpty) return false;
    final first = s[0];
    if (first != '+' && !RegExp(r'[0-9]').hasMatch(first)) return false;
    return RegExp(r'^\+?[0-9\s\-().]+$').hasMatch(s);
  }

  /// True if [input] looks like an email address.
  static bool looksLikeEmail(String input) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(input.trim());

  /// Turns what someone typed into a full international number
  /// (+15551234567), using [dialCode] (the country picker, no plus) unless
  /// they typed their own +code. Null if it isn't a usable number.
  static String? normalizePhone(String input, {String dialCode = '1'}) {
    final s = input.trim();
    if (!RegExp(r'^\+?[0-9\s\-().]+$').hasMatch(s)) return null;
    var digits = s.replaceAll(RegExp(r'[^0-9]'), '');

    if (s.startsWith('+')) {
      return (digits.length >= 8 && digits.length <= 15) ? '+$digits' : null;
    }

    if (dialCode == '1') {
      // US/Canada: 10 digits, or 11 if they typed the leading 1.
      if (digits.length == 11 && digits.startsWith('1')) {
        digits = digits.substring(1);
      }
      return digits.length == 10 ? '+1$digits' : null;
    }

    // Most countries write local numbers with a leading 0 that's dropped
    // internationally (UK 07700... -> +44 7700...). Italy keeps it.
    if (digits.startsWith('0') && dialCode != '39') {
      digits = digits.substring(1);
    }
    final full = '$dialCode$digits';
    return (digits.length >= 6 && full.length <= 15) ? '+$full' : null;
  }

  /// Texts a 6-digit code to [phone] (full +number). On Android the code
  /// can be read automatically, in which case [onAutoVerified] fires with a
  /// ready credential and no typing is needed.
  Future<void> sendPhoneCode({
    required String phone,
    int? resendToken,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
    required void Function(String errorCode) onError,
  }) {
    return _auth.verifyPhoneNumber(
      phoneNumber: phone,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      codeSent: (id, token) => onCodeSent(id, token),
      verificationCompleted: onAutoVerified,
      verificationFailed: (e) => onError(e.code),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// Creates a phone account once the code checks out: signs in with the
  /// number, claims the username and writes the profile. If anything fails
  /// part-way, the half-made account is removed.
  Future<Map<String, dynamic>> completePhoneSignUp({
    required PhoneAuthCredential credential,
    required String phone,
    required String username,
    required String birthYear,
    required String birthMonth,
    required String birthDay,
  }) async {
    try {
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) return {'success': false, 'error': ''};

      // This number already has an account.
      if (result.additionalUserInfo?.isNewUser == false) {
        await _auth.signOut();
        return {'success': false, 'error': 'phone-taken'};
      }

      // Claim the name. If someone got it a moment ago, undo the account.
      try {
        await _firestore.collection('usernames').doc(_key(username)).set({
          'uid': user.uid,
          'email': '',
          'phone': phone,
        });
      } catch (_) {
        await user.delete();
        return {'success': false, 'error': 'username-taken'};
      }

      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': '',
        'phone': phone,
        'username': username,
        'birthYear': birthYear,
        'birthMonth': birthMonth,
        'birthDay': birthDay,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {'success': true, 'user': user};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': e.code};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Logs into an existing phone account with a checked code. If the number
  /// has no account, nothing is created and 'no-account' comes back.
  Future<Map<String, dynamic>> loginWithPhone(
      PhoneAuthCredential credential) async {
    try {
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) return {'success': false, 'error': ''};

      if (result.additionalUserInfo?.isNewUser == true) {
        // Firebase just made a blank account for an unknown number; remove it.
        await user.delete();
        return {'success': false, 'error': 'no-account'};
      }
      return {'success': true, 'user': user};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': e.code};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // SIGN UP (email)
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

  // LOGIN — username or email, plus password. (Phone numbers log in with a
  // texted code instead; see loginWithPhone.)
  Future<Map<String, dynamic>> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    try {
      String email = usernameOrEmail.trim();
      if (!email.contains('@')) {
        final doc =
        await _firestore.collection('usernames').doc(_key(email)).get();
        final data = doc.data();
        final found = data?['email'] as String?;
        if (found == null || found.isEmpty) {
          if (data != null && data['phone'] != null) {
            return {'success': false, 'error': 'phone-account'};
          }
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