import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'DailyModeration.dart';
import 'GroupAvatar.dart';

/// The sheet for banning someone from one Daily: how long, and an optional
/// reason. The sheet itself is the confirmation (it says exactly what will
/// happen), so there's no second "are you sure" pop-up.
///
///   final banned = await DailyBanSheet.show(context,
///       dailyId: id, dailyTitle: title, uid: uid, username: name);
class DailyBanSheet extends StatefulWidget {
  final String dailyId;
  final String dailyTitle;
  final String uid;
  final String username;

  const DailyBanSheet({
    Key? key,
    required this.dailyId,
    required this.dailyTitle,
    required this.uid,
    required this.username,
  }) : super(key: key);

  /// True if they were banned.
  static Future<bool> show(
      BuildContext context, {
        required String dailyId,
        required String dailyTitle,
        required String uid,
        required String username,
      }) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DailyBanSheet(
        dailyId: dailyId,
        dailyTitle: dailyTitle,
        uid: uid,
        username: username,
      ),
    );
    return done == true;
  }

  @override
  State<DailyBanSheet> createState() => _DailyBanSheetState();
}

class _BanLength {
  final String label;
  final Duration? duration; // null = permanent
  const _BanLength(this.label, this.duration);
}

class _DailyBanSheetState extends State<DailyBanSheet> {
  static const _lengths = [
    _BanLength('1 hour', Duration(hours: 1)),
    _BanLength('1 day', Duration(days: 1)),
    _BanLength('1 week', Duration(days: 7)),
    _BanLength('30 days', Duration(days: 30)),
    _BanLength('Permanent', null),
  ];

  int _picked = 1; // 1 day
  final TextEditingController _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _ban() async {
    setState(() => _saving = true);
    try {
      await DailyModeration.ban(
        dailyId: widget.dailyId,
        uid: widget.uid,
        username: widget.username,
        duration: _lengths[_picked].duration,
        reason: _reason.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't ban ${widget.username}. Try again.")),
      );
      print('DailyBanSheet: ban failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final length = _lengths[_picked];
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: kc.grey(300),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    MemberAvatar(userId: widget.uid, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ban ${widget.username}?',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'From ${widget.dailyTitle} only',
                            style: TextStyle(
                                fontSize: 13.5, color: kc.grey(600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _label('How long'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _lengths.length; i++)
                      _chip(_lengths[i].label, i == _picked,
                              () => setState(() => _picked = i)),
                  ],
                ),
                const SizedBox(height: 22),
                _label('Reason (optional)'),
                const SizedBox(height: 10),
                TextField(
                  controller: _reason,
                  maxLines: 3,
                  minLines: 2,
                  maxLength: 300,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Only the owner and moderators see this',
                    hintStyle: TextStyle(color: kc.grey(400), fontSize: 14.5),
                    filled: true,
                    fillColor: kc.grey(100),
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Says exactly what happens, so this is the confirmation.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kc.grey(50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kc.grey(200)),
                  ),
                  child: Text(
                    length.duration == null
                        ? "They'll be removed from this Daily and can't post in it, "
                        "add it, or be invited back unless you unban them."
                        : "They'll be removed from this Daily and can't post in it "
                        "or add it again for ${length.label}. After that they "
                        "can rejoin.",
                    style: TextStyle(
                        fontSize: 13, height: 1.35, color: kc.grey(700)),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kc.text,
                          side: BorderSide(color: kc.grey(300)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _ban,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.red.withOpacity(0.5),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _saving
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                            : const Text('Ban',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
  );

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.cyan : kc.grey(100),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : kc.adapt(const Color(0xFF2E2E2E)),
          ),
        ),
      ),
    );
  }
}

/// Kept for any other file that still uses it.
extension StringExtension on String {
  String capitalize() =>
      isEmpty ? this : "${this[0].toUpperCase()}${substring(1)}";
}