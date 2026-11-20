import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'DailyCoverData.dart';

/// Owner-only switch: "AI cover captions" on or off for one Daily.
///
/// On (the default): the cover shows an AI-written hook line above the
/// photo, unless the owner wrote their own for that day.
/// Off: covers show only hooks the owner wrote; otherwise no line at all.
///
/// Drop it anywhere in the Daily's settings, e.g.
///   DailyAiHooksSwitch(dailyId: daily.id, accentColor: dailyColor)
class DailyAiHooksSwitch extends StatelessWidget {
  final String dailyId;
  final Color accentColor;

  const DailyAiHooksSwitch({
    Key? key,
    required this.dailyId,
    required this.accentColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: DailyCoverService.watchAiHooksEnabled(dailyId),
      builder: (context, snap) {
        final enabled = snap.data ?? true;
        return SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          activeColor: accentColor,
          title: const Text(
            'AI cover captions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'A short line written about the cover photo. Captions you write '
                'in the schedule always show instead.',
            style: TextStyle(fontSize: 12.5, color: kc.grey(600)),
          ),
          value: enabled,
          onChanged: snap.hasData
              ? (v) async {
            try {
              await DailyCoverService.setAiHooksEnabled(dailyId, v);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Couldn't save that. Try again."),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }
              : null,
        );
      },
    );
  }
}