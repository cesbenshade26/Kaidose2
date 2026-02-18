import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'DailyData.dart';
import 'InsideDaily.dart';
import 'DailyTransitions.dart';
import 'DailyList.dart';

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
  XFile? _selectedImage;
  XFile? _selectedVideo;
  VideoPlayerController? _videoController;

  @override
  void dispose() {
    _entryController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _handleMediaAttach(XFile? image, XFile? video, VideoPlayerController? controller) {
    setState(() {
      if (image != null) {
        _selectedImage = image;
        _selectedVideo = null;
        _videoController?.dispose();
        _videoController = null;
      } else if (video != null) {
        _selectedVideo = video;
        _selectedImage = null;
        _videoController?.dispose();
        _videoController = controller;
      }
    });
  }

  void _handleMediaRemove() {
    setState(() {
      _selectedImage = null;
      _selectedVideo = null;
    });
    _videoController?.dispose();
    _videoController = null;
  }

  void _handleSend() {
    final message = _entryController.text.trim();
    if (message.isNotEmpty || _selectedImage != null || _selectedVideo != null) {
      setState(() {
        _showOverlay = false;
      });

      // Add message with media to InsideDaily after overlay closes
      Future.delayed(const Duration(milliseconds: 100), () {
        _insideDailyKey.currentState?.addPromptMessageWithMedia(
          message,
          _selectedImage?.path,
          _selectedVideo?.path,
        );
      });
    }
  }

  void _handleBack() async {
    // Unmark as viewed so they have to see the prompt again
    await DailyList.unmarkAsViewed(widget.daily.id);
    if (mounted) {
      Navigator.pop(context);
    }
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
            selectedImage: _selectedImage,
            selectedVideo: _selectedVideo,
            videoController: _videoController,
            onMediaRemove: _handleMediaRemove,
            onMediaAttach: _handleMediaAttach,
          ),
      ],
    );
  }
}