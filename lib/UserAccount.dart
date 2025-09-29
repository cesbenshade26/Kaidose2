// UserAccount.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'InterestDetector.dart';
import 'Home.dart';

class UserAccount extends StatefulWidget {
  final bool fadeInFromAnimation; // New parameter to detect animation transition

  const UserAccount({Key? key, this.fadeInFromAnimation = false}) : super(key: key);

  @override
  _UserAccountState createState() => _UserAccountState();
}

class _UserAccountState extends State<UserAccount> with TickerProviderStateMixin {
  bool _showInterestDetector = false;
  bool _isLoading = true;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize fade controller if coming from animation
    if (widget.fadeInFromAnimation) {
      _fadeController = AnimationController(
        duration: const Duration(milliseconds: 800),
        vsync: this,
      );
      _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
      );
    }

    _checkFirstTimeLogin();
  }

  Future<void> _checkFirstTimeLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Check if this user has ever completed the interest detector
    bool hasCompletedInterestDetector = prefs.getBool('interest_detector_completed') ?? false;

    setState(() {
      _showInterestDetector = !hasCompletedInterestDetector; // Show if they haven't completed it
      _isLoading = false;
    });

    // Start fade animation if coming from Kaidose animation
    if (widget.fadeInFromAnimation && !_showInterestDetector) {
      // Small delay to let the previous animation settle
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _fadeController.forward();
        }
      });
    }
  }

  void _onInterestDetectorComplete() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Mark that the user has completed the interest detector
    await prefs.setBool('interest_detector_completed', true);

    setState(() {
      _showInterestDetector = false;
    });

    // If we were supposed to fade in, do it now after InterestDetector
    if (widget.fadeInFromAnimation) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _fadeController.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    if (widget.fadeInFromAnimation) {
      _fadeController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_showInterestDetector) {
      return InterestDetector(
        onComplete: _onInterestDetectorComplete,
      );
    } else {
      // Return HomeScreen with or without fade effect
      final homeScreen = const HomeScreen();

      if (widget.fadeInFromAnimation) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: homeScreen,
        );
      } else {
        return homeScreen;
      }
    }
  }
}