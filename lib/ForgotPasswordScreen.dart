import 'package:flutter/material.dart';
import 'dart:async';
import 'auth_service.dart';
import 'KaidoseBrand.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();

  bool _emailSent = false;
  bool _isLoading = false;
  String _sentTo = '';
  int _timerValue = 60;
  Timer? _timer;

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

  Future<void> _handleReset({bool resend = false}) async {
    final email = resend ? _sentTo : _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the email you signed up with'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);
    final error = await _authService.sendPasswordReset(email);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error == null) {
      setState(() {
        _emailSent = true;
        _sentTo = email;
      });
      _startTimer();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  icon: _emailSent
                      ? Icons.mark_email_read_outlined
                      : Icons.lock_reset,
                  title: _emailSent ? 'Check your email' : 'Forgot password?',
                  subtitle: _emailSent
                      ? 'We sent a reset link to\n$_sentTo\nFollow it to choose a new password.'
                      : 'Enter your account email and we\'ll send you a link to reset your password.',
                ),
                const SizedBox(height: 32),
                if (!_emailSent) ...[
                  AuthField(
                    controller: _emailController,
                    label: 'Email address',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    onSubmitted: (_) => _handleReset(),
                  ),
                  const SizedBox(height: 20),
                  AuthButton(
                    label: 'Send reset link',
                    loading: _isLoading,
                    onPressed: _handleReset,
                  ),
                ] else ...[
                  AuthButton(
                    label: 'Back to log in',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _timerValue == 0 && !_isLoading
                        ? () => _handleReset(resend: true)
                        : null,
                    child: Text(
                      _timerValue == 0
                          ? 'Resend link'
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}