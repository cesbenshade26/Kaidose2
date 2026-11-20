import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'ArchiveStorage.dart';
import 'CreateArchive.dart';
import 'InsideArchive.dart';
import 'SavedItemStorage.dart';
import 'SettingsWidgets.dart';

/// Settings → Archives: your folders of saved Daily posts and clips.
/// "Your Archives" is always first; + makes a new folder.
class ArchivesScreen extends StatefulWidget {
  const ArchivesScreen({Key? key}) : super(key: key);

  @override
  State<ArchivesScreen> createState() => _ArchivesScreenState();
}

class _ArchivesScreenState extends State<ArchivesScreen> {
  @override
  void initState() {
    super.initState();
    ArchiveStorage.start();
    SavedItems.start();
  }

  void _open(ArchiveData f) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => InsideArchiveScreen(archive: f)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SettingsStyle.page,
      appBar: AppBar(
        title: Text('Archives',
            style: TextStyle(
                color: SettingsStyle.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: SettingsStyle.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: SettingsStyle.ink),
        actions: [
          IconButton(
            tooltip: 'New folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => showFolderEditor(context),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([ArchiveStorage.folders, SavedItems.items]),
        builder: (context, _) {
          final folders = ArchiveStorage.folders.value;
          if (folders.isEmpty) {
            return Center(
                child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              SettingsGroup(
                footer: 'Save Daily posts and clips with the bookmark, then '
                    'pick a folder. Hold anything inside a folder to move or '
                    'remove it.',
                children: [
                  for (final f in folders)
                    SettingsTile(
                      icon: f.isDefault
                          ? Icons.bookmarks_outlined
                          : Icons.folder_outlined,
                      title: f.name,
                      subtitle: f.description.isEmpty ? null : f.description,
                      value: _count(SavedItems.countIn(f.id)),
                      onTap: () => _open(f),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton.icon(
                  onPressed: () => showFolderEditor(context),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('New folder',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(foregroundColor: SettingsStyle.ink),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _count(int n) => n == 0 ? 'Empty' : '$n';
}

/// Older name, kept so anything still pointing at it opens the new screen.
class ArchivesView extends StatelessWidget {
  const ArchivesView({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => const ArchivesScreen();
}