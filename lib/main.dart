import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'OpeningScreen.dart';
import 'UserAccount.dart';
import 'EmailVerificationScreen.dart';
import 'ForgotPasswordScreen.dart';
import 'NotificationScreen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // --- FOR TESTING ONLY ---
    // Force a fresh start by ignoring any saved sessions
    Widget initialScreen = const OpeningScreen();

    runApp(KaidoseApp(startScreen: initialScreen));
  } catch (e) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text("Error: $e")))));
  }
}

class KaidoseApp extends StatelessWidget {
  final Widget startScreen;
  const KaidoseApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: startScreen,
      routes: {
        '/opening': (context) => const OpeningScreen(),
        '/user-account': (context) => const UserAccount(),
        '/verify-email': (context) => const EmailVerificationScreen(),
        '/forgot-password': (context) => const ForgotPasswordScreen(),
        '/notifications': (context) => const NotificationsScreen(),
      },
    );
  }
}