import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

/// Horizontally-scrollable row of "share out of the app" actions — the
/// native OS share sheet ("More", same call on iOS and Android — the
/// plugin picks the right native implementation for you) plus a quick
/// "Copy Link". There's no way to enumerate/list individual installed
/// apps ourselves; tapping "More" hands off to the OS, which shows
/// whatever's actually installed.
///
/// Pass [clipId] to have "More" download and share the actual clip video
/// file, and "Copy Link" copy its Storage URL. Pass [fallbackShareText]
/// for a plain-text-only "More" share when there's no clip (Copy Link is
/// hidden in that case, since there's nothing link-like to copy).
class NativeShareBar extends StatefulWidget {
  final String? clipId;
  final String? fallbackShareText;

  const NativeShareBar({
    Key? key,
    this.clipId,
    this.fallbackShareText,
  }) : super(key: key);

  @override
  State<NativeShareBar> createState() => _NativeShareBarState();
}

class _NativeShareBarState extends State<NativeShareBar> {
  bool _isPreparing = false;

  Future<Map<String, String>?> _fetchClipData() async {
    if (widget.clipId == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('clips')
          .doc(widget.clipId)
          .get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      return {
        'videoUrl': data['videoUrl'] as String? ?? '',
        'caption': data['caption'] as String? ?? '',
      };
    } catch (e) {
      print('NativeShareBar: fetch clip error: $e');
      return null;
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    if (widget.clipId == null) return;

    final clip = await _fetchClipData();
    final videoUrl = clip?['videoUrl'] ?? '';

    if (videoUrl.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to copy'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    await Clipboard.setData(ClipboardData(text: videoUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied!'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _shareMore(BuildContext context) async {
    if (_isPreparing) return;
    setState(() => _isPreparing = true);

    try {
      if (widget.clipId != null) {
        final clip = await _fetchClipData();
        final videoUrl = clip?['videoUrl'] ?? '';
        final caption = clip?['caption'] ?? '';

        if (videoUrl.isEmpty) {
          throw Exception('Clip has no video URL');
        }

        // Download the actual video to a temp file so the receiving app
        // gets real media handed to it, not just a link.
        final tempDir = await getTemporaryDirectory();
        final fileName = 'shared_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final localFile = File('${tempDir.path}/$fileName');

        await FirebaseStorage.instance.refFromURL(videoUrl).writeToFile(localFile);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(localFile.path)],
            text: caption.isNotEmpty ? caption : null,
          ),
        );
      } else {
        await SharePlus.instance.share(
          ShareParams(text: widget.fallbackShareText ?? ''),
        );
      }
    } catch (e) {
      print('NativeShareBar: share error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
  }

  Widget _buildBubble({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: isLoading
                  ? const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Colors.cyan, strokeWidth: 2.5),
              )
                  : Icon(icon, color: Colors.grey[800], size: 26),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 64,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    if (widget.clipId != null) {
      items.add(_buildBubble(
        icon: Icons.link,
        label: 'Copy Link',
        onTap: () => _copyLink(context),
      ));
    }

    items.add(_buildBubble(
      icon: Icons.ios_share,
      label: 'More',
      onTap: () => _shareMore(context),
      isLoading: _isPreparing,
    ));

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: items,
      ),
    );
  }
}