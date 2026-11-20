import 'package:flutter/material.dart';
import 'AppColors.dart';
import 'package:flutter/services.dart';
import 'ArchiveStorage.dart';
import 'ClipsActivity.dart' show ClipGrid;
import 'CreateArchive.dart';
import 'DailyPostActivity.dart' show DailyPostCard, warmDailyPosts;
import 'DailyShare.dart';
import 'SavedContent.dart';
import 'SavedItemStorage.dart';
import 'SelectArchiveFolder.dart';
import 'SettingsWidgets.dart';
import 'clip_service.dart';

/// One Archives folder: Daily posts and Clips in two tabs, newest saved
/// first. Hold anything for options.
class InsideArchiveScreen extends StatelessWidget {
  final ArchiveData archive;
  const InsideArchiveScreen({Key? key, required this.archive}) : super(key: key);

  Future<void> _menu(BuildContext context, ArchiveData folder) async {
    final choice = await showSavedMenu(context, [
      (Icons.edit_outlined, 'Edit folder', 'edit', false),
      if (!folder.isDefault)
        (Icons.delete_outline_rounded, 'Delete folder', 'delete', true),
    ]);
    if (!context.mounted) return;
    if (choice == 'edit') {
      await showFolderEditor(context, existing: folder);
    } else if (choice == 'delete') {
      final ok = await settingsConfirm(
        context,
        title: 'Delete "${folder.name}"?',
        message: 'The folder goes away. Posts in it stay saved in their '
            'Dailies and in any other folders; clips only in this folder '
            'are unsaved.',
        confirmLabel: 'Delete',
        danger: true,
      );
      if (ok && await ArchiveStorage.delete(folder.id) && context.mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ArchiveData>>(
      valueListenable: ArchiveStorage.folders,
      builder: (context, _, __) {
        final folder = ArchiveStorage.byId(archive.id) ?? archive;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: kc.background,
            appBar: AppBar(
              backgroundColor: kc.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: SettingsStyle.ink),
              centerTitle: true,
              title: Text(folder.name,
                  style: TextStyle(
                      color: SettingsStyle.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.more_horiz_rounded),
                  onPressed: () => _menu(context, folder),
                ),
              ],
              bottom: TabBar(
                labelColor: SettingsStyle.ink,
                unselectedLabelColor: SettingsStyle.subtle,
                indicatorColor: SettingsStyle.ink,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle:
                TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                tabs: [Tab(text: 'Daily posts'), Tab(text: 'Clips')],
              ),
            ),
            body: TabBarView(
              children: [
                SavedPostsList(
                  refs: () => SavedItems.inFolder(folder.id),
                  emptyText: 'Daily posts you save here show up here.',
                  folderId: folder.id,
                ),
                SavedClipsGrid(folderId: folder.id),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A small sheet of options. Returns the chosen value.
Future<String?> showSavedMenu(
    BuildContext context, List<(IconData, String, String, bool)> items) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: kc.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
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
          const SizedBox(height: 6),
          for (final i in items)
            ListTile(
              leading: Icon(i.$1,
                  color: i.$4 ? SettingsStyle.danger : SettingsStyle.ink),
              title: Text(i.$2,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: i.$4 ? SettingsStyle.danger : SettingsStyle.ink)),
              onTap: () => Navigator.pop(ctx, i.$3),
            ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
}

Widget _empty(IconData icon, String title, String text) => ListView(
  physics: const AlwaysScrollableScrollPhysics(),
  children: [
    const SizedBox(height: 90),
    Icon(icon, size: 56, color: kc.adapt(const Color(0xFFC4C7CC))),
    const SizedBox(height: 14),
    Text(title,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: SettingsStyle.ink)),
    const SizedBox(height: 6),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: SettingsStyle.subtle)),
    ),
  ],
);

/// Saved Daily posts as profile-style cards. Used in a folder
/// ([folderId] set) and in a Daily's Saved ([folderId] null: shows inside
/// that one Daily, so no Daily name on the cards).
class SavedPostsList extends StatefulWidget {
  final List<SavedRef> Function() refs;
  final String emptyText;
  final String? folderId;

  const SavedPostsList({
    Key? key,
    required this.refs,
    required this.emptyText,
    this.folderId,
  }) : super(key: key);

  @override
  State<SavedPostsList> createState() => _SavedPostsListState();
}

class _SavedPostsListState extends State<SavedPostsList>
    with AutomaticKeepAliveClientMixin {
  List<SavedPost>? _posts;
  String _loadedFor = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    SavedItems.items.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    SavedItems.items.removeListener(_changed);
    super.dispose();
  }

  List<SavedRef> get _refs => widget.refs().where((r) => r.isPost).toList();

  void _changed() {
    final keys = _refs.map((r) => r.key).join(',');
    if (keys != _loadedFor) _load();
  }

  Future<void> _load() async {
    final refs = _refs;
    _loadedFor = refs.map((r) => r.key).join(',');
    // Keep what's on screen; only fetch posts not loaded yet.
    final have = {for (final p in _posts ?? const <SavedPost>[]) p.ref.key: p};
    final fresh = await SavedContent.posts(
        refs.where((r) => !have.containsKey(r.key)).toList());
    final byKey = {...have, for (final p in fresh) p.ref.key: p};
    if (!mounted) return;
    setState(() => _posts = [
      for (final r in refs)
        if (byKey[r.key] != null) byKey[r.key]!,
    ]);
  }

  Future<void> _onHold(SavedPost p) async {
    final folder = widget.folderId;
    final name = folder == null ? null : ArchiveStorage.byId(folder)?.name;
    final choice = await showSavedMenu(context, [
      if (folder != null)
        (Icons.wb_sunny_outlined, 'Visit Daily', 'visit', false),
      (Icons.folder_outlined, 'Save to folders…', 'folders', false),
      if (folder != null)
        (Icons.remove_circle_outline_rounded, 'Remove from ${name ?? 'folder'}',
        'remove', false),
      (Icons.bookmark_remove_outlined, 'Unsave', 'unsave', true),
    ]);
    if (!mounted) return;
    final key = p.ref.key;
    switch (choice) {
      case 'visit':
        DailyShareLink.open(context, p.dailyId);
        break;
      case 'folders':
        final picked = await showSaveToSheet(context,
            selected: SavedItems.get(key)?.archiveIds ?? const [],
            allowDailyOnly: true,
            alreadySaved: true);
        if (picked != null) await SavedItems.setFolders(key, picked);
        break;
      case 'remove':
        await SavedItems.removeFromFolder(key, folder!);
        break;
      case 'unsave':
        await SavedItems.unsave(key);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final posts = _posts;
    if (posts == null) {
      return Center(child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))));
    }
    if (posts.isEmpty) {
      return _empty(Icons.bookmark_border_rounded, 'No saved posts',
          widget.emptyText);
    }
    final messages = posts.map((p) => p.message).toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      itemCount: posts.length,
      itemBuilder: (context, i) {
        warmDailyPosts(messages, i);
        final p = posts[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DailyPostCard(
            key: ValueKey(p.ref.key),
            message: p.message,
            dailyId: p.dailyId,
            dailyTitle: p.dailyTitle,
            color: p.color,
            showDaily: widget.folderId != null,
            onLongPress: () => _onHold(p),
          ),
        );
      },
    );
  }
}

/// Saved clips in a folder, as a grid.
class SavedClipsGrid extends StatefulWidget {
  final String folderId;
  const SavedClipsGrid({Key? key, required this.folderId}) : super(key: key);

  @override
  State<SavedClipsGrid> createState() => _SavedClipsGridState();
}

class _SavedClipsGridState extends State<SavedClipsGrid>
    with AutomaticKeepAliveClientMixin {
  List<(SavedRef, ClipData)>? _clips;
  String _loadedFor = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    SavedItems.items.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    SavedItems.items.removeListener(_changed);
    super.dispose();
  }

  List<SavedRef> get _refs =>
      SavedItems.inFolder(widget.folderId).where((r) => r.isClip).toList();

  void _changed() {
    if (_refs.map((r) => r.key).join(',') != _loadedFor) _load();
  }

  Future<void> _load() async {
    final refs = _refs;
    _loadedFor = refs.map((r) => r.key).join(',');
    final have = {for (final c in _clips ?? const []) c.$1.key: c};
    final fresh = await SavedContent.clips(
        refs.where((r) => !have.containsKey(r.key)).toList());
    final byKey = {...have, for (final c in fresh) c.$1.key: c};
    if (!mounted) return;
    setState(() => _clips = [
      for (final r in refs)
        if (byKey[r.key] != null) byKey[r.key]!,
    ]);
  }

  Future<void> _onHold(ClipData clip) async {
    final key = SavedItems.clipKey(clip.id);
    final name = ArchiveStorage.byId(widget.folderId)?.name ?? 'folder';
    final choice = await showSavedMenu(context, [
      (Icons.folder_outlined, 'Save to folders…', 'folders', false),
      (Icons.remove_circle_outline_rounded, 'Remove from $name', 'remove', false),
      (Icons.bookmark_remove_outlined, 'Unsave', 'unsave', true),
    ]);
    if (!mounted) return;
    switch (choice) {
      case 'folders':
        final picked = await showSaveToSheet(context,
            selected: SavedItems.get(key)?.archiveIds ?? const [],
            alreadySaved: true);
        if (picked != null) await SavedItems.setFolders(key, picked);
        break;
      case 'remove':
        await SavedItems.removeFromFolder(key, widget.folderId);
        break;
      case 'unsave':
        await SavedItems.unsave(key);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final clips = _clips;
    if (clips == null) {
      return Center(child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))));
    }
    if (clips.isEmpty) {
      return _empty(Icons.play_circle_outline_rounded, 'No saved clips',
          'Clips you save here show up here.');
    }
    return ClipGrid(
      clips: clips.map((c) => c.$2).toList(),
      onLongPress: _onHold,
    );
  }
}