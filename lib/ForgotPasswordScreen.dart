import 'package:flutter/material.dart';
import 'dart:async';
import 'auth_service.dart';

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
  int _timerValue = 60;
  Timer? _timer;

  void _startTimer() {
    setState(() => _timerValue = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_timerValue == 0) t.cancel();
      else setState(() => _timerValue--);
    });
  }

  Future<void> _handleReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isLoading = true);
    String? error = await _authService.sendPasswordReset(email);
    setState(() => _isLoading = false);

    if (error == null) {
      setState(() => _emailSent = true);
      _startTimer();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
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
      appBar: AppBar(elevation: 0, backgroundColor: Colors.white, leading: const BackButton(color: Colors.black)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_emailSent ? Icons.mark_email_read_outlined : Icons.lock_reset, size: 80, color: Colors.cyan),
            const SizedBox(height: 24),
            Text(_emailSent ? "Check your email" : "Forgot Password?", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              _emailSent
                  ? "We sent a reset link to ${_emailController.text}. Follow the link to set a new password."
                  : "Enter your account email and we'll send you a link to reset your password.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            if (!_emailSent) ...[
              TextField(
                controller: _emailController,
                decoration: InputDecoration(hintText: "Email Address", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleReset,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.black),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Send Reset Link", style: TextStyle(color: Colors.white)),
              ),
            ] else ...[
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.black),
                child: const Text("I've Reset My Password", style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _timerValue == 0 ? _handleReset : null,
                child: Text(_timerValue == 0 ? "Resend Link" : "Resend in ${_timerValue}s", style: TextStyle(color: _timerValue == 0 ? Colors.cyan : Colors.grey)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}