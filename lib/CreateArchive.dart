import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'ArchiveStorage.dart';
import 'SettingsWidgets.dart';

/// New folder, or rename one ([existing]). Returns the folder, or null if
/// cancelled.
Future<ArchiveData?> showFolderEditor(BuildContext context,
    {ArchiveData? existing}) {
  return showModalBottomSheet<ArchiveData>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FolderEditor(existing: existing),
  );
}

class _FolderEditor extends StatefulWidget {
  final ArchiveData? existing;
  const _FolderEditor({this.existing});

  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final TextEditingController _name =
  TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _about =
  TextEditingController(text: widget.existing?.description ?? '');
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  bool get _ready => _name.text.trim().isNotEmpty && !_busy;

  Future<void> _save() async {
    if (!_ready) return;
    setState(() => _busy = true);
    final e = widget.existing;
    ArchiveData? result;
    if (e == null) {
      result = await ArchiveStorage.create(_name.text, description: _about.text);
    } else {
      final ok = await ArchiveStorage.rename(e.id, _name.text,
          description: _about.text);
      if (ok) {
        result = ArchiveData(
          id: e.id,
          name: _name.text.trim(),
          description: _about.text.trim(),
          createdAt: e.createdAt,
        );
      }
    }
    if (!mounted) return;
    if (result == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save that. Try again.")));
      return;
    }
    Navigator.pop(context, result);
  }

  InputDecoration _field(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: kc.adapt(const Color(0xFFA5AAB2))),
    filled: true,
    fillColor: SettingsStyle.page,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: kc.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
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
                Text(editing ? 'Edit folder' : 'New folder',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: SettingsStyle.ink)),
                const SizedBox(height: 14),
                TextField(
                  controller: _name,
                  autofocus: true,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _field('Name'),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _about,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: _field('Description (optional)'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _ready ? _save : null,
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
                    child: Text(editing ? 'Save' : 'Create',
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}