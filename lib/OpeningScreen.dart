import 'package:flutter/material.dart';
import 'CreateAccount.dart';
import 'ForgotPasswordScreen.dart';
import 'auth_service.dart';

class OpeningScreen extends StatefulWidget {
  final bool skipAnimation;
  const OpeningScreen({super.key, this.skipAnimation = false});

  @override
  State<OpeningScreen> createState() => _OpeningScreenState();
}

class _OpeningScreenState extends State<OpeningScreen> with TickerProviderStateMixin {
  late AnimationController _drawController;
  late Animation<double> _drawProgress;
  late AnimationController _formController;
  late Animation<double> _formOpacity;
  late AnimationController _fadeController;
  late Animation<double> _fadeOpacity;

  final _authService = AuthService();

  bool moveToTop = false;
  bool showForm = false;
  bool isCheckingLoginState = true;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String loginError = '';

  @override
  void initState() {
    super.initState();

    _drawController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    _drawProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _drawController, curve: Curves.easeInOut),
    );

    _formController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _formOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _formController, curve: Curves.easeIn),
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _initializeScreen();
  }

  void _initializeScreen() {
    // For testing: we ignore previous login sessions to always show the form
    setState(() {
      isCheckingLoginState = false;
    });

    if (widget.skipAnimation) {
      setState(() {
        moveToTop = true;
        showForm = true;
      });
      _drawController.value = 1.0;
      _formController.value = 1.0;
    } else {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _drawController.forward().whenComplete(() async {
      setState(() {
        moveToTop = true;
      });

      await Future.delayed(const Duration(milliseconds: 1500));

      setState(() {
        showForm = true;
      });
      _formController.forward();
    });
  }

  @override
  void dispose() {
    _drawController.dispose();
    _formController.dispose();
    _fadeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _attemptLogin() async {
    setState(() {
      loginError = '';
    });

    final inputUser = _usernameController.text.trim();
    final inputPass = _passwordController.text;

    if (inputUser.isEmpty || inputPass.isEmpty) {
      setState(() {
        loginError = 'Please enter username and password';
      });
      return;
    }

    setState(() => isCheckingLoginState = true);

    final result = await _authService.login(
      usernameOrEmail: inputUser,
      password: inputPass,
    );

    setState(() => isCheckingLoginState = false);

    if (!mounted) return;

    if (result['success']) {
      Navigator.pushReplacementNamed(context, '/user-account');
    } else {
      setState(() {
        loginError = result['error'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isCheckingLoginState) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Colors.cyan)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // The Animated Title
          AnimatedPositioned(
            duration: const Duration(seconds: 2),
            curve: Curves.easeInOut,
            top: moveToTop ? 80 : MediaQuery.of(context).size.height / 2 - 32,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeOpacity,
              child: AnimatedBuilder(
                animation: _drawProgress,
                builder: (context, child) {
                  return Center(
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: _drawProgress.value,
                        child: const Text(
                          'Kaidose',
                          style: TextStyle(
                            fontFamily: 'Slackey',
                            fontSize: 64,
                            color: Colors.cyan,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // The Login Form
          if (showForm)
            FadeTransition(
              opacity: _formOpacity,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 60.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Login to Kaidose',
                        style: TextStyle(
                          fontFamily: 'Slackey',
                          fontSize: 24,
                          color: Colors.cyan,
                        ),
                      ),
                      const SizedBox(height: 24),

                      _buildTextField(_usernameController, 'Username or Email', false),
                      const SizedBox(height: 16),
                      _buildTextField(_passwordController, 'Password', true),

                      // Forgot Password Link
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 45.0, top: 8.0),
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _attemptLogin,
                          child: const Text('Login', style: TextStyle(color: Colors.white)),
                        ),
                      ),

                      if (loginError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(loginError, style: const TextStyle(color: Colors.red)),
                        ),

                      const SizedBox(height: 20),
                      const Divider(color: Colors.grey, thickness: 1, indent: 40, endIndent: 40),
                      const SizedBox(height: 20),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const CreateAccount()),
                            );
                          },
                          child: const Text('Create Account', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, bool obscure) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        cursorColor: Colors.black,
        decoration: InputDecoration(
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.black),
            borderRadius: BorderRadius.circular(12),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}