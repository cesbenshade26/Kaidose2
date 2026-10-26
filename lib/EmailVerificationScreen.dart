import 'package:flutter/material.dart';
import 'dart:async';
import 'auth_service.dart';
import 'InterestOnboarding.dart';
import 'KaidoseBrand.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({Key? key}) : super(key: key);

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final AuthService _authService = AuthService();
  bool _isChecking = false;
  bool _navigated = false;
  int _timerValue = 60;
  Timer? _timer;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _startTimer();
    // Quietly check every few seconds so the person is taken onward as soon
    // as they tap the link in their email — no button press needed.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check(silent: true));
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

  Future<void> _check({bool silent = false}) async {
    if (_navigated || _isChecking) return;
    if (!silent) setState(() => _isChecking = true);

    bool isVerified = false;
    try {
      isVerified = await _authService.checkVerificationStatus();
    } catch (_) {}

    if (!mounted || _navigated) return;

    if (isVerified) {
      _navigated = true;
      _poll?.cancel();
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const InterestOnboarding(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else if (!silent) {
      setState(() => _isChecking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not verified yet — check your spam folder too'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _resend() async {
    final error = await _authService.resendVerificationEmail();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error == null ? 'Email sent again' : authErrorMessage(error)),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (error == null) _startTimer();
  }

  /// Wrong address? Sign out and go back to the front door.
  Future<void> _useDifferentEmail() async {
    _poll?.cancel();
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = _authService.currentUser?.email ?? 'your email';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AuthHeader(
                  icon: Icons.mark_email_unread_outlined,
                  title: 'Check your email',
                  subtitle: 'We sent a confirmation link to\n$email\n'
                      'Tap it and you\'ll be taken in automatically.',
                ),
                const SizedBox(height: 36),
                AuthButton(
                  label: 'I\'ve verified my email',
                  loading: _isChecking,
                  onPressed: () => _check(),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _timerValue == 0 ? _resend : null,
                  child: Text(
                    _timerValue == 0
                        ? 'Resend email'
                        : 'Resend in ${_timerValue}s',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: _timerValue == 0
                          ? KaidoseBrand.cyan
                          : Colors.grey[400],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _useDifferentEmail,
                  child: Text('Wrong email? Start over',
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