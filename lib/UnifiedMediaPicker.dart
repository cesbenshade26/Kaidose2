import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

/// A single resolved pick — a ready-to-use local File plus whether it's a
/// video, so callers don't need to know anything about
/// AssetEntity/photo_manager themselves.
class PickedMedia {
  final File file;
  final bool isVideo;

  PickedMedia({required this.file, required this.isVideo});
}

/// Which kinds of media the picker lists.
enum MediaFilter { all, videos, photos }

/// Called once the user taps Add, with every item they checked, in the
/// order they checked them.
typedef MultiMediaPickedCallback = void Function(List<PickedMedia> items);

/// Inline (not modal) gallery panel — photos and videos merged into one
/// grid, newest first, same idea as iMessage's embedded picker. Meant to
/// be inserted directly into a compose area's layout (pushing the message
/// list up, not overlaying it) rather than shown as a popup.
///
/// Tap a cell to check/uncheck it (multi-select); an Add button appears
/// once at least one is checked. The Draw entry point lives here too, as
/// a row above the grid, so it only ever appears while this panel itself
/// is open — no separate menu needed.
class UnifiedMediaPickerPanel extends StatefulWidget {
  final MultiMediaPickedCallback onMediaSelected;
  final VoidCallback onDrawTap;
  final VoidCallback onClose;
  final double height;

  /// Defaults keep the original behavior (photos + videos, multi-select,
  /// Draw row). Clips use: initialFilter videos, allowFilterToggle,
  /// singleSelect, showDraw false, maxVideoDuration 60s.
  final MediaFilter initialFilter;
  final bool allowFilterToggle;
  final bool singleSelect;

  /// With [singleSelect], lets the Photos view still be multi-select (tap
  /// several, then Add) while Videos stay tap-to-pick. Used by Clips so a
  /// photo clip can have several photos.
  final bool multiSelectPhotos;

  /// Most items that can be checked at once (null = no limit).
  final int? maxSelect;
  final bool showDraw;
  final Duration? maxVideoDuration;
  final String title;

  const UnifiedMediaPickerPanel({
    Key? key,
    required this.onMediaSelected,
    required this.onDrawTap,
    required this.onClose,
    this.height = 320,
    this.initialFilter = MediaFilter.all,
    this.allowFilterToggle = false,
    this.singleSelect = false,
    this.multiSelectPhotos = false,
    this.maxSelect,
    this.showDraw = true,
    this.maxVideoDuration,
    this.title = 'Photos & Videos',
  }) : super(key: key);

  @override
  State<UnifiedMediaPickerPanel> createState() => _UnifiedMediaPickerPanelState();
}

enum _LoadState { loading, denied, error, ready }

class _UnifiedMediaPickerPanelState extends State<UnifiedMediaPickerPanel> {
  _LoadState _state = _LoadState.loading;
  List<AssetEntity> _assets = [];
  late MediaFilter _filter = widget.initialFilter;

  // LinkedHashSet-backed (Dart's default Set literal) — preserves the
  // order items were checked in, so the Add button can hand them back in
  // that same order.
  final Set<String> _selectedAssetIds = {};
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!mounted) return;

      if (!ps.hasAccess) {
        setState(() => _state = _LoadState.denied);
        return;
      }

      await _loadAssets();
    } catch (e) {
      print('UnifiedMediaPickerPanel: permission request error: $e');
      if (mounted) setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _loadAssets() async {
    try {
      // type: common → both images and videos in one query, which is the
      // whole point of merging Camera Roll + Video into one grid.
      final paths = await PhotoManager.getAssetPathList(
        type: _filter == MediaFilter.videos
            ? RequestType.video
            : _filter == MediaFilter.photos
            ? RequestType.image
            : RequestType.common,
        onlyAll: true,
      );

      if (paths.isEmpty) {
        if (mounted) {
          setState(() {
            _assets = [];
            _state = _LoadState.ready;
          });
        }
        return;
      }

      final recentAlbum = paths.first;
      final assets = await recentAlbum.getAssetListPaged(page: 0, size: 120);

      if (mounted) {
        setState(() {
          _assets = assets;
          _state = _LoadState.ready;
        });
      }
    } catch (e) {
      print('UnifiedMediaPickerPanel: load error: $e');
      if (mounted) setState(() => _state = _LoadState.ready);
    }
  }

  Future<void> _setFilter(MediaFilter f) async {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _selectedAssetIds.clear();
      _state = _LoadState.loading;
    });
    await _loadAssets();
  }

  bool get _single =>
      widget.singleSelect &&
          !(widget.multiSelectPhotos && _filter == MediaFilter.photos);

  bool _isTooLong(AssetEntity asset) =>
      asset.type == AssetType.video &&
          widget.maxVideoDuration != null &&
          asset.videoDuration > widget.maxVideoDuration!;

  void _toggleSelected(AssetEntity asset) {
    if (_isTooLong(asset)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
              'Clips can be up to ${widget.maxVideoDuration!.inSeconds} seconds'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_single) {
      _selectedAssetIds
        ..clear()
        ..add(asset.id);
      _handleAddPressed();
      return;
    }
    if (!_selectedAssetIds.contains(asset.id) &&
        widget.maxSelect != null &&
        _selectedAssetIds.length >= widget.maxSelect!) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Up to ${widget.maxSelect} at a time'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      if (_selectedAssetIds.contains(asset.id)) {
        _selectedAssetIds.remove(asset.id);
      } else {
        _selectedAssetIds.add(asset.id);
      }
    });
  }

  Future<void> _handleAddPressed() async {
    if (_isResolving || _selectedAssetIds.isEmpty) return;
    setState(() => _isResolving = true);

    final items = <PickedMedia>[];
    for (final id in _selectedAssetIds) {
      try {
        final asset = _assets.firstWhere((a) => a.id == id);
        final file = await asset.file;
        if (file != null) {
          items.add(PickedMedia(file: file, isVideo: asset.type == AssetType.video));
        }
      } catch (e) {
        print('UnifiedMediaPickerPanel: resolve error: $e');
      }
    }

    // Parent's callback closes this panel — no need to reset _isResolving
    // locally, this widget is about to be disposed.
    widget.onMediaSelected(items);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
          if (widget.allowFilterToggle) ...[
            _buildFilterToggle(),
            const SizedBox(width: 12),
          ],
          GestureDetector(
            onTap: widget.onClose,
            child: Icon(Icons.close, color: Colors.grey[600], size: 22),
          ),
        ],
      ),
    );
  }

  /// Deliberately small and quiet: two tiny labels, the active one pilled.
  Widget _buildFilterToggle() {
    Widget option(String label, MediaFilter f) {
      final selected = _filter == f;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setFilter(f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? Colors.grey[200] : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.black87 : Colors.grey[500],
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        option('Videos', MediaFilter.videos),
        option('Photos', MediaFilter.photos),
      ],
    );
  }

  Widget _buildDrawRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onDrawTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, color: Colors.black87, size: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  'Draw',
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCell(AssetEntity asset) {
    final bool isVideo = asset.type == AssetType.video;
    final bool isSelected = _selectedAssetIds.contains(asset.id);
    final bool tooLong = _isTooLong(asset);

    return GestureDetector(
      onTap: () => _toggleSelected(asset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: AssetEntityImageProvider(
              asset,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(200),
            ),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey[200],
              child: Icon(Icons.broken_image, color: Colors.grey[400], size: 24),
            ),
          ),
          if (isVideo) ...[
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.15)),
            ),
            const Center(
              child: Icon(Icons.play_circle_fill, color: Colors.white, size: 26),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Text(
                _formatDuration(asset.videoDuration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                ),
              ),
            ),
          ],
          if (tooLong)
            Positioned.fill(
              child: Container(color: Colors.white.withOpacity(0.65)),
            ),
          if (isSelected)
            Positioned.fill(
              child: Container(color: Colors.cyan.withOpacity(0.25)),
            ),
          // Checkmark indicator — always visible, filled when selected.
          if (!_single)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? Colors.cyan : Colors.white.withOpacity(0.85),
                  border: Border.all(
                    color: isSelected ? Colors.cyan : Colors.grey[400]!,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator(color: Colors.cyan));
      case _LoadState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 40, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  "Couldn't load your photos. If this just appeared after "
                      "adding this feature, make sure the app was fully "
                      "rebuilt (flutter clean + a fresh flutter run) rather "
                      "than hot-reloaded.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          ),
        );
      case _LoadState.denied:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.no_photography_outlined, size: 40, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'Allow access to your photos to attach one here',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => PhotoManager.openSetting(),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ),
        );
      case _LoadState.ready:
        if (_assets.isEmpty) {
          return Center(
            child: Text(
              _filter == MediaFilter.videos
                  ? 'No videos found'
                  : _filter == MediaFilter.photos
                  ? 'No photos found'
                  : 'No photos or videos found',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            childAspectRatio: 1,
          ),
          itemCount: _assets.length,
          itemBuilder: (context, index) => _buildGridCell(_assets[index]),
        );
    }
  }

  Widget _buildAddButtonBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: _isResolving ? null : _handleAddPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyan,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isResolving
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
          )
              : Text(
            'Add (${_selectedAssetIds.length})',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          if (widget.showDraw) ...[
            _buildDrawRow(),
            Divider(height: 1, color: Colors.grey[200]),
          ],
          Expanded(child: _buildBody()),
          if (_selectedAssetIds.isNotEmpty && !_single)
            _buildAddButtonBar(),
        ],
      ),
    );
  }
}