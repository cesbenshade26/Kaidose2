import 'package:flutter/material.dart';
import 'Archives.dart';

/// Your saved items and archive folders, on their own screen. Temporarily
/// reached from a button in Settings; it can move to a better spot later.
class SavedScreen extends StatelessWidget {
  const SavedScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Saved'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: const ArchivesView(),
    );
  }
}