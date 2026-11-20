import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'DailyData.dart';
import 'InsideArchive.dart' show SavedPostsList;
import 'SavedItemStorage.dart';
import 'SettingsWidgets.dart';

/// Inside one of your Dailies → Saved: the posts from this Daily you've
/// saved (only you see this), newest saved first, as profile-style cards.
/// Hold one to move it into a folder or unsave it.
class DailySavedScreen extends StatelessWidget {
  final DailyData daily;
  const DailySavedScreen({Key? key, required this.daily}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SavedItems.start();
    return Scaffold(
      backgroundColor: kc.background,
      appBar: AppBar(
        backgroundColor: kc.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: SettingsStyle.ink),
        centerTitle: true,
        title: Column(
          children: [
            Text('Saved',
                style: TextStyle(
                    color: SettingsStyle.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            Text(daily.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: SettingsStyle.subtle,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      body: SavedPostsList(
        refs: () => SavedItems.inDaily(daily.id),
        emptyText: 'Tap the bookmark on a post in this Daily to save it here.',
      ),
    );
  }
}