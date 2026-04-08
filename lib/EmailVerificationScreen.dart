import 'package:flutter/material.dart';
import 'dart:async';
import 'auth_service.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({Key? key}) : super(key: key);

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final AuthService _authService = AuthService();
  bool _isChecking = false;
  int _timerValue = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    setState(() => _timerValue = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_timerValue == 0) t.cancel();
      else setState(() => _timerValue--);
    });
  }

  Future<void> _check() async {
    setState(() => _isChecking = true);
    bool isV = await _authService.checkVerificationStatus();
    if (isV) {
      Navigator.pushReplacementNamed(context, '/user-account');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Still not verified. Check your spam folder!"))
      );
    }
    setState(() => _isChecking = false);
  }

  Future<void> _resend() async {
    String? error = await _authService.resendVerificationEmail();
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email resent!")));
      _startTimer();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $error")));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(elevation: 0, backgroundColor: Colors.white, leading: const BackButton(color: Colors.black)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 100, color: Colors.cyan),
              const SizedBox(height: 20),
              const Text("Verify Email", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text("We sent a link to:\n${_authService.currentUser?.email}", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _isChecking ? null : _check,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55), backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _isChecking ? const CircularProgressIndicator(color: Colors.white) : const Text("I've Verified My Email", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _timerValue == 0 ? _resend : null,
                child: Text(_timerValue == 0 ? "Resend Email" : "Resend in ${_timerValue}s", style: TextStyle(color: _timerValue == 0 ? Colors.cyan : Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}