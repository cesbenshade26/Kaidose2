// UserAccount.dart
import 'package:flutter/material.dart';
import 'InterestDetector.dart';
import 'Home.dart';

class UserAccount extends StatefulWidget {
  const UserAccount({Key? key}) : super(key: key);

  @override
  _UserAccountState createState() => _UserAccountState();
}

class _UserAccountState extends State<UserAccount> {
  bool _showInterestDetector = true;

  void _onInterestDetectorComplete() {
    setState(() {
      _showInterestDetector = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showInterestDetector) {
      return InterestDetector(
        onComplete: _onInterestDetectorComplete,
      );
    } else {
      return const HomeScreen();
    }
  }
}