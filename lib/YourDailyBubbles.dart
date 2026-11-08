import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'DailyBubbleService.dart';
import 'DailyBubbleViewer.dart';
import 'StoryMediaItem.dart';

/// A single Daily Bubble in memory. `id` is the Firestore doc id — null
/// only in the brief window before the very first save completes.
/// `media` is an optimistic local cache of items (photos and/or video
/// clips) added this session; the viewer always re-fetches the
/// authoritative, ordered list from Firestore when a bubble is opened.
class DailyBubbleData {
  String? id;
  String name;
  File? cover;
  List<StoryMediaItem> media;

  DailyBubbleData({this.id, required this.name, this.cover, List<StoryMediaItem>? media})
      : media = media ?? [];
}

/// Manages the state of the Daily Bubble creation flow, and the
/// current user's saved bubbles.
///
/// Creation is kicked off from the Add sheet (Daily Bubble) but finished on
/// the Profile tab, so this is a static, listener-based manager — same
/// pattern as DailyPhotoManager/BackgroundPicManager — rather than something
/// passed down through Add.dart's widget tree.
///
/// `bubbles` holds every saved bubble, left to right in creation order.
/// While the overlay is open, `draftName`/`draftCover` hold the in-progress
/// edit — either a brand new bubble (editingIndex == null, appended on
/// Create) or an existing one being re-edited (editingIndex == that index).
class YourDailyBubbleManager {
  static List<DailyBubbleData> bubbles = [];
  static bool isCreating = false;
  static bool isLoadingBubbles = false;
  static int? editingIndex;
  static String draftName = '';
  static File? draftCover;

  static VoidCallback? _navigateToProfileCallback;
  static final List<VoidCallback> _listeners = [];

  /// HomeScreen registers this so startCreatingBubble() can force-switch
  /// to the Profile tab without Add.dart needing to know about it.
  static void registerNavigateToProfile(VoidCallback callback) {
    _navigateToProfileCallback = callback;
  }

  static void unregisterNavigateToProfile() {
    _navigateToProfileCallback = null;
  }

  static void addListener(VoidCallback listener) => _listeners.add(listener);
  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static void _notifyListeners() {
    for (var listener in _listeners) {
      try {
        listener();
      } catch (e) {
        print('YourDailyBubbleManager: listener error: $e');
      }
    }
  }

  /// Loads this user's saved bubbles from Firestore. Call once when the
  /// Profile page first loads.
  static Future<void> loadBubblesFromFirestore() async {
    isLoadingBubbles = true;
    _notifyListeners();

    final records = await DailyBubbleService.loadBubbles();
    bubbles = records
        .map((r) => DailyBubbleData(id: r.id, name: r.name, cover: r.cover))
        .toList();

    isLoadingBubbles = false;
    _notifyListeners();
  }

  /// Called from the Daily Bubble option in the Add sheet. Always
  /// starts a brand-new bubble — it gets appended after any existing ones
  /// once "Create" is pressed.
  static void startCreatingBubble() {
    editingIndex = null;
    draftName = '';
    draftCover = null;
    isCreating = true;
    _notifyListeners();
    _navigateToProfileCallback?.call();
  }

  /// Long-pressing an existing bubble in the row reopens that specific
  /// bubble for editing (rather than creating a new one).
  static void reopenForEditing(int index) {
    if (index < 0 || index >= bubbles.length) return;
    editingIndex = index;
    draftName = bubbles[index].name;
    draftCover = bubbles[index].cover;
    isCreating = true;
    _notifyListeners();
  }

  static void setBubbleName(String name) {
    draftName = name;
    _notifyListeners();
  }

  static void setBubbleCover(File cover) {
    draftCover = cover;
    _notifyListeners();
  }

  /// "Create"/"Save" button — persists to Firestore, then updates local
  /// state. New bubbles go on the end of the list (so they show up to the
  /// right of the last one); edits update the bubble at editingIndex in
  /// place, keeping its already-attached media.
  static Future<void> finishCreatingBubble() async {
    final name = draftName;
    final cover = draftCover;

    if (editingIndex != null) {
      final index = editingIndex!;
      final existing = bubbles[index];
      if (existing.id != null) {
        final success = await DailyBubbleService.updateBubble(
          bubbleId: existing.id!,
          name: name,
          cover: cover,
        );
        if (success) {
          bubbles[index] = DailyBubbleData(
            id: existing.id,
            name: name,
            cover: cover ?? existing.cover,
            media: existing.media,
          );
        }
      }
    } else {
      final newId = await DailyBubbleService.createBubble(name: name, cover: cover);
      if (newId != null) {
        bubbles.add(DailyBubbleData(id: newId, name: name, cover: cover));
      }
    }

    isCreating = false;
    editingIndex = null;
    _notifyListeners();
  }

  /// X button — discards the draft without touching any saved bubble.
  static void cancelCreatingBubble() {
    isCreating = false;
    editingIndex = null;
    draftName = '';
    draftCover = null;
    _notifyListeners();
  }

  /// Attaches a just-posted Your Daily photo OR video clip to a saved
  /// bubble, both locally (optimistic) and in Firestore.
  static Future<void> addMediaToBubble(int index, File file, {required bool isVideo}) async {
    if (index < 0 || index >= bubbles.length) return;
    final bubble = bubbles[index];
    if (bubble.id == null) return;

    bubble.media.add(StoryMediaItem(file: file, isVideo: isVideo));
    _notifyListeners();

    await DailyBubbleService.addMediaToBubble(
      bubbleId: bubble.id!,
      file: file,
      isVideo: isVideo,
    );
  }

  /// Fetches every photo/video posted to a bubble, oldest first, for
  /// viewing.
  static Future<List<StoryMediaItem>> getBubbleMedia(int index) async {
    if (index < 0 || index >= bubbles.length) return [];
    final bubble = bubbles[index];
    if (bubble.id == null) return List.unmodifiable(bubble.media);
    return DailyBubbleService.loadBubbleMedia(bubbleId: bubble.id!);
  }
}

/// Full-screen dark overlay shown over the Profile page while a bubble is
/// being created or edited. Everything underneath is dimmed and unusable;
/// only this card (name + cover picker + Create) and the X button are
/// interactive.
class YourDailyBubbleCreatorOverlay extends StatefulWidget {
  const YourDailyBubbleCreatorOverlay({Key? key}) : super(key: key);

  @override
  State<YourDailyBubbleCreatorOverlay> createState() =>
      _YourDailyBubbleCreatorOverlayState();
}

class _YourDailyBubbleCreatorOverlayState
    extends State<YourDailyBubbleCreatorOverlay> {
  final ImagePicker _picker = ImagePicker();
  late TextEditingController _nameController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: YourDailyBubbleManager.draftName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() {
        YourDailyBubbleManager.setBubbleCover(File(image.path));
      });
    }
  }

  Future<void> _handleCreate() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    // Belt-and-suspenders: commit whatever is currently in the field even
    // if onChanged hasn't fired for the very last keystroke.
    YourDailyBubbleManager.setBubbleName(_nameController.text);
    await YourDailyBubbleManager.finishCreatingBubble();

    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = YourDailyBubbleManager.editingIndex != null;
    final bool hasCover = YourDailyBubbleManager.draftCover != null;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.6),
        child: SafeArea(
          child: Stack(
            children: [
              // X to back out
              Positioned(
                top: 8,
                right: 16,
                child: GestureDetector(
                  onTap: _isSaving
                      ? null
                      : () => YourDailyBubbleManager.cancelCreatingBubble(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        color: Colors.black87, size: 22),
                  ),
                ),
              ),
              // Name + cover + create card
              Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 28),
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isEditing ? 'Edit Daily Bubble' : 'New Daily Bubble',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: _isSaving ? null : _pickCover,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey[100],
                                  border: Border.all(
                                    color: hasCover
                                        ? Colors.cyan
                                        : Colors.grey[400]!,
                                    width: 2,
                                  ),
                                ),
                                child: hasCover
                                    ? ClipOval(
                                  child: Image.file(
                                    YourDailyBubbleManager.draftCover!,
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.cover,
                                  ),
                                )
                                    : Icon(Icons.add_a_photo_outlined,
                                    color: Colors.grey[600], size: 30),
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.cyan,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                  child: Icon(
                                    hasCover ? Icons.edit : Icons.add,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          hasCover ? 'Tap to change cover' : 'Tap to add a cover',
                          style:
                          TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _nameController,
                          maxLength: 24,
                          enabled: !_isSaving,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(
                              fontSize: 15, color: Colors.black87),
                          decoration: InputDecoration(
                            hintText: 'Bubble name',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            counterStyle: TextStyle(
                                color: Colors.grey[500], fontSize: 11),
                            filled: true,
                            fillColor: Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Colors.cyan, width: 1.5),
                            ),
                          ),
                          onChanged: (value) =>
                              YourDailyBubbleManager.setBubbleName(value),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _handleCreate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyan,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                              Colors.cyan.withOpacity(0.4),
                              disabledForegroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                                : Text(
                              isEditing ? 'Save' : 'Create',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
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
}

/// Fetches a bubble's posted media and opens the viewer, or lets the user
/// know there's nothing posted to it yet.
Future<void> _viewBubble(BuildContext context, int index) async {
  final bubble = YourDailyBubbleManager.bubbles[index];

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.cyan)),
  );

  final media = await YourDailyBubbleManager.getBubbleMedia(index);

  if (!context.mounted) return;
  Navigator.pop(context); // close loading spinner

  if (media.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No Daily posts in this bubble yet')),
    );
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DailyBubbleViewer(items: media, bubbleName: bubble.name),
    ),
  );
}

/// Row of Daily Bubbles shown in the Profile layout (below followers/bio,
/// above the tab bar). Tap a bubble to view its posted Your Dailys, oldest
/// first; long-press to edit its name/cover. Shows every saved bubble left
/// to right, with the one currently being edited (if any) reflecting live
/// draft changes, and a trailing in-progress preview when creating a
/// brand-new bubble.
class YourDailyBubbleRow extends StatelessWidget {
  const YourDailyBubbleRow({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final items = <_BubbleDisplayItem>[];

    for (int i = 0; i < YourDailyBubbleManager.bubbles.length; i++) {
      if (YourDailyBubbleManager.isCreating && YourDailyBubbleManager.editingIndex == i) {
        items.add(_BubbleDisplayItem(
          name: YourDailyBubbleManager.draftName,
          cover: YourDailyBubbleManager.draftCover,
          index: i,
        ));
      } else {
        final b = YourDailyBubbleManager.bubbles[i];
        items.add(_BubbleDisplayItem(name: b.name, cover: b.cover, index: i));
      }
    }

    // Brand-new bubble being created goes on the end, to the right of
    // everything already saved.
    if (YourDailyBubbleManager.isCreating && YourDailyBubbleManager.editingIndex == null) {
      items.add(_BubbleDisplayItem(
        name: YourDailyBubbleManager.draftName,
        cover: YourDailyBubbleManager.draftCover,
        index: null,
      ));
    }

    return SizedBox(
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: item.index != null
                  ? () => _viewBubble(context, item.index!)
                  : null,
              onLongPress: item.index != null
                  ? () => YourDailyBubbleManager.reopenForEditing(item.index!)
                  : null,
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                      border: Border.all(color: Colors.cyan.withOpacity(0.55), width: 1.5),
                    ),
                    child: item.cover != null
                        ? ClipOval(
                      child: Image.file(
                        item.cover!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      ),
                    )
                        : Icon(Icons.person, color: Colors.grey[400], size: 24),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 60,
                    child: Text(
                      item.name.isNotEmpty ? item.name : 'New',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BubbleDisplayItem {
  final String name;
  final File? cover;
  final int? index; // null = in-progress new bubble, not yet saved

  _BubbleDisplayItem({required this.name, this.cover, this.index});
}