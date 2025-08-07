// main.dart
import 'package:flutter/material.dart';
import 'OpeningScreen.dart';
import 'UserAccount.dart';

void main() {
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
      }, // App starts here
    );
  }
}