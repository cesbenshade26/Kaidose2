import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'DailyBubbleService.dart';
import 'DailyBubbleViewer.dart';

/// A single Daily Bubble in memory. `id` is the Firestore doc id — null
/// only in the brief window before the very first save completes.
/// `photos` is an optimistic local cache of photos added this session;
/// the viewer always re-fetches the authoritative, ordered list from
/// Firestore when a bubble is opened.
class DailyBubbleData {
  String? id;
  String name;
  File? cover;
  List<File> photos;

  DailyBubbleData({this.id, required this.name, this.cover, List<File>? photos})
      : photos = photos ?? [];
}

/// Manages the state of the "Add a Daily Bubble!" creation flow, and the
/// current user's saved bubbles.
///
/// Creation is kicked off from the Add tab (YourDaily.dart) but finished on
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

  /// Called from the "Add a Daily Bubble!" button on the Add tab. Always
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
  /// place, keeping its already-attached photos.
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
            photos: existing.photos,
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

  /// Attaches a just-posted Your Daily photo to a saved bubble, both
  /// locally (optimistic) and in Firestore.
  static Future<void> addPhotoToBubble(int index, File photo) async {
    if (index < 0 || index >= bubbles.length) return;
    final bubble = bubbles[index];
    if (bubble.id == null) return;

    bubble.photos.add(photo);
    _notifyListeners();

    await DailyBubbleService.addPhotoToBubble(bubbleId: bubble.id!, photo: photo);
  }

  /// Fetches every photo posted to a bubble, oldest first, for viewing.
  static Future<List<File>> getBubblePhotos(int index) async {
    if (index < 0 || index >= bubbles.length) return [];
    final bubble = bubbles[index];
    if (bubble.id == null) return List.unmodifiable(bubble.photos);
    return DailyBubbleService.loadBubblePhotos(bubbleId: bubble.id!);
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

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.65),
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
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.black, size: 22),
                  ),
                ),
              ),
              // Name + cover + create card
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isEditing ? 'Edit Daily Bubble' : 'New Daily Bubble',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _isSaving ? null : _pickCover,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[200],
                            border: Border.all(color: Colors.cyan, width: 2),
                          ),
                          child: YourDailyBubbleManager.draftCover != null
                              ? ClipOval(
                            child: Image.file(
                              YourDailyBubbleManager.draftCover!,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                            ),
                          )
                              : const Icon(Icons.add_a_photo, color: Colors.grey, size: 32),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to add a cover',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        maxLength: 24,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Bubble name',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => YourDailyBubbleManager.setBubbleName(value),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _handleCreate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
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

/// Fetches a bubble's posted photos and opens the viewer, or lets the user
/// know there's nothing posted to it yet.
Future<void> _viewBubble(BuildContext context, int index) async {
  final bubble = YourDailyBubbleManager.bubbles[index];

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.cyan)),
  );

  final photos = await YourDailyBubbleManager.getBubblePhotos(index);

  if (!context.mounted) return;
  Navigator.pop(context); // close loading spinner

  if (photos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No Daily posts in this bubble yet')),
    );
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DailyBubbleViewer(photos: photos, bubbleName: bubble.name),
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
      height: 92,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          return Padding(
            padding: const EdgeInsets.only(right: 14),
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
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                      border: Border.all(color: Colors.cyan, width: 2),
                    ),
                    child: item.cover != null
                        ? ClipOval(
                      child: Image.file(
                        item.cover!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    )
                        : Icon(Icons.person, color: Colors.grey[400], size: 28),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 70,
                    child: Text(
                      item.name.isNotEmpty ? item.name : 'New',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
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