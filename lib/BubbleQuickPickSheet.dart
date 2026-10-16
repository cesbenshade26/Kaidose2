import 'package:flutter/material.dart';
import 'YourDailyBubbles.dart';

/// Shown when the "Your Daily" checkbox is checked in the Send to Daily
/// sheet, letting the user optionally pick ONE Daily Bubble to also add
/// the clip to. Since it's opened via showModalBottomSheet from inside
/// another bottom sheet, it stacks on top and dims everything below it
/// (the app content AND the sheet that opened it) for free.
///
/// Tapping a bubble selects it and closes immediately, returning that
/// bubble's id to the caller. Closing without picking one (X button, or
/// the default swipe-down-to-dismiss) returns null — the caller's Your
/// Daily send just proceeds without a bubble attached.
Future<String?> showBubbleQuickPickSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _BubbleQuickPickSheet(),
  );
}

class _BubbleQuickPickSheet extends StatefulWidget {
  const _BubbleQuickPickSheet();

  @override
  State<_BubbleQuickPickSheet> createState() => _BubbleQuickPickSheetState();
}

class _BubbleQuickPickSheetState extends State<_BubbleQuickPickSheet> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Refresh from Firestore in case this is opened before the user has
    // ever visited Profile this session (where bubbles normally load).
    await YourDailyBubbleManager.loadBubblesFromFirestore();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final bubbles = YourDailyBubbleManager.bubbles;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header — title + X to close without picking
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add to a Daily Bubble',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close, color: Colors.grey[600], size: 22),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEEEEEE)),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.deepPurple),
                ),
              )
            else if (bubbles.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No Daily Bubbles yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: bubbles.length,
                  itemBuilder: (context, index) {
                    final bubble = bubbles[index];
                    return ListTile(
                      onTap: () => Navigator.pop(context, bubble.id),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.deepPurple.withOpacity(0.15),
                        ),
                        child: bubble.cover != null
                            ? ClipOval(
                          child: Image.file(
                            bubble.cover!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          ),
                        )
                            : const Icon(Icons.auto_awesome, color: Colors.deepPurple),
                      ),
                      title: Text(
                        bubble.name.isNotEmpty ? bubble.name : 'New',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}