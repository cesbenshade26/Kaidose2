// UserAccount.dart
import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart'; // Commented out for now
// import 'InterestDetector.dart'; // Commented out for now
import 'Home.dart';

class UserAccount extends StatefulWidget {
  final bool fadeInFromAnimation;
  const UserAccount({Key? key, this.fadeInFromAnimation = false}) : super(key: key);

  @override
  _UserAccountState createState() => _UserAccountState();
}

class _UserAccountState extends State<UserAccount> with TickerProviderStateMixin {
  // bool _showInterestDetector = false; // Commented out
  bool _isLoading = false; // Set to false since we aren't "loading" prefs anymore

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    // Skip the check and just play the fade-in
    _fadeController.forward();

    /* // PREVIOUS INTEREST DETECTOR LOGIC - SAVE FOR LATER
    _checkFirstTimeLogin();
    */
  }

  /*
  Future<void> _checkFirstTimeLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool hasCompleted = prefs.getBool('interest_detector_completed') ?? false;
    setState(() {
      _showInterestDetector = !hasCompleted;
      _isLoading = false;
    });
    if (widget.fadeInFromAnimation && !_showInterestDetector) {
      _fadeController.forward();
    }
  }

  void _onInterestDetectorComplete() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interest_detector_completed', true);
    setState(() { _showInterestDetector = false; });
  }
  */

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    /*
    if (_showInterestDetector) {
      return InterestDetector(onComplete: _onInterestDetectorComplete);
    }
    */

    // Defaulting to the HomeScreen
    return FadeTransition(
      opacity: _fadeAnimation,
      child: const HomeScreen(fadeInFromAnimation: false),
    );
  }
}