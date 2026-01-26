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
  final GlobalKey<InsideDailyState> _insideDailyKey = GlobalKey<InsideDailyState>();
  bool _showOverlay = true;

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _handleSend() {
    final message = _entryController.text.trim();
    if (message.isNotEmpty) {
      setState(() {
        _showOverlay = false;
      });

      // Add message directly to InsideDaily after overlay closes
      Future.delayed(const Duration(milliseconds: 100), () {
        _insideDailyKey.currentState?.addPromptMessage(message);
      });
    }
  }

  void _handleBack() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InsideDaily(
          key: _insideDailyKey,
          daily: widget.daily,
        ),
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