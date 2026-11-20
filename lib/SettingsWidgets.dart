import 'package:flutter/material.dart';
import 'AppColors.dart';

/// The look shared by every Settings page: a light grey page, white
/// rounded groups with a small heading above each, and plain rows (a
/// simple dark icon, the title, a chevron). Cyan is kept for things you
/// act on (switches, buttons), not decoration.
class SettingsStyle {
  SettingsStyle._();

  // Live: they follow light/dark mode (exactly today's colors in light).
  static Color get page =>
      AppTheme.isDark ? kc.background : kc.adapt(const Color(0xFFF4F5F7));
  static Color get ink => kc.adapt(const Color(0xFF2E2E2E));
  static Color get subtle => kc.adapt(const Color(0xFF8A8F98));
  static Color get danger =>
      AppTheme.isDark ? const Color(0xFFFF6369) : const Color(0xFFE5484D);
}

/// A settings page: app bar + scrolling list of [children].
class SettingsPage extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsPage({Key? key, required this.title, required this.children})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SettingsStyle.page,
      appBar: AppBar(
        title: Text(title,
            style: TextStyle(
                color: SettingsStyle.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: SettingsStyle.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: SettingsStyle.ink),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: children,
      ),
    );
  }
}

/// A white rounded group of rows, with an optional heading above and a
/// small note below.
class SettingsGroup extends StatelessWidget {
  final String? title;
  final String? footer;
  final List<Widget> children;

  const SettingsGroup({
    Key? key,
    this.title,
    this.footer,
    required this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Divider(
            height: 1, thickness: 0.5, indent: 52, color: kc.adapt(const Color(0xFFE6E7EA))));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
              child: Text(
                title!,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: SettingsStyle.subtle,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: kc.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: rows),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text(footer!,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.35, color: SettingsStyle.subtle)),
            ),
        ],
      ),
    );
  }
}

/// One row: icon square, title (+ optional subtitle), and on the right
/// either [value] text, a custom [trailing], or a chevron.
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool showChevron;

  const SettingsTile({
    Key? key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.showChevron = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = danger ? SettingsStyle.danger : SettingsStyle.ink;
    final iconColor = danger ? SettingsStyle.danger : kc.adapt(const Color(0xFF55595F));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          color: color)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: 12.5, color: SettingsStyle.subtle)),
                  ],
                ],
              ),
            ),
            if (value != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 14.5, color: SettingsStyle.subtle),
                  ),
                ),
              ),
            if (trailing != null)
              trailing!
            else if (showChevron && onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.chevron_right_rounded,
                    size: 22,
                    color: danger
                        ? SettingsStyle.danger.withOpacity(0.5)
                        : kc.adapt(const Color(0xFFC4C7CC))),
              ),
          ],
        ),
      ),
    );
  }
}

/// A plain rounded dialog matching the settings look. Returns true when
/// [confirmLabel] is tapped.
Future<bool> settingsConfirm(
    BuildContext context, {
      required String title,
      required String message,
      required String confirmLabel,
      bool danger = false,
      String cancelLabel = 'Cancel',
    }) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kc.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title,
          style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: SettingsStyle.ink)),
      content: Text(message,
          style: TextStyle(
              fontSize: 14.5, height: 1.4, color: kc.adapt(const Color(0xFF555A61)))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel,
              style: TextStyle(color: SettingsStyle.ink)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: danger ? SettingsStyle.danger : SettingsStyle.subtle)),
        ),
      ],
    ),
  );
  return ok == true;
}

// ─── Mute / pause for a while ─────────────────────────────────────────────────

/// What was picked in [showMuteForSheet]: a length of time, or null for
/// "until I turn it back on".
class MuteFor {
  final Duration? duration;
  const MuteFor(this.duration);

  /// When it ends, or null if it doesn't.
  DateTime? get until =>
      duration == null ? null : DateTime.now().add(duration!);
}

/// Asked when muting a chat or pausing notifications: for 1 hour, for 24
/// hours, or until turned back on. Null if they cancel (nothing changes).
Future<MuteFor?> showMuteForSheet(
    BuildContext context, {
      required String title,
      String? message,
    }) {
  Widget option(BuildContext ctx, String label, Duration? d) => InkWell(
    onTap: () => Navigator.pop(ctx, MuteFor(d)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: SettingsStyle.ink)),
          ),
        ],
      ),
    ),
  );

  return showModalBottomSheet<MuteFor>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: kc.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Column(
                      children: [
                        Text(title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: SettingsStyle.subtle)),
                        if (message != null) ...[
                          const SizedBox(height: 3),
                          Text(message,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: SettingsStyle.subtle)),
                        ],
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 0.5, color: kc.adapt(const Color(0xFFE6E7EA))),
                  option(ctx, 'For 1 hour', const Duration(hours: 1)),
                  Divider(height: 1, thickness: 0.5, color: kc.adapt(const Color(0xFFE6E7EA))),
                  option(ctx, 'For 24 hours', const Duration(hours: 24)),
                  Divider(height: 1, thickness: 0.5, color: kc.adapt(const Color(0xFFE6E7EA))),
                  option(ctx, 'Until I turn it back on', null),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: kc.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(ctx),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    child: Text('Cancel',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: SettingsStyle.ink)),
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

/// "until 4:12 PM", or "until tomorrow 9:30 AM".
String untilLabel(DateTime t) {
  final now = DateTime.now();
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final time = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? 'until $time' : 'until tomorrow $time';
}