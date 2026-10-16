import 'package:flutter/material.dart';
import 'YourDaily.dart';
import 'AddClip.dart';

/// Route name used when an Add screen is pushed on top of the app, so other
/// code can find and close it (see Home.dart).
const String kAddRouteName = 'add';

/// Where the Add sheet's options land when they need a full screen.
/// (Daily Message and Daily Bubble are handled in the sheet itself and New
/// Daily has its own flow, so only these two live here.)
enum AddDestination { clip, yourDaily }

/// One focused full-screen composer, opened from the Add sheet. Each option
/// gets only its own screen — no tab bar — with a close button.
class AddWidget extends StatelessWidget {
  final AddDestination destination;

  const AddWidget({Key? key, required this.destination}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    switch (destination) {
      case AddDestination.clip:
      // AddClipScreen has its own app bar (title + close).
        return const AddClipScreen(closeable: true);
      case AddDestination.yourDaily:
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            foregroundColor: Colors.black,
            elevation: 0,
            centerTitle: true,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.black),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text(
              'Your Daily',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black),
            ),
          ),
          body: const YourDailyWidget(),
        );
    }
  }
}