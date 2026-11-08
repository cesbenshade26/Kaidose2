import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'message_service.dart';

/// Disappearing-message settings for a 1:1 chat. Each person has their own
/// setting; it only changes what YOU see.
class DisappearingMessagesScreen extends StatefulWidget {
  final String friendUserId;
  final String friendUsername;

  const DisappearingMessagesScreen({
    Key? key,
    required this.friendUserId,
    required this.friendUsername,
  }) : super(key: key);

  /// Stored option -> timer chips shown on the screen, in order.
  static const List<MapEntry<String, String>> timers = [
    MapEntry('1h', '1 hour'),
    MapEntry('3h', '3 hours'),
    MapEntry('24h', '24 hours'),
    MapEntry('3d', '3 days'),
    MapEntry('7d', '1 week'),
    MapEntry('30d', '1 month'),
    MapEntry('365d', '1 year'),
  ];

  /// How long after a message has been viewed it disappears, for the timer
  /// options. Null for "off" and "after viewing".
  static Duration? durationFor(String option) =>
      MessageService.durationFor(option);

  /// Short label for the stored option (used on the Manage screen too).
  static String labelFor(String option) {
    for (final t in timers) {
      if (t.key == option) return t.value;
    }
    if (option == 'after_viewing' || option == 'on_close') {
      return 'After viewing';
    }
    return 'Off';
  }

  @override
  State<DisappearingMessagesScreen> createState() =>
      _DisappearingMessagesScreenState();
}

class _DisappearingMessagesScreenState
    extends State<DisappearingMessagesScreen> {
  final MessageService _messageService = MessageService();
  String _selected = 'off';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final option = await _messageService.getChatSettings(widget.friendUserId);
    if (!mounted) return;
    setState(() {
      // The old "on close" option is now "after viewing".
      _selected = option == 'on_close' ? 'after_viewing' : option;
      _isLoading = false;
    });
  }

  Future<void> _choose(String option) async {
    if (option == _selected) return;
    HapticFeedback.selectionClick();
    final previous = _selected;
    setState(() => _selected = option);
    try {
      await _messageService.saveChatSettings(
        recipientUserId: widget.friendUserId,
        deleteOption: option,
      );
    } catch (_) {
      if (mounted) setState(() => _selected = previous);
    }
  }

  bool get _isOff => _selected == 'off';

  String get _summary {
    if (_isOff) {
      return 'Messages stay in your copy of this chat until you delete them.';
    }
    if (_selected == 'after_viewing') {
      return 'Messages disappear from your chat once you\'ve seen them and left.';
    }
    return 'Messages disappear from your chat ${DisappearingMessagesScreen.labelFor(_selected).toLowerCase()} after you\'ve seen them.';
  }

  // ------------------------------------------------------------------ UI

  Widget _hero() {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: _isOff ? Colors.grey[200] : Colors.cyan.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _isOff ? Icons.timer_off_outlined : Icons.timer_outlined,
            size: 42,
            color: _isOff ? Colors.grey[600] : Colors.cyan[700],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _isOff
              ? 'Disappearing messages are off'
              : DisappearingMessagesScreen.labelFor(_selected),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _summary,
            key: ValueKey(_selected),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14.5, height: 1.35, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  /// A full-width choice (After viewing / Never).
  Widget _bigOption({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _selected == value;
    return GestureDetector(
      onTap: () => _choose(value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? Colors.cyan.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.cyan : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected ? Colors.cyan : Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 22, color: selected ? Colors.white : Colors.grey[600]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.cyan[800] : Colors.black87,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: selected ? 1 : 0,
              child:
              const Icon(Icons.check_circle, color: Colors.cyan, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timerChip(String value, String label) {
    final selected = _selected == value;
    return GestureDetector(
      onTap: () => _choose(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.cyan : Colors.grey[100],
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? Colors.cyan : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'Disappearing Messages',
          style: TextStyle(
              color: Colors.black, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const SizedBox(height: 12),
          _hero(),
          const SizedBox(height: 32),

          _sectionLabel('As soon as it\'s seen'),
          _bigOption(
            value: 'after_viewing',
            icon: Icons.visibility_outlined,
            title: 'After viewing',
            subtitle: 'Gone from your chat once you\'ve seen it',
          ),
          const SizedBox(height: 28),

          _sectionLabel('Or after a set time'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final t in DisappearingMessagesScreen.timers)
                _timerChip(t.key, t.value),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 10),
            child: Text(
              'The timer starts when a message has been seen.',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ),
          const SizedBox(height: 28),

          _bigOption(
            value: 'off',
            icon: Icons.all_inclusive,
            title: 'Never',
            subtitle: 'Messages stay until you delete them',
          ),
          const SizedBox(height: 28),

          // What to know
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _note(Icons.people_outline,
                    'This is only your setting. ${widget.friendUsername} chooses their own, and it doesn\'t change what they see.'),
                const SizedBox(height: 12),
                _note(Icons.bookmark_border,
                    'Saved messages are kept. New settings apply to new messages going forward.'),
                const SizedBox(height: 12),
                _note(Icons.screenshot_outlined,
                    'Hidden messages are held securely for 30 days before they\'re permanently deleted. ${widget.friendUsername} can also still screenshot messages.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13.5, height: 1.35, color: Colors.grey[700])),
        ),
      ],
    );
  }
}