import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'GroupAvatar.dart';
import 'SafetyService.dart';

// ─── Small shared pieces ──────────────────────────────────────────────────────

Widget _handle() => Center(
  child: Container(
    width: 40,
    height: 4,
    margin: const EdgeInsets.only(top: 10, bottom: 8),
    decoration: BoxDecoration(
      color: Colors.grey[300],
      borderRadius: BorderRadius.circular(2),
    ),
  ),
);

Widget _sheet(BuildContext context, List<Widget> children) {
  return Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
    child: Column(mainAxisSize: MainAxisSize.min, children: [_handle(), ...children]),
  );
}

/// One row in a safety menu.
class SafetyMenuItem {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;

  const SafetyMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });
}

/// A plain bottom-sheet menu of [items]. Tapping one closes the sheet and
/// runs it.
class SafetyMenu {
  static Future<void> show(BuildContext context, List<SafetyMenuItem> items,
      {String? title}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _sheet(sheetContext, [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        for (final it in items)
          ListTile(
            leading: Icon(it.icon,
                color: it.destructive ? Colors.red : Colors.black87),
            title: Text(it.label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: it.destructive ? Colors.red : Colors.black87,
                )),
            subtitle: it.subtitle == null
                ? null
                : Text(it.subtitle!,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
            onTap: () {
              Navigator.pop(sheetContext);
              it.onTap();
            },
          ),
      ]),
    );
  }
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: Colors.black87,
    duration: const Duration(seconds: 2),
  ));
}

Future<String> _usernameOf(String uid, String? known) async {
  if (known != null && known.isNotEmpty) return known;
  try {
    final d = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final n = d.data()?['username'] as String?;
    if (n != null && n.isNotEmpty) return n;
  } catch (_) {}
  return 'this person';
}

// ─── Block ────────────────────────────────────────────────────────────────────

class BlockFlow {
  /// Asks first, then blocks. Returns true if they were blocked.
  static Future<bool> confirmAndBlock(BuildContext context, String uid,
      {String? username}) async {
    final name = await _usernameOf(uid, username);
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Block $name?'),
        content: const Text(
          "They won't be able to find you, see your profile, clips or "
              'story, or message you. You\'ll stop being friends, and their '
              "posts won't show up for you. They won't be told.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    HapticFeedback.mediumImpact();
    try {
      await SafetyService.instance.block(uid);
      if (context.mounted) _toast(context, 'Blocked $name');
      return true;
    } catch (e) {
      if (context.mounted) _toast(context, "Couldn't block. Try again.");
      return false;
    }
  }

  static Future<void> unblock(BuildContext context, String uid,
      {String? username}) async {
    final name = await _usernameOf(uid, username);
    try {
      await SafetyService.instance.unblock(uid);
      if (context.mounted) _toast(context, 'Unblocked $name');
    } catch (_) {
      if (context.mounted) _toast(context, "Couldn't unblock. Try again.");
    }
  }
}

// ─── The "⋯" menu on someone's profile ───────────────────────────────────────

class UserActions {
  /// Mute, hide your story, remove friend, report and block.
  static Future<void> show(BuildContext context,
      {required String uid, String? username}) async {
    final s = SafetyService.instance;
    final name = await _usernameOf(uid, username);
    final friends = await s.areFriends(uid).catchError((_) => false);
    if (!context.mounted) return;

    final blocked = s.isBlocked(uid);
    final items = <SafetyMenuItem>[
      if (!blocked) ...[
        SafetyMenuItem(
          icon: s.isMuted(uid)
              ? Icons.volume_up_outlined
              : Icons.volume_off_outlined,
          label: s.isMuted(uid) ? 'Unmute' : 'Mute',
          subtitle: s.isMuted(uid)
              ? "Show their story and clips again"
              : "Hide their story and clips. They won't know.",
          onTap: () async {
            final mute = !s.isMuted(uid);
            await s.setMuted(uid, mute);
            if (context.mounted) {
              _toast(context, mute ? 'Muted $name' : 'Unmuted $name');
            }
          },
        ),
        SafetyMenuItem(
          icon: s.isStoryHiddenFrom(uid)
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          label: s.isStoryHiddenFrom(uid)
              ? 'Show my story to $name'
              : 'Hide my story from $name',
          onTap: () async {
            final hide = !s.isStoryHiddenFrom(uid);
            await s.setStoryHidden(uid, hide);
            if (context.mounted) {
              _toast(
                  context,
                  hide
                      ? "$name won't see your story"
                      : '$name can see your story again');
            }
          },
        ),
        if (friends)
          SafetyMenuItem(
            icon: Icons.person_remove_outlined,
            label: 'Remove friend',
            onTap: () => _confirmRemoveFriend(context, uid, name),
          ),
      ],
      SafetyMenuItem(
        icon: Icons.flag_outlined,
        label: 'Report',
        destructive: true,
        onTap: () => ReportSheet.show(
          context,
          target: ReportTarget.user,
          targetId: uid,
          ownerUid: uid,
          ownerName: name,
          path: 'users/$uid',
        ),
      ),
      blocked
          ? SafetyMenuItem(
        icon: Icons.lock_open_rounded,
        label: 'Unblock',
        onTap: () => BlockFlow.unblock(context, uid, username: name),
      )
          : SafetyMenuItem(
        icon: Icons.block_rounded,
        label: 'Block',
        destructive: true,
        onTap: () => BlockFlow.confirmAndBlock(context, uid, username: name),
      ),
    ];
    await SafetyMenu.show(context, items, title: name);
  }

  static Future<void> _confirmRemoveFriend(
      BuildContext context, String uid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Remove $name?'),
        content: const Text(
            "You'll stop being friends. To be friends again, one of you will "
                'need to send a new friend request.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SafetyService.instance.removeFriend(uid);
      if (context.mounted) _toast(context, 'Removed $name');
    } catch (_) {
      if (context.mounted) _toast(context, "Couldn't remove. Try again.");
    }
  }
}

// ─── Report ───────────────────────────────────────────────────────────────────

class ReportSheet {
  /// Pick a reason, add details if you want, send. Afterwards offers to
  /// block the person too.
  static Future<void> show(
      BuildContext context, {
        required ReportTarget target,
        required String targetId,
        required String ownerUid,
        String? ownerName,
        String? path,
        String? preview,
        Map<String, dynamic>? extra,
      }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportSheet(
        target: target,
        targetId: targetId,
        ownerUid: ownerUid,
        ownerName: ownerName,
        path: path,
        preview: preview,
        extra: extra,
      ),
    );
  }
}

class _ReportSheet extends StatefulWidget {
  final ReportTarget target;
  final String targetId;
  final String ownerUid;
  final String? ownerName;
  final String? path;
  final String? preview;
  final Map<String, dynamic>? extra;

  const _ReportSheet({
    required this.target,
    required this.targetId,
    required this.ownerUid,
    this.ownerName,
    this.path,
    this.preview,
    this.extra,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final TextEditingController _note = TextEditingController();
  bool _sending = false;
  bool _done = false;

  String get _what {
    switch (widget.target) {
      case ReportTarget.user:
        return 'account';
      case ReportTarget.clip:
        return 'clip';
      case ReportTarget.dailyMessage:
        return 'post';
      case ReportTarget.comment:
        return 'comment';
      case ReportTarget.chatMessage:
        return 'message';
      case ReportTarget.story:
        return 'story';
      case ReportTarget.daily:
        return 'Daily';
      case ReportTarget.groupChat:
        return 'group';
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reason == null || _sending) return;
    setState(() => _sending = true);
    try {
      await SafetyService.instance.report(
        target: widget.target,
        targetId: widget.targetId,
        ownerUid: widget.ownerUid,
        reason: _reason!,
        note: _note.text,
        path: widget.path,
        preview: widget.preview,
        extra: widget.extra,
      );
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't send the report. Try again.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 12),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _done
                ? _thanks()
                : (_reason == null ? _reasons() : _details()),
          ),
        ),
      ),
    );
  }

  Widget _title(String text, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub,
                style: TextStyle(
                    fontSize: 13.5, color: Colors.grey[600], height: 1.3)),
          ],
        ],
      ),
    );
  }

  Widget _reasons() {
    final reasons = widget.target == ReportTarget.user
        ? ReportReason.values
        : ReportReason.values
        .where((r) => r != ReportReason.underage)
        .toList();
    return Column(
      key: const ValueKey('reasons'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _handle(),
        _title('Report this $_what',
            sub: "Why are you reporting it? Your report is anonymous."),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final r in reasons)
                ListTile(
                  title: Text(r.label,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w500)),
                  trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
                  onTap: () => setState(() => _reason = r),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _details() {
    return Column(
      key: const ValueKey('details'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _handle(),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              onPressed: () => setState(() => _reason = null),
            ),
            Expanded(
              child: Text(_reason!.label,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        if (_reason == ReportReason.selfHarm)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              "If someone is in immediate danger, call your local emergency "
                  "number. In the US you can call or text 988 to reach the "
                  "Suicide & Crisis Lifeline.",
              style: TextStyle(fontSize: 13.5, height: 1.35),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: TextField(
            controller: _note,
            maxLines: 3,
            minLines: 2,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Add details (optional)',
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.red.withOpacity(0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25)),
              ),
              child: _sending
                  ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.4))
                  : const Text('Submit report',
                  style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _thanks() {
    final s = SafetyService.instance;
    final canBlock = widget.ownerUid.isNotEmpty &&
        widget.ownerUid != s.uid &&
        !s.isBlocked(widget.ownerUid);
    final name = widget.ownerName;
    return Column(
      key: const ValueKey('thanks'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _handle(),
        const SizedBox(height: 10),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.cyan.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_rounded, color: Colors.cyan[700], size: 36),
        ),
        const SizedBox(height: 14),
        const Text('Thanks for letting us know',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 6, 32, 18),
          child: Text(
            "We'll review it and take it down if it breaks our Community "
                "Guidelines. They won't know who reported them.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.35),
          ),
        ),
        if (canBlock)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final blocked = await BlockFlow.confirmAndBlock(
                      context, widget.ownerUid,
                      username: name);
                  if (blocked) nav.pop();
                },
                icon: const Icon(Icons.block_rounded, size: 20),
                label: Text(name == null ? 'Block them' : 'Block $name',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25)),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25)),
              ),
              child: const Text('Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Settings: Blocked accounts ───────────────────────────────────────────────

class BlockedAccountsScreen extends StatelessWidget {
  const BlockedAccountsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final s = SafetyService.instance;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Blocked accounts'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: s.changes,
        builder: (context, _, __) {
          final ids = s.blocked.toList();
          if (ids.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block_rounded, size: 56, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text("You haven't blocked anyone",
                        style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: ids.length,
            separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 76),
            itemBuilder: (context, i) => _BlockedRow(uid: ids[i]),
          );
        },
      ),
    );
  }
}

class _BlockedRow extends StatefulWidget {
  final String uid;
  const _BlockedRow({required this.uid});

  @override
  State<_BlockedRow> createState() => _BlockedRowState();
}

class _BlockedRowState extends State<_BlockedRow> {
  String? _name;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _usernameOf(widget.uid, null).then((n) {
      if (mounted) setState(() => _name = n);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          MemberAvatar(userId: widget.uid, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Text(_name ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
              setState(() => _busy = true);
              await BlockFlow.unblock(context, widget.uid, username: _name);
              if (mounted) setState(() => _busy = false);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: BorderSide(color: Colors.grey[300]!),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
  }
}