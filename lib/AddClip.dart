import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'ClipTracker.dart';
import 'clip_service.dart';
import 'UnifiedMediaPicker.dart';

/// Create a Clip: one video (up to 60s) or one photo, plus a caption.
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

  File? _file;
  bool _isVideo = true;
  VideoPlayerController? _videoController;

  bool _showPicker = false;
  bool _isInitializing = false;
  bool _isPosting = false;
  String? _errorMessage;

  bool get _hasMedia => _file != null;

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
      _file = file;
      _isVideo = isVideo;
      _showPicker = false;
      _errorMessage = null;
      _isInitializing = isVideo;
    });

    if (!isVideo) return;

    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted || _file != file) {
        await controller.dispose();
        return;
      }
      controller.setLooping(true);
      controller.play();
      setState(() {
        _videoController = controller;
        _isInitializing = false;
      });
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
    final item = items.first;
    _setMedia(item.file, isVideo: item.isVideo);
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
      _videoController = null;
      _file = null;
      _errorMessage = null;
      _isInitializing = false;
    });
  }

  // ─── Posting ──────────────────────────────────────────────────────────────

  Future<void> _post() async {
    if (_file == null || _isPosting) return;
    FocusScope.of(context).unfocus();
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
        );
      } else {
        success = await ClipService.uploadPhotoClip(
          photoFile: _file!,
          caption: caption,
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
          _videoController = null;
          _file = null;
          _captionController.clear();
        });
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to post clip. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('AddClipScreen: post error: $e');
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text(
          'New Clip',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black),
        ),
        leading: _hasMedia
            ? IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: _isPosting ? null : _clearMedia,
        )
            : (widget.closeable
            ? IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.of(context).maybePop(),
        )
            : null),
      ),
      body: Column(
        children: [
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
          if (_hasMedia) _buildCaptionAndPost(),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: _showPicker
                ? UnifiedMediaPickerPanel(
              height: _pickerHeight,
              title: 'Choose media',
              initialFilter: MediaFilter.videos,
              allowFilterToggle: true,
              singleSelect: true,
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
    color: Colors.grey[50],
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: Colors.grey[800]!, width: 1),
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
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Icon(Icons.play_arrow_rounded,
                    size: 34, color: Colors.grey[800]),
              ),
              const SizedBox(height: 16),
              const Text(
                'Share a moment',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87),
              ),
              const SizedBox(height: 6),
              Text(
                'A video up to 60 seconds, or a photo',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              _primaryButton(
                icon: Icons.photo_library_outlined,
                label: 'Choose from library',
                onTap: () {
                  FocusScope.of(context).unfocus();
                  setState(() => _showPicker = !_showPicker);
                },
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
          backgroundColor: Colors.cyan,
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
          foregroundColor: Colors.black87,
          side: BorderSide(color: Colors.grey[400]!),
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
            // Swap / remove
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
                  child: const Text('Photo',
                      style: TextStyle(
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
      return Image.file(_file!, fit: BoxFit.cover);
    }

    final c = _videoController;
    if (_isInitializing || c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyan, strokeWidth: 2.5),
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

  Widget _buildCaptionAndPost() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _captionController,
            maxLength: 150,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(color: Colors.black87, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Add a caption...',
              hintStyle: TextStyle(color: Colors.grey[500]),
              counterStyle: TextStyle(color: Colors.grey[500], fontSize: 11),
              filled: true,
              fillColor: Colors.grey[100],
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.cyan, width: 1.5),
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
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.cyan.withOpacity(0.4),
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