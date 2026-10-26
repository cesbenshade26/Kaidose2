import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'BackgroundPicManager.dart';
import 'ProfilePicManager.dart';
import 'UnifiedMediaPicker.dart';
import 'DrawPad.dart';

/// Shared look of the profile banner so Profile, the selector and the crop
/// screen always agree.
class BackgroundSpec {
  static const double bannerHeight = 130.0;
  static const double avatarSize = 100.0;

  /// Soft cyan -> white, shown when no photo is set.
  static const BoxDecoration defaultDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF4DD0E1), Color(0xFFE0F7FA), Colors.white],
      stops: [0.0, 0.7, 1.0],
    ),
  );

  /// Light dark scrim at the top so status bar / icons stay readable.
  static const BoxDecoration scrimDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x59000000), Color(0x00000000)],
    ),
  );
}

// ---------------------------------------------------------------------------
// Crop screen: choose which part of the photo becomes the banner.
// ---------------------------------------------------------------------------
class BackgroundPicEditor extends StatefulWidget {
  final File imageFile;
  final Function(File) onImageCropped;

  const BackgroundPicEditor({
    Key? key,
    required this.imageFile,
    required this.onImageCropped,
  }) : super(key: key);

  @override
  State<BackgroundPicEditor> createState() => _BackgroundPicEditorState();
}

class _BackgroundPicEditorState extends State<BackgroundPicEditor> {
  final GlobalKey _cropKey = GlobalKey();
  Size? _imageSize;
  double _scale = 1.0; // user zoom on top of "cover"
  Offset _offset = Offset.zero; // image center relative to frame center
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  bool _saving = false;
  File? _profilePic;

  @override
  void initState() {
    super.initState();
    _profilePic = ProfilePicManager.globalProfilePic;
    final stream = FileImage(widget.imageFile).resolve(const ImageConfiguration());
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _imageSize =
            Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
      stream.removeListener(l);
    }, onError: (_, __) {
      if (mounted) Navigator.pop(context);
    });
    stream.addListener(l);
  }

  double _base(Size frame) =>
      (frame.width / _imageSize!.width) > (frame.height / _imageSize!.height)
          ? frame.width / _imageSize!.width
          : frame.height / _imageSize!.height;

  Offset _clamp(Offset o, Size frame) {
    final disp = _imageSize! * (_base(frame) * _scale);
    final maxX = ((disp.width - frame.width) / 2).clamp(0.0, double.infinity);
    final maxY = ((disp.height - frame.height) / 2).clamp(0.0, double.infinity);
    return Offset(o.dx.clamp(-maxX, maxX), o.dy.clamp(-maxY, maxY));
  }

  Future<void> _save(Size frame) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
      _cropKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1200 / frame.width);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
          '${Directory.systemTemp.path}/cropped_background_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data!.buffer.asUint8List());
      widget.onImageCropped(file);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not crop that photo. Try another.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // Same size the banner has on the profile (full width x bannerHeight).
    final frame = Size(width, BackgroundSpec.bannerHeight);
    const avatar = BackgroundSpec.avatarSize;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Position photo',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: true,
      ),
      body: _imageSize == null
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : Column(
        children: [
          const SizedBox(height: 24),
          // Exactly what the profile will show.
          SizedBox(
            width: frame.width,
            height: frame.height + avatar / 2 + 8,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onScaleStart: (d) {
                    _startScale = _scale;
                    _startOffset = _offset;
                    _startFocal = d.focalPoint;
                  },
                  onScaleUpdate: (d) {
                    setState(() {
                      _scale = (_startScale * d.scale).clamp(1.0, 4.0);
                      _offset = _clamp(
                          _startOffset + (d.focalPoint - _startFocal), frame);
                    });
                  },
                  child: RepaintBoundary(
                    key: _cropKey,
                    child: SizedBox(
                      width: frame.width,
                      height: frame.height,
                      child: ClipRect(
                        child: Stack(
                          children: [
                            Positioned(
                              left: frame.width / 2 -
                                  (_imageSize!.width * _base(frame) * _scale) / 2 +
                                  _offset.dx,
                              top: frame.height / 2 -
                                  (_imageSize!.height * _base(frame) * _scale) / 2 +
                                  _offset.dy,
                              width: _imageSize!.width * _base(frame) * _scale,
                              height: _imageSize!.height * _base(frame) * _scale,
                              child: Image.file(widget.imageFile, fit: BoxFit.fill),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Preview-only overlays (not part of the saved crop).
                IgnorePointer(
                  child: Container(
                    width: frame.width,
                    height: frame.height,
                    decoration: BackgroundSpec.scrimDecoration,
                  ),
                ),
                Positioned(
                  top: frame.height - avatar / 2,
                  left: (frame.width - avatar) / 2,
                  child: IgnorePointer(
                    child: Container(
                      width: avatar,
                      height: avatar,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[300],
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: ClipOval(
                        child: _profilePic != null && _profilePic!.existsSync()
                            ? Image.file(_profilePic!, fit: BoxFit.cover)
                            : const DefaultProfilePic(size: avatar, borderWidth: 0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('Drag to move, pinch to zoom',
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const SizedBox(height: 4),
          Text('This is how it will look on your profile',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const Spacer(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : () => _save(frame),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Text('Use this photo',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selector screen: live preview on top, inline photo picker below.
// ---------------------------------------------------------------------------
class BackgroundPicScreen extends StatefulWidget {
  final Function(File?)? onBackgroundPicChanged;

  const BackgroundPicScreen({Key? key, this.onBackgroundPicChanged}) : super(key: key);

  @override
  State<BackgroundPicScreen> createState() => _BackgroundPicScreenState();
}

class _BackgroundPicScreenState extends State<BackgroundPicScreen> {
  File? _selectedImage;
  File? _profilePic;
  VoidCallback? _listener;

  @override
  void initState() {
    super.initState();
    _selectedImage = BackgroundPicManager.globalBackgroundPic;
    _profilePic = ProfilePicManager.globalProfilePic;
    _listener = () {
      if (mounted) setState(() => _selectedImage = BackgroundPicManager.globalBackgroundPic);
    };
    BackgroundPicManager.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) BackgroundPicManager.removeListener(_listener!);
    super.dispose();
  }

  void _openEditor(File file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BackgroundPicEditor(
          imageFile: file,
          onImageCropped: (cropped) {
            BackgroundPicManager.globalBackgroundPic = cropped;
            widget.onBackgroundPicChanged?.call(cropped);
          },
        ),
      ),
    );
  }

  void _openDrawingPad() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrawingScreen(
          onDrawingComplete: (File drawing) {
            Navigator.pop(context); // close the drawing pad
            _openEditor(drawing);
          },
        ),
      ),
    );
  }

  void _removeBackground() {
    BackgroundPicManager.globalBackgroundPic = null;
    setState(() => _selectedImage = null);
    widget.onBackgroundPicChanged?.call(null);
  }

  Widget _preview() {
    const h = BackgroundSpec.bannerHeight;
    const a = BackgroundSpec.avatarSize;
    final hasPic = _selectedImage != null && _selectedImage!.existsSync();

    return SizedBox(
      width: double.infinity,
      height: h + a / 2 + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: h,
            child: hasPic
                ? Image.file(
              _selectedImage!,
              fit: BoxFit.cover,
              key: ValueKey(
                  _selectedImage!.path + _selectedImage!.lastModifiedSync().toString()),
              errorBuilder: (_, __, ___) =>
                  Container(decoration: BackgroundSpec.defaultDecoration),
            )
                : Container(decoration: BackgroundSpec.defaultDecoration),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: h,
            child: IgnorePointer(child: Container(decoration: BackgroundSpec.scrimDecoration)),
          ),
          Positioned(
            top: h - a / 2,
            left: (MediaQuery.of(context).size.width - a) / 2,
            child: Container(
              width: a,
              height: a,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[300],
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: ClipOval(
                child: _profilePic != null && _profilePic!.existsSync()
                    ? Image.file(_profilePic!, fit: BoxFit.cover)
                    : const DefaultProfilePic(size: a, borderWidth: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPic = _selectedImage != null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _preview(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Choose a photo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                if (hasPic)
                  TextButton(
                    onPressed: _removeBackground,
                    style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                    child: const Text('Remove'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                hasPic
                    ? 'Pick a new photo to replace your background.'
                    : 'Optional. Without one, your profile uses a calm default.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => UnifiedMediaPickerPanel(
                height: c.maxHeight,
                title: 'Photos',
                initialFilter: MediaFilter.photos,
                allowFilterToggle: false,
                singleSelect: true,
                showDraw: true,
                onDrawTap: _openDrawingPad,
                onClose: () => Navigator.pop(context),
                onMediaSelected: (items) {
                  if (items.isEmpty) return;
                  _openEditor(items.first.file);
                },
              ),
            ),
          ),
        ],
      ),
      // Back button floats over the banner.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
    );
  }
}