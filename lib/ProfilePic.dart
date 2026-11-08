import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'ProfilePicManager.dart';
import 'UnifiedMediaPicker.dart';
import 'DrawPad.dart';
import 'UseCam.dart';

// ---------------------------------------------------------------------------
// Crop screen: choose which part of the photo becomes your profile picture.
// ---------------------------------------------------------------------------
class ProfilePicEditor extends StatefulWidget {
  final File imageFile;
  final Function(File) onImageCropped;

  const ProfilePicEditor({
    Key? key,
    required this.imageFile,
    required this.onImageCropped,
  }) : super(key: key);

  @override
  State<ProfilePicEditor> createState() => _ProfilePicEditorState();
}

class _ProfilePicEditorState extends State<ProfilePicEditor> {
  final GlobalKey _cropKey = GlobalKey();
  Size? _imageSize;
  double _scale = 1.0; // user zoom on top of "cover"
  Offset _offset = Offset.zero; // image center relative to frame center
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
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

  double _base(double frame) {
    final a = frame / _imageSize!.width;
    final b = frame / _imageSize!.height;
    return a > b ? a : b;
  }

  Offset _clamp(Offset o, double frame) {
    final disp = _imageSize! * (_base(frame) * _scale);
    final maxX = ((disp.width - frame) / 2).clamp(0.0, double.infinity);
    final maxY = ((disp.height - frame) / 2).clamp(0.0, double.infinity);
    return Offset(o.dx.clamp(-maxX, maxX), o.dy.clamp(-maxY, maxY));
  }

  Future<void> _save(double frame) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
      _cropKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 600 / frame);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
          '${Directory.systemTemp.path}/cropped_profile_${DateTime.now().millisecondsSinceEpoch}.png');
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
    final frame = MediaQuery.of(context).size.width - 48;

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
          SizedBox(
            width: frame,
            height: frame,
            child: Stack(
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
                      width: frame,
                      height: frame,
                      child: ClipRect(
                        child: Stack(
                          children: [
                            Positioned(
                              left: frame / 2 -
                                  (_imageSize!.width * _base(frame) * _scale) / 2 +
                                  _offset.dx,
                              top: frame / 2 -
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
                // Preview-only: fades what falls outside the circle.
                IgnorePointer(
                  child: CustomPaint(
                    size: Size(frame, frame),
                    painter: _CircleMaskPainter(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Drag to move, pinch to zoom',
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
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

class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final circle = Path()..addOval(Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2));
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, circle),
      Paint()..color = Colors.white.withOpacity(0.75),
    );
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.cyan,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Selector screen: preview on top, inline photo picker below.
// ---------------------------------------------------------------------------
class ProfilePicScreen extends StatefulWidget {
  final Function(File?)? onProfilePicChanged;

  const ProfilePicScreen({Key? key, this.onProfilePicChanged}) : super(key: key);

  @override
  State<ProfilePicScreen> createState() => _ProfilePicScreenState();
}

class _ProfilePicScreenState extends State<ProfilePicScreen> {
  File? _selectedImage;
  VoidCallback? _listener;

  @override
  void initState() {
    super.initState();
    _selectedImage = ProfilePicManager.globalProfilePic;
    _listener = () {
      if (mounted) setState(() => _selectedImage = ProfilePicManager.globalProfilePic);
    };
    ProfilePicManager.addListener(_listener!);
    // Refresh from Firebase in case another device updated it
    ProfilePicManager.forceRefresh();
  }

  @override
  void dispose() {
    if (_listener != null) ProfilePicManager.removeListener(_listener!);
    super.dispose();
  }

  void _openEditor(File file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePicEditor(
          imageFile: file,
          onImageCropped: (cropped) {
            ProfilePicManager.globalProfilePic = cropped;
            widget.onProfilePicChanged?.call(cropped);
          },
        ),
      ),
    );
  }

  Future<void> _openCamera() async {
    final image = await UseCam.openCamera(context);
    if (image != null && mounted) _openEditor(File(image.path));
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

  void _useDefault() {
    ProfilePicManager.globalProfilePic = null;
    setState(() => _selectedImage = null);
    widget.onProfilePicChanged?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final hasPic = _selectedImage != null && _selectedImage!.existsSync();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text('Profile photo',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[300],
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: ClipOval(
              child: hasPic
                  ? Image.file(
                _selectedImage!,
                fit: BoxFit.cover,
                key: ValueKey(_selectedImage!.path + _selectedImage!.lastModifiedSync().toString()),
                errorBuilder: (_, __, ___) => const DefaultProfilePic(size: 140, borderWidth: 0),
              )
                  : const DefaultProfilePic(size: 140, borderWidth: 0),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _openCamera,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Take photo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  side: BorderSide(color: Colors.grey[300]!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
              if (hasPic) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _useDefault,
                  style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                  child: const Text('Use default'),
                ),
              ],
            ],
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
    );
  }
}