import 'package:flutter/material.dart';
import 'AddDailyMessage.dart';

/// Everything the "+" on the Dailies header can start.
enum AddOption { dailyMessage, newDaily, clip, yourDaily, dailyBubble }

/// Pops up the create sheet. Resolves to the option that should be handled
/// by the caller (everything except Daily Message, which is handled inside
/// the sheet itself), or null if the sheet was dismissed or finished.
///
/// The rest of the screen is dimmed so the sheet is the only thing in focus.
Future<AddOption?> showAddSheet(BuildContext context) {
  return showModalBottomSheet<AddOption>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withOpacity(0.55),
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => const _AddSheet(),
  );
}

enum _SheetPage { menu, dailyMessage }

class _AddSheet extends StatefulWidget {
  const _AddSheet();

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  _SheetPage _page = _SheetPage.menu;

  static const _items = <_AddItem>[
    _AddItem(AddOption.dailyMessage, Icons.chat_bubble_outline, 'Daily Message'),
    _AddItem(AddOption.newDaily, Icons.wb_sunny_outlined, 'New Daily'),
    _AddItem(AddOption.clip, Icons.videocam_outlined, 'Clip'),
    _AddItem(AddOption.yourDaily, Icons.photo_camera_outlined, 'Your Daily'),
    _AddItem(AddOption.dailyBubble, Icons.bubble_chart_outlined, 'Daily Bubble'),
  ];

  void _select(AddOption option) {
    if (option == AddOption.dailyMessage) {
      // Stays in this same sheet: it just grows into the compose view.
      FocusScope.of(context).unfocus();
      setState(() => _page = _SheetPage.dailyMessage);
    } else {
      Navigator.pop(context, option);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Rides above the keyboard, and never grows past the screen.
    final maxHeight = (media.size.height -
        media.viewInsets.bottom -
        media.padding.top) *
        0.96;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                // Height animates between the short menu and the taller
                // compose view; only the incoming page is laid out, and it
                // fades in while the sheet resizes.
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeIn,
                    layoutBuilder: (current, previous) =>
                    current ?? const SizedBox.shrink(),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: _page == _SheetPage.menu
                        ? _buildMenu(context)
                        : AddDailyMessage(
                      key: const ValueKey('dailyMessage'),
                      onBack: () =>
                          setState(() => _page = _SheetPage.menu),
                      onClose: () => Navigator.pop(context),
                      onSent: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    return Column(
      key: const ValueKey('menu'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title + close
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Add',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        for (final item in _items) _buildRow(item),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildRow(_AddItem item) {
    return InkWell(
      onTap: () => _select(item.option),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, color: Colors.cyan, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

class _AddItem {
  final AddOption option;
  final IconData icon;
  final String title;

  const _AddItem(this.option, this.icon, this.title);
}