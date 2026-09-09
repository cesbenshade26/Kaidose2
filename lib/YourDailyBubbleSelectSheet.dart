import 'package:flutter/material.dart';
import 'dart:io';
import 'YourDailyBubbles.dart';

/// Bottom sheet shown after posting/sharing a Your Daily, letting the user
/// optionally attach the photo to one or more existing Daily Bubbles.
///
/// Only ever shown when at least one Daily Bubble exists — if there are
/// none, the caller should skip straight to [onPost] instead.
///
/// Dismiss via the back arrow or by swiping the sheet down (default
/// bottom-sheet drag-to-dismiss). "Post" runs [onPost] — the actual post
/// action — regardless of whether any bubbles are checked, then attaches
/// the photo to whichever bubbles were checked.
class YourDailyBubbleSelectSheet extends StatefulWidget {
  final File photo;
  final Future<void> Function() onPost;

  const YourDailyBubbleSelectSheet({
    Key? key,
    required this.photo,
    required this.onPost,
  }) : super(key: key);

  @override
  State<YourDailyBubbleSelectSheet> createState() =>
      _YourDailyBubbleSelectSheetState();
}

class _YourDailyBubbleSelectSheetState
    extends State<YourDailyBubbleSelectSheet> {
  late List<bool> _checked;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _checked = List<bool>.filled(YourDailyBubbleManager.bubbles.length, false);
  }

  Future<void> _post() async {
    if (_isPosting) return;
    setState(() => _isPosting = true);

    await widget.onPost();

    for (int i = 0; i < YourDailyBubbleManager.bubbles.length; i++) {
      if (i < _checked.length && _checked[i]) {
        await YourDailyBubbleManager.addPhotoToBubble(i, widget.photo);
      }
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar — also indicates it can be swiped down to dismiss
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back, size: 24),
              ),
              const Expanded(
                child: Text(
                  'Add to Daily Bubbles',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 24), // balances the back arrow
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Optional — Post works either way',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: YourDailyBubbleManager.bubbles.length,
              itemBuilder: (context, index) {
                final bubble = YourDailyBubbleManager.bubbles[index];
                return CheckboxListTile(
                  value: _checked[index],
                  onChanged: (val) {
                    setState(() => _checked[index] = val ?? false);
                  },
                  title: Text(
                    bubble.name.isNotEmpty ? bubble.name : 'New',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  secondary: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.cyan.withOpacity(0.2),
                    ),
                    child: bubble.cover != null
                        ? ClipOval(
                      child: Image.file(
                        bubble.cover!,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                      ),
                    )
                        : const Icon(Icons.person, color: Colors.cyan),
                  ),
                  activeColor: Colors.cyan,
                  controlAffinity: ListTileControlAffinity.trailing,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isPosting ? null : _post,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isPosting
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
                  : const Text(
                'Post',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 12),
        ],
      ),
    );
  }
}