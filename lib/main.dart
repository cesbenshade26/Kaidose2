import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'OpeningScreen.dart';
import 'UserAccount.dart';
import 'EmailVerificationScreen.dart';
import 'ForgotPasswordScreen.dart';
import 'NotificationScreen.dart';
import 'NotificationService.dart';
import 'InterestOnboarding.dart';
import 'Home.dart';
import 'AppColors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Light / dark / system choice saved on this phone (see AppColors.dart).
    await AppTheme.load();
    final startScreen = await _pickStartScreen();
    runApp(KaidoseApp(startScreen: startScreen));
  } catch (e) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text("Error: $e")))));
  }
}

/// Where the app opens:
///  - first launch after installing      -> login (signed out)
///  - signed out (tapped Log out)         -> login
///  - signed in, onboarding not finished  -> onboarding
///  - signed in                           -> Home (Dailies). If a notification
///    was tapped to open the app, Home then opens that screen on top.
Future<Widget> _pickStartScreen() async {
  final auth = FirebaseAuth.instance;

  // iPhones keep Firebase sign-ins in the Keychain even after the app is
  // deleted, so a reinstall would otherwise open already signed in. A
  // fresh install always starts at login instead.
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('has_launched_before') != true) {
      await prefs.setBool('has_launched_before', true);
      if (auth.currentUser != null) await auth.signOut();
      return const OpeningScreen();
    }
  } catch (_) {}

  // Wait for Firebase to restore the saved sign-in (usually instant).
  User? user;
  try {
    user = await auth
        .authStateChanges()
        .first
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    user = auth.currentUser;
  }
  if (user == null) return const OpeningScreen();

  // Same check the login screen does. If it can't be read (offline), go
  // to Home rather than holding the app on the splash screen.
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get()
        .timeout(const Duration(seconds: 4));
    if (doc.exists && doc.data()?['onboardingComplete'] != true) {
      return const InterestOnboarding();
    }
  } catch (_) {}

  return const HomeScreen();
}

class KaidoseApp extends StatelessWidget {
  final Widget startScreen;
  const KaidoseApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the light/dark choice changes in Settings. Dark mode
    // stays off (AppTheme.darkModeReady) until every screen is converted.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, _, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: AppTheme.effective,
        // Lets a tapped push notification open the right screen.
        navigatorKey: NotificationService.navigatorKey,
        home: startScreen,
        routes: {
          '/opening': (context) => const OpeningScreen(),
          '/user-account': (context) => const UserAccount(),
          '/verify-email': (context) => const EmailVerificationScreen(),
          '/forgot-password': (context) => const ForgotPasswordScreen(),
          '/notifications': (context) => const NotificationsScreen(),
        },
      ),
    );
  }
}