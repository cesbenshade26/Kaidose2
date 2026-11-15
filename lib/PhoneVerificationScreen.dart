import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'InterestOnboarding.dart';
import 'KaidoseBrand.dart';

/// What was typed on Create Account, held until the number is verified.
/// The account isn't created until the code checks out.
class PendingPhoneSignUp {
  final String username;
  final String birthYear;
  final String birthMonth;
  final String birthDay;

  const PendingPhoneSignUp({
    required this.username,
    required this.birthYear,
    required this.birthMonth,
    required this.birthDay,
  });
}

/// Texts a 6-digit code and checks it. Used for both:
///  - signing up with a phone number ([signUp] given) -> onboarding
///  - logging in with a phone number ([signUp] null)  -> home
///
/// Pops with 'username-taken', 'phone-taken' or 'no-account' when the
/// screen before it should show a message instead.
class PhoneVerificationScreen extends StatefulWidget {
  final String phone; // full international number, e.g. +15551234567
  final PendingPhoneSignUp? signUp;

  const PhoneVerificationScreen({Key? key, required this.phone, this.signUp})
      : super(key: key);

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _codeController = TextEditingController();

  String? _verificationId;
  int? _resendToken;
  bool _sending = true;
  bool _verifying = false;
  bool _done = false;
  int _timerValue = 60;
  Timer? _timer;

  bool get _isSignUp => widget.signUp != null;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
    _sendCode();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() => _timerValue = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_timerValue == 0) {
        t.cancel();
      } else if (mounted) {
        setState(() => _timerValue--);
      }
    });
  }

  Future<void> _sendCode() async {
    setState(() => _sending = true);
    await _authService.sendPhoneCode(
      phone: widget.phone,
      resendToken: _resendToken,
      onCodeSent: (id, token) {
        if (!mounted) return;
        setState(() {
          _verificationId = id;
          _resendToken = token;
          _sending = false;
        });
        _startTimer();
      },
      // Android can read the text itself: finish without any typing.
      onAutoVerified: (credential) {
        if (mounted) _complete(credential);
      },
      onError: (code) {
        if (!mounted) return;
        setState(() => _sending = false);
        _showMessage(authErrorMessage(code));
      },
    );
  }

  /// Six digits typed (or pasted / autofilled) -> check straight away.
  void _onCodeChanged() {
    if (_codeController.text.trim().length == 6 && !_verifying) _verifyTyped();
  }

  void _verifyTyped() {
    final code = _codeController.text.trim();
    if (_verificationId == null) {
      _showMessage('Hang on, the code is still on its way');
      return;
    }
    if (code.length != 6) {
      _showMessage('Enter the 6-digit code');
      return;
    }
    _complete(PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: code,
    ));
  }

  Future<void> _complete(PhoneAuthCredential credential) async {
    if (_done || _verifying) return;
    FocusScope.of(context).unfocus();
    setState(() => _verifying = true);

    final Map<String, dynamic> result;
    if (_isSignUp) {
      final s = widget.signUp!;
      result = await _authService.completePhoneSignUp(
        credential: credential,
        phone: widget.phone,
        username: s.username,
        birthYear: s.birthYear,
        birthMonth: s.birthMonth,
        birthDay: s.birthDay,
      );
    } else {
      result = await _authService.loginWithPhone(credential);
    }
    if (!mounted) return;

    if (result['success'] == true) {
      _done = true;
      if (_isSignUp) {
        _goTo(const InterestOnboarding());
      } else {
        await _goAfterLogin();
      }
      return;
    }

    setState(() => _verifying = false);
    final error = result['error'] as String?;
    if (error == 'username-taken' ||
        error == 'phone-taken' ||
        error == 'no-account') {
      Navigator.of(context).pop(error);
    } else {
      _codeController.clear();
      _showMessage(authErrorMessage(error));
    }
  }

  /// Same check the login screen does: onboarding first if it isn't done.
  Future<void> _goAfterLogin() async {
    var onboardingDone = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
        onboardingDone = doc.data()?['onboardingComplete'] == true;
      } catch (_) {}
    }
    if (!mounted) return;
    if (onboardingDone) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/user-account', (route) => false);
    } else {
      _goTo(const InterestOnboarding());
    }
  }

  void _goTo(Widget screen) {
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
          (route) => false,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// +15551234567 -> (555) 123-4567; other countries shown as is.
  String _pretty(String e164) {
    if (e164.startsWith('+1') && e164.length == 12) {
      final d = e164.substring(2);
      return '(${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}';
    }
    return e164;
  }

  @override
  Widget build(BuildContext context) {
    final pretty = _pretty(widget.phone);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AuthHeader(
                  icon: Icons.sms_outlined,
                  title: 'Enter the code',
                  subtitle: _sending
                      ? 'Texting a code to\n$pretty…'
                      : 'We texted a 6-digit code to\n$pretty',
                ),
                const SizedBox(height: 32),
                AuthField(
                  controller: _codeController,
                  label: '6-digit code',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 6,
                  onSubmitted: (_) => _verifyTyped(),
                ),
                const SizedBox(height: 20),
                AuthButton(
                  label: _isSignUp ? 'Verify' : 'Log in',
                  loading: _verifying,
                  onPressed: _verifyTyped,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: (_timerValue == 0 && !_sending) ? _sendCode : null,
                  child: Text(
                    _timerValue == 0 && !_sending
                        ? 'Resend code'
                        : 'Resend in ${_timerValue}s',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: _timerValue == 0 && !_sending
                          ? KaidoseBrand.cyan
                          : Colors.grey[400],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Wrong number? Go back',
                      style: TextStyle(fontSize: 13.5, color: Colors.grey[600])),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}