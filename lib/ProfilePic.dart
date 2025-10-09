import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'ProfilePicManager.dart';
import 'DrawPad.dart';
import 'CamRoll.dart';
import 'UseCam.dart';

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
  final GlobalKey _imageKey = GlobalKey();
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _imageLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _imageLoaded = true;
      });
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      if (details.scale != 1.0) {
        _scale = (_scale * details.scale).clamp(0.5, 3.0);
      }
      _offset += details.focalPointDelta;
    });
  }

  Future<void> _cropAndSave() async {
    try {
      final RenderBox renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
      final size = renderBox.size;

      // Calculate the circle's position and size
      final circleSize = 300.0;
      final circleCenter = Offset(size.width / 2, size.height / 2);
      final circleRect = Rect.fromCircle(center: circleCenter, radius: circleSize / 2);

      // Create a picture recorder to capture just the circular area
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Clip to circular area
      canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, circleSize, circleSize)));

      // Load and decode the image
      final imageBytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final originalImage = frame.image;

      // Calculate source rectangle from the original image based on scale and offset
      final imageWidth = originalImage.width.toDouble();
      final imageHeight = originalImage.height.toDouble();
      final imageAspect = imageWidth / imageHeight;
      final screenAspect = size.width / size.height;

      double displayWidth, displayHeight;
      if (imageAspect > screenAspect) {
        displayHeight = size.height;
        displayWidth = displayHeight * imageAspect;
      } else {
        displayWidth = size.width;
        displayHeight = displayWidth / imageAspect;
      }

      // Apply scale
      displayWidth *= _scale;
      displayHeight *= _scale;

      // Calculate the image position on screen
      final imageLeft = (size.width - displayWidth) / 2 + _offset.dx;
      final imageTop = (size.height - displayHeight) / 2 + _offset.dy;

      // Calculate what portion of the image is visible in the circle
      final visibleLeft = (circleRect.left - imageLeft) / displayWidth;
      final visibleTop = (circleRect.top - imageTop) / displayHeight;
      final visibleWidth = circleSize / displayWidth;
      final visibleHeight = circleSize / displayHeight;

      // Define source rectangle from original image
      final srcRect = Rect.fromLTWH(
        (visibleLeft * imageWidth).clamp(0, imageWidth),
        (visibleTop * imageHeight).clamp(0, imageHeight),
        (visibleWidth * imageWidth).clamp(0, imageWidth),
        (visibleHeight * imageHeight).clamp(0, imageHeight),
      );

      // Draw the portion of the image
      final dstRect = Rect.fromLTWH(0, 0, circleSize, circleSize);
      canvas.drawImageRect(originalImage, srcRect, dstRect, Paint());

      // Convert to image
      final picture = recorder.endRecording();
      final img = await picture.toImage(circleSize.toInt(), circleSize.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // Save to file
      final String fileName = 'cropped_profile_${DateTime.now().millisecondsSinceEpoch}.png';
      final Directory tempDir = Directory.systemTemp;
      final File croppedFile = File('${tempDir.path}/$fileName');
      await croppedFile.writeAsBytes(pngBytes);

      widget.onImageCropped(croppedFile);
      Navigator.pop(context);
    } catch (e) {
      print('Error cropping image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cropping image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_imageLoaded) {
      return const Scaffold(
        backgroundColor: Colors.black54,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen interactive image
          Positioned.fill(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  setState(() {
                    final scrollDelta = event.scrollDelta.dy;
                    final scaleDelta = scrollDelta > 0 ? 0.9 : 1.1;
                    _scale = (_scale * scaleDelta).clamp(0.5, 3.0);
                  });
                }
              },
              child: GestureDetector(
                onScaleUpdate: _onScaleUpdate,
                child: Container(
                  key: _imageKey,
                  color: Colors.black,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..translate(_offset.dx, _offset.dy)
                      ..scale(_scale),
                    child: Center(
                      child: Image.file(
                        widget.imageFile,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Dark overlay with circular hole
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: CircularHolePainter(),
              ),
            ),
          ),

          // Circle border
          Center(
            child: IgnorePointer(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),

          // Instructions text
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Text(
                'Drag to move • Pinch/scroll to zoom',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: 50,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Confirm button
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: _cropAndSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: const Text(
                  'Confirm',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter to create the dark overlay with circular hole
class CircularHolePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final circlePath = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: 150,
      ));

    final fullScreenPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final holePath = Path.combine(
      PathOperation.difference,
      fullScreenPath,
      circlePath,
    );

    canvas.drawPath(holePath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ProfilePicScreen class - keeping this unchanged
class ProfilePicScreen extends StatefulWidget {
  final Function(File?)? onProfilePicChanged;

  const ProfilePicScreen({Key? key, this.onProfilePicChanged}) : super(key: key);

  @override
  State<ProfilePicScreen> createState() => _ProfilePicScreenState();
}

class _ProfilePicScreenState extends State<ProfilePicScreen> {
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _selectedImage = ProfilePicManager.globalProfilePic;
  }

  Future<void> _openCameraRoll() async {
    final XFile? image = await CamRoll.openCameraRoll(context);
    if (image != null) {
      _navigateToEditor(image, 'Photos');
    }
  }

  Future<void> _openCamera() async {
    final XFile? image = await UseCam.openCamera(context);
    if (image != null) {
      _navigateToEditor(image, 'Camera');
    }
  }

  void _navigateToEditor(XFile image, String source) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePicEditor(
          imageFile: File(image.path),
          onImageCropped: (File croppedFile) {
            print('Image from $source cropped! Path: ${croppedFile.path}');
            setState(() {
              _selectedImage = croppedFile;
            });
            ProfilePicManager.globalProfilePic = croppedFile;
            print('ProfilePicManager.globalProfilePic set to: ${ProfilePicManager.globalProfilePic?.path}');
            if (widget.onProfilePicChanged != null) {
              widget.onProfilePicChanged!(croppedFile);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Profile picture updated from $source!'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ),
    );
  }

  void _openDrawingPad() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          onDrawingComplete: (File drawingFile) {
            print('Drawing completed! File: ${drawingFile.path}');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfilePicEditor(
                  imageFile: drawingFile,
                  onImageCropped: (File croppedFile) {
                    print('Drawing cropped! Path: ${croppedFile.path}');
                    setState(() {
                      _selectedImage = croppedFile;
                    });
                    ProfilePicManager.globalProfilePic = croppedFile;
                    if (widget.onProfilePicChanged != null) {
                      widget.onProfilePicChanged!(croppedFile);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile picture updated from drawing!'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  width: double.infinity,
                  color: Colors.white,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[300],
                            border: Border.all(
                              color: Colors.grey[400]!,
                              width: 3,
                            ),
                          ),
                          child: ClipOval(
                            child: _selectedImage != null
                                ? Image.file(_selectedImage!, fit: BoxFit.cover, width: 200, height: 200)
                                : const DefaultProfilePic(size: 200, borderWidth: 0),
                          ),
                        ),
                        if (_selectedImage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _selectedImage = null;
                                  ProfilePicManager.globalProfilePic = null;
                                });
                                if (widget.onProfilePicChanged != null) {
                                  widget.onProfilePicChanged!(null);
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Profile picture removed!'),
                                    duration: Duration(seconds: 2),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[600],
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Remove Photo'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildOptionButton(
                              icon: Platform.isIOS ? Icons.photo_library : Icons.photo,
                              label: 'Photos',
                              onTap: _openCameraRoll,
                              enabled: true,
                            ),
                            _buildOptionButton(
                              icon: Icons.camera_alt,
                              label: 'Camera',
                              onTap: _openCamera,
                              enabled: true,
                            ),
                            _buildOptionButton(
                              icon: Icons.edit,
                              label: 'Draw',
                              onTap: _openDrawingPad,
                              enabled: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Tap Photos to select from camera roll, Camera to take a new photo, or Draw to create art',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 50,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey[400],
          borderRadius: BorderRadius.circular(15),
          boxShadow: enabled ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: enabled ? Colors.grey[700] : Colors.grey[500]),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: enabled ? Colors.grey[700] : Colors.grey[500], fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}