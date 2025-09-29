// OpeningScreen.dart
import 'UserAccount.dart';
import 'package:flutter/material.dart';
import 'package:kaidose/InterestDetector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'CreateAccount.dart';
import 'InterestDetector.dart';

class OpeningScreen extends StatefulWidget {
  final bool skipAnimation;
  const OpeningScreen({super.key, this.skipAnimation = false});

  @override
  State<OpeningScreen> createState() => _OpeningScreenState();
}

class _OpeningScreenState extends State<OpeningScreen>
    with TickerProviderStateMixin {
  late AnimationController _drawController;
  late Animation<double> _drawProgress;

  late AnimationController _formController;
  late Animation<double> _formOpacity;

  late AnimationController _fadeController;
  late Animation<double> _fadeOpacity;

  bool moveToTop = false;
  bool showForm = false;
  bool isCheckingLoginState = true;
  bool shouldGoToHome = false;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? storedUsername;
  String? storedPassword;

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

    _checkLoginStateAndInitialize();
  }

  Future<void> _checkLoginStateAndInitialize() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Load stored credentials
    storedUsername = prefs.getString('kaidose_user');
    storedPassword = prefs.getString('kaidose_pass');

    // Get today's date as a string
    String today = DateTime.now().toString().substring(0, 10); // YYYY-MM-DD format
    String? lastLoginDate = prefs.getString('kaidose_last_login_date');

    // Check if user logged in today
    bool loggedInToday = (lastLoginDate == today);

    setState(() {
      isCheckingLoginState = false;
      shouldGoToHome = loggedInToday;
    });

    if (widget.skipAnimation) {
      if (shouldGoToHome) {
        // Skip animation, go directly to UserAccount
        Navigator.pushReplacementNamed(context, '/user-account');
      } else {
        // Skip animation, show login form
        moveToTop = true;
        showForm = true;
        _drawController.forward();
        _formController.forward();
      }
    } else {
      // Show animation regardless
      _startAnimation();
    }
  }

  void _startAnimation() {
    _drawController.forward().whenComplete(() async {
      setState(() {
        moveToTop = true;
      });

      await Future.delayed(const Duration(milliseconds: 2000));

      if (shouldGoToHome) {
        // Fade out the title and go to Home
        _fadeController.forward().whenComplete(() {
          Navigator.pushReplacementNamed(context, '/user-account');
        });
      } else {
        // Show login form
        setState(() {
          showForm = true;
        });
        _formController.forward();
      }
    });
  }

  Future<void> _loadStoredCredentials() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      storedUsername = prefs.getString('kaidose_user');
      storedPassword = prefs.getString('kaidose_pass');
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

  void _attemptLogin() async {
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

    if (storedUsername == null || storedPassword == null) {
      setState(() {
        loginError = 'No account found. Please create an account.';
      });
      return;
    }

    if (inputUser == storedUsername && inputPass == storedPassword) {
      // Save today's date as login date
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String today = DateTime.now().toString().substring(0, 10); // YYYY-MM-DD format
      await prefs.setString('kaidose_last_login_date', today);

      Navigator.pushReplacementNamed(context, '/user-account');
    } else {
      setState(() {
        loginError = 'Incorrect username or password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const titleText = 'Kaidose';
    const slackeyStyle = TextStyle(
      fontFamily: 'Slackey',
      fontSize: 64,
      color: Colors.cyan,
    );
    const formTitleStyle = TextStyle(
      fontFamily: 'Slackey',
      fontSize: 24,
      color: Colors.cyan,
    );

    // Show loading while checking login state
    if (isCheckingLoginState) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Kaidose title that draws and then moves to top, with fade animation
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
                        child: Text(titleText, style: slackeyStyle),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Login form fades in
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
                      // "Login to Kaidose"
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          'Login to Kaidose',
                          style: formTitleStyle,
                        ),
                      ),

                      // Username field
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: TextField(
                          controller: _usernameController,
                          cursorColor: Colors.black,

                          decoration: InputDecoration(
                            hintText: 'Username',
                            focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.black,
                                )
                            ),
                            border: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.black,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Password field
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.black,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Login button below password box
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                          onPressed: _attemptLogin,
                          child: const Text('Login',
                              style: TextStyle(color: Colors.white)
                          ),
                        ),
                      ),

                      if (loginError.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          loginError,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Divider between inputs and buttons
                      const Divider(
                        color: Colors.grey,
                        thickness: 1,
                        indent: 40,
                        endIndent: 40,
                      ),

                      const SizedBox(height: 20),

                      // Forgot password + Create account
                      TextButton(
                        onPressed: () {
                          // TODO: Add forgot password functionality
                        },
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),

                      const SizedBox(height: 8),

                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const CreateAccount()),
                          );
                        },
                        child: const Text('Create Account',
                            style: TextStyle(color: Colors.white)
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
}