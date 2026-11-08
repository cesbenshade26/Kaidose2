import 'dart:io';
import 'package:flutter/material.dart';
import 'DailyBubbleService.dart';
import 'DailyBubbleViewer.dart';

/// Another person's Daily Bubbles, shown on their profile. Looks like the row
/// on your own Profile, but read-only: tap a bubble to watch what's in it
/// (oldest first), no editing. Shows nothing if they have no bubbles.
class UserBubbleRow extends StatefulWidget {
  final String userId;

  const UserBubbleRow({Key? key, required this.userId}) : super(key: key);

  @override
  State<UserBubbleRow> createState() => _UserBubbleRowState();
}

class _UserBubbleRowState extends State<UserBubbleRow> {
  List<DailyBubbleRecord> _bubbles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await DailyBubbleService.loadBubbles(uid: widget.userId);
    if (!mounted) return;
    setState(() => _bubbles = records);
  }

  Future<void> _open(DailyBubbleRecord bubble) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
      const Center(child: CircularProgressIndicator(color: Colors.cyan)),
    );

    final media = await DailyBubbleService.loadBubbleMedia(
      bubbleId: bubble.id,
      uid: widget.userId,
    );

    if (!mounted) return;
    Navigator.pop(context); // close loading spinner

    if (media.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Daily posts in this bubble yet')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DailyBubbleViewer(items: media, bubbleName: bubble.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_bubbles.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: _bubbles.length,
        itemBuilder: (context, i) {
          final b = _bubbles[i];
          final File? cover = b.cover;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _open(b),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                      border: Border.all(
                          color: Colors.cyan.withOpacity(0.55), width: 1.5),
                    ),
                    child: cover != null
                        ? ClipOval(
                      child: Image.file(
                        cover,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      ),
                    )
                        : Icon(Icons.person, color: Colors.grey[400], size: 24),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 60,
                    child: Text(
                      b.name.isNotEmpty ? b.name : 'Bubble',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}