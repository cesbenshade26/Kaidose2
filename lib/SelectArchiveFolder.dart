import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'ArchiveStorage.dart';
import 'CreateArchive.dart';
import 'SettingsWidgets.dart';

/// "Save to…": pick Archives folders (any number). For a Daily post in one
/// of your Dailies, [allowDailyOnly] adds "Only in this Daily" (saved in
/// the Daily's Saved, no folder). Returns the chosen folder ids (empty =
/// only in the Daily), or null if they backed out.
Future<List<String>?> showSaveToSheet(
    BuildContext context, {
      List<String> selected = const [],
      bool allowDailyOnly = false,
      bool alreadySaved = false,
    }) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SaveToSheet(
      initial: selected,
      allowDailyOnly: allowDailyOnly,
      alreadySaved: alreadySaved,
    ),
  );
}

class _SaveToSheet extends StatefulWidget {
  final List<String> initial;
  final bool allowDailyOnly;
  final bool alreadySaved;
  const _SaveToSheet({
    required this.initial,
    required this.allowDailyOnly,
    required this.alreadySaved,
  });

  @override
  State<_SaveToSheet> createState() => _SaveToSheetState();
}

class _SaveToSheetState extends State<_SaveToSheet> {
  late final Set<String> _picked = {...widget.initial};

  @override
  void initState() {
    super.initState();
    ArchiveStorage.loadFromStorage().then((_) {
      if (!mounted) return;
      // Clips have to go somewhere: start with "Your Archives".
      if (!widget.allowDailyOnly && _picked.isEmpty) {
        setState(() => _picked.add(ArchiveStorage.defaultId));
      }
    });
  }

  Future<void> _newFolder() async {
    final f = await showFolderEditor(context);
    if (f != null && mounted) setState(() => _picked.add(f.id));
  }

  bool get _canSave => widget.allowDailyOnly || _picked.isNotEmpty;

  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool on,
    required VoidCallback onTap,
    bool radio = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SettingsStyle.page,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 21, color: kc.adapt(const Color(0xFF55595F))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          color: SettingsStyle.ink)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12.5, color: SettingsStyle.subtle)),
                ],
              ),
            ),
            Icon(
              on
                  ? (radio
                  ? Icons.radio_button_checked_rounded
                  : Icons.check_circle_rounded)
                  : (radio
                  ? Icons.radio_button_off_rounded
                  : Icons.circle_outlined),
              size: 24,
              color: on ? Colors.cyan : kc.adapt(const Color(0xFFC4C7CC)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
      BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
        color: kc.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: kc.grey(300),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Save to',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: SettingsStyle.ink)),
              ),
            ),
            Flexible(
              child: ValueListenableBuilder<List<ArchiveData>>(
                valueListenable: ArchiveStorage.folders,
                builder: (context, folders, _) => ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 4),
                  children: [
                    if (widget.allowDailyOnly)
                      _row(
                        icon: Icons.wb_sunny_outlined,
                        title: 'Only in this Daily',
                        subtitle: 'Find it in the Daily\'s Saved',
                        on: _picked.isEmpty,
                        radio: true,
                        onTap: () => setState(_picked.clear),
                      ),
                    for (final f in folders)
                      _row(
                        icon: Icons.folder_outlined,
                        title: f.name,
                        subtitle: f.description.isEmpty ? null : f.description,
                        on: _picked.contains(f.id),
                        onTap: () => setState(() => _picked.contains(f.id)
                            ? _picked.remove(f.id)
                            : _picked.add(f.id)),
                      ),
                    InkWell(
                      onTap: _newFolder,
                      child: Padding(
                        padding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Icon(Icons.add_rounded,
                                  size: 24, color: SettingsStyle.ink),
                            ),
                            SizedBox(width: 14),
                            Text('New folder',
                                style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    color: SettingsStyle.ink)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                  _canSave ? () => Navigator.pop(context, _picked.toList()) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kc.adapt(const Color(0xFFE6E7EA)),
                    disabledForegroundColor: kc.adapt(const Color(0xFFA5AAB2)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(widget.alreadySaved ? 'Done' : 'Save',
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}