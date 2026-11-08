import 'dart:io';
import 'package:flutter/material.dart';
import 'ChatTarget.dart';
import 'UnifiedMediaPicker.dart';

/// Pick a wallpaper for the group (everyone in the group sees it).
class GroupWallpaperScreen extends StatefulWidget {
  final ChatTarget target;
  final String? currentUrl;
  final String myUsername;

  const GroupWallpaperScreen({
    Key? key,
    required this.target,
    required this.currentUrl,
    required this.myUsername,
  }) : super(key: key);

  @override
  State<GroupWallpaperScreen> createState() => _GroupWallpaperScreenState();
}

class _GroupWallpaperScreenState extends State<GroupWallpaperScreen> {
  File? _picked;
  bool _saving = false;

  Future<void> _save() async {
    if (_picked == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.target
          .setWallpaper(_picked, byUsername: widget.myUsername);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not set wallpaper: $e')));
    }
  }

  Future<void> _remove() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.target.setWallpaper(null, byUsername: widget.myUsername);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Widget _sampleBubble(String text, {required bool mine}) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: Border.all(color: Colors.cyan.withOpacity(0.25)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _preview() {
    final ImageProvider? image = _picked != null
        ? FileImage(_picked!)
        : (widget.currentUrl != null ? NetworkImage(widget.currentUrl!) : null);

    return Container(
      height: 190,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[300]!),
        image: image != null
            ? DecorationImage(image: image, fit: BoxFit.cover)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _sampleBubble('How does this look?', mine: false),
            _sampleBubble('Love it', mine: true),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasWallpaper = widget.currentUrl != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Wallpaper',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          if (hasWallpaper && _picked == null)
            TextButton(
              onPressed: _saving ? null : _remove,
              style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
              child: const Text('Remove'),
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _preview(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _picked != null
                            ? 'Looks good? Set it for the whole group.'
                            : widget.target.isGroup
                            ? 'Everyone in the group sees this wallpaper.'
                            : 'You and your friend both see this wallpaper.',
                        style:
                        TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ),
                    if (_picked != null)
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Set wallpaper'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => UnifiedMediaPickerPanel(
                    height: c.maxHeight,
                    title: 'Photos',
                    initialFilter: MediaFilter.photos,
                    allowFilterToggle: false,
                    singleSelect: true,
                    showDraw: false,
                    onDrawTap: () {},
                    onClose: () => Navigator.pop(context),
                    onMediaSelected: (items) {
                      if (items.isEmpty) return;
                      setState(() => _picked = items.first.file);
                    },
                  ),
                ),
              ),
            ],
          ),
          if (_saving)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.7),
                child: const Center(
                    child: CircularProgressIndicator(color: Colors.cyan)),
              ),
            ),
        ],
      ),
    );
  }
}