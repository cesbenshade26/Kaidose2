import 'package:flutter/material.dart';
import 'DailyData.dart';
import 'InsideDaily.dart';
import 'DailyTransitions.dart';

class UponOpeningDaily extends StatefulWidget {
  final DailyData daily;

  const UponOpeningDaily({
    Key? key,
    required this.daily,
  }) : super(key: key);

  @override
  State<UponOpeningDaily> createState() => _UponOpeningDailyState();
}

class _UponOpeningDailyState extends State<UponOpeningDaily> {
  final TextEditingController _entryController = TextEditingController();
  bool _showOverlay = true;

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _handleSend() {
    setState(() {
      _showOverlay = false;
    });
  }

  void _handleBack() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InsideDaily(daily: widget.daily),
        if (_showOverlay)
          DailyPromptOverlay(
            dailyTitle: widget.daily.title,
            dailyEntryPrompt: widget.daily.dailyEntryPrompt,
            entryController: _entryController,
            onSend: _handleSend,
            onBack: _handleBack,
          ),
      ],
    );
  }
}