// main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'OpeningScreen.dart';
import 'UserAccount.dart';

void main() async {
  // Ensure Flutter is ready before calling Firebase
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Check if Firebase is already initialized to prevent [core/duplicate-app]
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print("Firebase initialized successfully");
    }
  } catch (e) {
    print("Firebase initialization error: $e");
  }

  runApp(const KaidoseApp());
}

class KaidoseApp extends StatelessWidget {
  const KaidoseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kaidose',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const OpeningScreen(),
        '/user-account': (context) => const UserAccount(),
      },
    );
  }
}