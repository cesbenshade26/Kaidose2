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
import 'SafetyService.dart';
import 'DailyPostActivity.dart' show DailyPostVideoCache;
import 'DailiesPreload.dart';
import 'DailyFonts.dart';
import 'CoverJump.dart';
import 'DataSaver.dart';
import 'PrivateInfo.dart';
import 'LikePrefs.dart';
import 'ReduceMotion.dart';
import 'ArchiveStorage.dart';
import 'SavedItemStorage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Light / dark / system choice saved on this phone (see AppColors.dart).
    await AppTheme.load();
    // Blocks, mutes, hidden stories: kept live for the signed-in account.
    SafetyService.instance.start();
    // Your top profile post's video, ready before Profile is opened.
    DailyPostVideoCache.startWarmingTopPost();
    // Dailies (the screen the app opens on): My Dailies, the For You feed
    // and the first cards' covers start loading as soon as someone is
    // signed in, at launch or right after logging in.
    DailiesPreload.start();
    // Daily title fonts (cards + inside a Daily), so titles never show in
    // the default font first. Not awaited: it never delays opening.
    DailyFonts.preload();
    // Which cover posts you've already been taken to (opening a Daily from
    // its cover goes to that post once).
    CoverJump.load();
    // Data saver (Settings → Content & data): cuts video preloading on
    // cellular. Not awaited.
    DataSaver.init();
    // Email, phone and birthday kept private (moves them off the public
    // profile for accounts made before that).
    PrivateInfo.start();
    // Like-count settings (Settings → Privacy → Likes).
    LikePrefs.start();
    // Your Archives folders and saved posts/clips, kept live.
    ArchiveStorage.start();
    SavedItems.start();
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

  // Same check the login screen does. The copy saved on the phone answers
  // instantly; the server is only asked when that copy is missing or says
  // onboarding isn't done (it may be out of date). If it can't be read
  // (offline), go to Home rather than holding the app on the splash screen.
  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
  try {
    final cached = await userRef.get(const GetOptions(source: Source.cache));
    if (cached.exists && cached.data()?['onboardingComplete'] == true) {
      return const HomeScreen();
    }
  } catch (_) {
    // Not saved on this phone yet: ask the server below.
  }
  try {
    final doc = await userRef.get().timeout(const Duration(seconds: 4));
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
    // Rebuilds when the light/dark choice changes in Settings (or the
    // phone's own setting, under "Match phone"). ThemeRebuilder redraws
    // every screen so they all switch together.
    return ThemeRebuilder(
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppTheme.mode,
        builder: (context, _, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          // Page transitions follow the phone's Reduce Motion setting.
          theme: AppTheme.lightTheme.copyWith(
              pageTransitionsTheme: ReduceMotion.transitions(
                  AppTheme.lightTheme.pageTransitionsTheme)),
          darkTheme: AppTheme.darkTheme.copyWith(
              pageTransitionsTheme: ReduceMotion.transitions(
                  AppTheme.darkTheme.pageTransitionsTheme)),
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
      ),
    );
  }
}