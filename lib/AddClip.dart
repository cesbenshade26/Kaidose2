import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'Moderation.dart';
import 'AppColors.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'ClipTracker.dart';
import 'clip_service.dart';
import 'UnifiedMediaPicker.dart';
import 'PhotoEditor.dart';
import 'MusicSearch.dart';
import 'ClipMusic.dart';

/// Create a Clip: one video (up to 60s) or up to 10 photos, plus a caption.
///
/// Empty state offers Library (the inline picker, videos first with a small
/// Videos | Photos switch) and Film (camera). Once something is chosen the
/// preview takes over, with a caption bar and a single Post button.
class AddClipScreen extends StatefulWidget {
  /// True when opened as its own screen from the Add sheet: shows a close
  /// button while nothing is chosen yet.
  final bool closeable;

  const AddClipScreen({Key? key, this.closeable = false}) : super(key: key);

  @override
  State<AddClipScreen> createState() => _AddClipScreenState();
}

class _AddClipScreenState extends State<AddClipScreen> {
  static const Duration _maxClipLength = Duration(seconds: 60);
  static const double _pickerHeight = 330;

  final TextEditingController _captionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  static const int _maxPhotos = ClipService.maxPhotosPerClip;

  File? _file; // the video, when this is a video clip
  final List<File> _photos = []; // the photos, when this is a photo clip
  int _previewIndex = 0;
  bool _editorOpen = false; // song is silent here while the editor is open
  MusicTrack? _music; // song picked in the editor (replaces the clip's audio)
  bool _pickerPhotos = false; // picker opened to add photos
  bool _isVideo = true;
  VideoPlayerController? _videoController;

  bool _showPicker = false;
  bool _isInitializing = false;
  bool _isPosting = false;
  String? _errorMessage;

  bool get _hasMedia => _isVideo ? _file != null : _photos.isNotEmpty;

  // ─── AI caption ideas ─────────────────────────────────────────────────────
  // Only runs when the user taps "Suggest a caption". A small frame (the
  // video's still, or the first photo) is made in the background as soon as
  // media is chosen, so the tap goes straight to the AI.
  int _mediaVersion = 0; // bumps whenever the chosen media changes
  Uint8List? _frame;
  String _frameMime = 'image/jpeg';
  bool _suggesting = false;
  List<String> _suggestions = [];

  void _mediaChanged() {
    _mediaVersion++;
    _frame = null;
    _suggestions = [];
    _suggesting = false;
  }

  Future<void> _prepareFrame() async {
    final version = _mediaVersion;
    Uint8List? bytes;
    var mime = 'image/jpeg';
    try {
      if (_isVideo && _file != null) {
        for (final ms in [1000, 0]) {
          bytes = await VideoThumbnail.thumbnailData(
            video: _file!.path,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 512,
            quality: 70,
            timeMs: ms,
          );
          if (bytes != null && bytes.isNotEmpty) break;
        }
      } else if (_photos.isNotEmpty) {
        // Shrink the first photo to 512px wide (originals can be 10MB+).
        final codec = await ui.instantiateImageCodec(
            await _photos.first.readAsBytes(),
            targetWidth: 512);
        final frame = await codec.getNextFrame();
        final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.png);
        bytes = data?.buffer.asUint8List();
        mime = 'image/png';
      }
    } catch (e) {
      print('AddClipScreen: frame for caption failed: $e');
    }
    if (version == _mediaVersion && bytes != null && bytes.isNotEmpty) {
      _frame = bytes;
      _frameMime = mime;
    }
  }

  Future<void> _suggestCaptions() async {
    if (_suggesting || !_hasMedia) return;
    final version = _mediaVersion;
    setState(() => _suggesting = true);
    try {
      if (_frame == null) await _prepareFrame();
      final frame = _frame;
      if (frame == null || version != _mediaVersion) {
        throw Exception('no frame');
      }
      final result = await FirebaseFunctions.instance
          .httpsCallable('suggestClipCaption')
          .call({
        'image': base64Encode(frame),
        'mimeType': _frameMime,
        'kind': _isVideo ? 'video' : 'photo',
        'draft': _captionController.text.trim(),
      });
      final raw = (result.data as Map?)?['captions'];
      final captions = raw is List
          ? raw.whereType<String>().where((c) => c.trim().isNotEmpty).toList()
          : <String>[];
      if (!mounted || version != _mediaVersion) return;
      setState(() {
        _suggestions = captions;
        _suggesting = false;
      });
      if (captions.isEmpty) _captionError();
    } on FirebaseFunctionsException catch (e) {
      // The server's own reason, e.g. "AI returned no captions".
      print('AddClipScreen: caption suggestions failed: '
          '${e.code} / ${e.message} / ${e.details}');
      if (!mounted) return;
      setState(() => _suggesting = false);
      _captionError();
    } catch (e) {
      print('AddClipScreen: caption suggestions failed: $e');
      if (!mounted) return;
      setState(() => _suggesting = false);
      _captionError();
    }
  }

  void _captionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Couldn't come up with captions. Try again."),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _useSuggestion(String caption) {
    final text = caption.length > 150 ? caption.substring(0, 150) : caption;
    setState(() {
      _captionController.text = text;
      _captionController.selection =
          TextSelection.collapsed(offset: text.length);
      _suggestions = [];
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  // ─── Media selection ──────────────────────────────────────────────────────

  Future<void> _setMedia(File file, {required bool isVideo}) async {
    await _videoController?.dispose();
    _videoController = null;

    setState(() {
      _mediaChanged();
      _file = file;
      _photos.clear();
      _isVideo = isVideo;
      _showPicker = false;
      _errorMessage = null;
      _isInitializing = isVideo;
    });

    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted || _file != file) {
        await controller.dispose();
        return;
      }
      controller.setLooping(true);
      // A picked song replaces the video's own sound.
      controller.setVolume(_music != null ? 0 : 1);
      controller.play();
      setState(() {
        _videoController = controller;
        _isInitializing = false;
      });
      _prepareFrame();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = "Couldn't load this video";
        });
      }
    }
  }

  void _onLibraryPicked(List<PickedMedia> items) {
    if (items.isEmpty) {
      setState(() => _showPicker = false);
      return;
    }
    final videos = items.where((i) => i.isVideo).toList();
    if (videos.isNotEmpty) {
      _setMedia(videos.first.file, isVideo: true);
      return;
    }
    _addPhotos(items.map((i) => i.file).toList());
  }

  Future<void> _addPhotos(List<File> files) async {
    await _videoController?.dispose();
    if (!mounted) return;
    final room = _maxPhotos - _photos.length;
    setState(() {
      _videoController = null;
      _file = null;
      _isVideo = false;
      _isInitializing = false;
      _errorMessage = null;
      _showPicker = false;
      final start = _photos.length;
      _photos.addAll(files.take(room));
      // Jump to the first photo that was just added.
      _previewIndex = start < _photos.length ? start : 0;
      if (start == 0) _mediaChanged();
    });
    if (_frame == null) _prepareFrame();
  }

  /// Edit (crop, text, draw, music) the photo being previewed; the edited
  /// copy takes its place in the clip.
  Future<void> _editCurrentPhoto() async {
    if (_photos.isEmpty) return;
    final i = _previewIndex.clamp(0, _photos.length - 1);
    setState(() => _editorOpen = true);
    final r = await PhotoEditor.open(context, _photos[i], withAudio: true);
    if (mounted) setState(() => _editorOpen = false);
    if (r != null && mounted && i < _photos.length) {
      setState(() {
        _photos[i] = r.file;
        _music = r.music ?? _music;
        if (i == 0) _mediaChanged();
      });
    }
  }

  /// Edit the video (text, draw, music). Music replaces its own audio.
  Future<void> _editVideo() async {
    final f = _file;
    if (f == null) return;
    setState(() => _editorOpen = true);
    final r =
    await PhotoEditor.open(context, f, isVideo: true, withAudio: true);
    if (mounted) setState(() => _editorOpen = false);
    if (r != null && mounted) {
      _music = r.music ?? _music;
      await _setMedia(r.file, isVideo: true);
    }
  }

  void _removePhotoAt(int i) {
    setState(() {
      if (i == 0) _mediaChanged();
      _photos.removeAt(i);
      if (_photos.isEmpty) {
        _previewIndex = 0;
        _isVideo = true;
      } else if (_previewIndex >= _photos.length) {
        _previewIndex = _photos.length - 1;
      } else if (i < _previewIndex) {
        _previewIndex--;
      }
    });
  }

  void _reorderPhotos(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final current = _photos[_previewIndex];
      final moved = _photos.removeAt(oldIndex);
      _photos.insert(newIndex, moved);
      if (oldIndex == 0 || newIndex == 0) _mediaChanged();
      _previewIndex = _photos.indexOf(current);
    });
  }

  void _openPicker({required bool photos}) {
    FocusScope.of(context).unfocus();
    setState(() {
      _pickerPhotos = photos;
      _showPicker = !_showPicker;
    });
  }

  Future<void> _film() async {
    FocusScope.of(context).unfocus();
    final XFile? video = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: _maxClipLength,
    );
    if (video != null) {
      await _setMedia(File(video.path), isVideo: true);
    }
  }

  Future<void> _clearMedia() async {
    await _videoController?.dispose();
    if (!mounted) return;
    setState(() {
      _mediaChanged();
      _videoController = null;
      _file = null;
      _photos.clear();
      _previewIndex = 0;
      _isVideo = true;
      _music = null;
      _errorMessage = null;
      _isInitializing = false;
    });
  }

  // ─── Posting ──────────────────────────────────────────────────────────────

  Future<void> _post() async {
    if (!_hasMedia || _isPosting) return;
    FocusScope.of(context).unfocus();
    // Community Guidelines agreed + no blocked language in the caption.
    if (!await TermsGate.readyToPost(context, _captionController.text)) return;
    setState(() => _isPosting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final caption = _captionController.text.trim();
      bool success;

      if (_isVideo) {
        // Local copy keeps your own profile view working, then upload so
        // other people can see it.
        await ClipTracker.addClip(_file!);
        success = await ClipService.uploadClip(
          videoFile: _file!,
          caption: caption,
          music: _music,
        );
      } else {
        success = await ClipService.uploadPhotoClip(
          photoFiles: List<File>.of(_photos),
          caption: caption,
          music: _music,
        );
      }

      if (!mounted) return;

      if (success) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Clip posted!'),
            backgroundColor: Colors.black87,
            duration: Duration(seconds: 2),
          ),
        );
        await _videoController?.dispose();
        setState(() {
          _mediaChanged();
          _videoController = null;
          _file = null;
          _photos.clear();
          _previewIndex = 0;
          _isVideo = true;
          _music = null;
          _captionController.clear();
        });
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to post clip. Try again.'),
            backgroundColor: context.colors.danger,
          ),
        );
      }
    } catch (e) {
      print('AddClipScreen: post error: $e');
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: context.colors.danger),
      );
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: context.colors.text,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          'New Clip',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: context.colors.text),
        ),
        leading: _hasMedia
            ? IconButton(
          icon: Icon(Icons.arrow_back, color: context.colors.text),
          onPressed: _isPosting ? null : _clearMedia,
        )
            : (widget.closeable
            ? IconButton(
          icon: Icon(Icons.close, color: context.colors.text),
          onPressed: () => Navigator.of(context).maybePop(),
        )
            : null),
      ),
      body: Column(
        children: [
          ClipMusicPlayer(
            track: _music,
            active: _hasMedia && !_editorOpen && !_isPosting,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _hasMedia
                        ? KeyedSubtree(
                      key: const ValueKey('preview'),
                      child: _buildPreviewCard(),
                    )
                        : KeyedSubtree(
                      key: const ValueKey('empty'),
                      child: _buildEmptyCard(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_hasMedia && !_isVideo) _buildFilmstrip(),
          if (_hasMedia) _buildCaptionAndPost(),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: _showPicker
                ? UnifiedMediaPickerPanel(
              key: ValueKey('picker-$_pickerPhotos'),
              height: _pickerHeight,
              title: _pickerPhotos ? 'Add photos' : 'Choose media',
              initialFilter: _pickerPhotos
                  ? MediaFilter.photos
                  : MediaFilter.videos,
              allowFilterToggle: !_pickerPhotos,
              singleSelect: true,
              multiSelectPhotos: true,
              maxSelect: _maxPhotos - _photos.length,
              showDraw: false,
              maxVideoDuration: _maxClipLength,
              onMediaSelected: _onLibraryPicked,
              onDrawTap: () {},
              onClose: () => setState(() => _showPicker = false),
            )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
    color: context.colors.surfaceMuted,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: context.colors.text.withOpacity(0.75), width: 1),
  );

  Widget _buildEmptyCard() {
    return Container(
      decoration: _cardDecoration,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.border),
                ),
                child: Icon(Icons.play_arrow_rounded,
                    size: 34, color: context.colors.text),
              ),
              const SizedBox(height: 16),
              Text(
                'Share a moment',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: context.colors.text),
              ),
              const SizedBox(height: 6),
              Text(
                'A video up to 60 seconds, or up to 10 photos',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: context.colors.textMuted),
              ),
              const SizedBox(height: 24),
              _primaryButton(
                icon: Icons.photo_library_outlined,
                label: 'Choose from library',
                onTap: () => _openPicker(photos: false),
              ),
              const SizedBox(height: 10),
              _secondaryButton(
                icon: Icons.videocam_outlined,
                label: 'Film',
                onTap: _film,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _primaryButton(
      {required IconData icon,
        required String label,
        required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.colors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _secondaryButton(
      {required IconData icon,
        required String label,
        required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.text,
          side: BorderSide(color: context.colors.textFaint),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildMedia(),
            // Swap / remove (video only; photos are removed in the strip below)
            if (_isVideo)
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: _isPosting ? null : _clearMedia,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child:
                    const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            if (_hasMedia && _errorMessage == null)
              Positioned(
                right: 12,
                bottom: 12,
                child: GestureDetector(
                  onTap: _isPosting
                      ? null
                      : (_isVideo ? _editVideo : _editCurrentPhoto),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_fix_high_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('Edit',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            if (!_isVideo)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      _photos.length > 1
                          ? '${_previewIndex + 1} / ${_photos.length}'
                          : 'Photo',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedia() {
    if (_errorMessage != null) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.white70),
              const SizedBox(height: 10),
              Text(_errorMessage!,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    if (!_isVideo) {
      if (_photos.isEmpty) return const SizedBox.shrink();
      final f = _photos[_previewIndex.clamp(0, _photos.length - 1)];
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: Image.file(
          f,
          key: ValueKey(f.path),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: 1080,
        ),
      );
    }

    final c = _videoController;
    if (_isInitializing || c == null || !c.value.isInitialized) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.accent, strokeWidth: 2.5),
      );
    }

    return GestureDetector(
      onTap: () => setState(() {
        c.value.isPlaying ? c.pause() : c.play();
      }),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
          if (!c.value.isPlaying)
            const Center(
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white70, size: 64),
            ),
        ],
      ),
    );
  }

  /// Thumbnails of the photos: tap to preview, hold and drag to reorder, x to
  /// remove, plus a tile to add more. The first one is the cover.
  Widget _buildFilmstrip() {
    const double size = 60;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: SizedBox(
        height: size + 8,
        child: Row(
          children: [
            Expanded(
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(top: 8),
                itemCount: _photos.length,
                onReorder: _reorderPhotos,
                proxyDecorator: (child, i, anim) => Material(
                  color: Colors.transparent,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                ),
                itemBuilder: (context, i) {
                  final selected = i == _previewIndex;
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(_photos[i].path),
                    index: i,
                    child: GestureDetector(
                      onTap: () => setState(() => _previewIndex = i),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: size,
                          height: size,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: size,
                                height: size,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFFFFB300)
                                        : Colors.transparent,
                                    width: 2.5,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(9.5),
                                  child: Image.file(
                                    _photos[i],
                                    fit: BoxFit.cover,
                                    cacheWidth: 180,
                                  ),
                                ),
                              ),
                              if (i == 0)
                                Positioned(
                                  left: 4,
                                  bottom: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('Cover',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: GestureDetector(
                                  onTap: _isPosting
                                      ? null
                                      : () => _removePhotoAt(i),
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Colors.black87,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_photos.length < _maxPhotos)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: GestureDetector(
                  onTap: _isPosting ? null : () => _openPicker(photos: true),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.colors.textFaint),
                    ),
                    child: Icon(Icons.add, color: context.colors.textMuted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A quiet "Suggest a caption" link above the caption box. Tapped, it
  /// shows a few AI-written ideas as chips; tapping one fills the box.
  Widget _buildCaptionIdeas() {
    final Widget child;
    if (_suggesting) {
      child = Row(
        key: const ValueKey('thinking'),
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.accent),
          ),
          const SizedBox(width: 8),
          Text('Writing captions...',
              style: TextStyle(fontSize: 13, color: context.colors.textMuted)),
        ],
      );
    } else if (_suggestions.isNotEmpty) {
      child = SizedBox(
        key: const ValueKey('ideas'),
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final c in _suggestions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  ),
                  labelStyle:
                  TextStyle(fontSize: 13, color: context.colors.text),
                  backgroundColor: context.colors.accent.withOpacity(0.08),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  onPressed: _isPosting ? null : () => _useSuggestion(c),
                ),
              ),
            IconButton(
              tooltip: 'More ideas',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.refresh, size: 18, color: context.colors.textMuted),
              onPressed: _isPosting ? null : _suggestCaptions,
            ),
          ],
        ),
      );
    } else {
      child = Align(
        key: const ValueKey('button'),
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: _isPosting ? null : _suggestCaptions,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 15, color: context.colors.accent),
              SizedBox(width: 6),
              Text('Suggest a caption',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.accent)),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: child,
      ),
    );
  }

  Widget _buildCaptionAndPost() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCaptionIdeas(),
          TextField(
            controller: _captionController,
            maxLength: 150,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: context.colors.text, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Add a caption...',
              hintStyle: TextStyle(color: context.colors.textFaint),
              counterStyle: TextStyle(color: context.colors.textFaint, fontSize: 11),
              filled: true,
              fillColor: context.colors.surfaceMuted,
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: context.colors.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isPosting ? null : _post,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: context.colors.accent.withOpacity(0.4),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _isPosting
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
                  : const Text('Post',
                  style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}