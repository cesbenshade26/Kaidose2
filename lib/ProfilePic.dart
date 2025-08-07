import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:image_picker/image_picker.dart';
// UNCOMMENT TO ADD ASK FOR PERMISSION TO PHOTOS:
// import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'ProfilePicManager.dart'; // Import the separate manager file
import 'DrawPad.dart';
import 'CamRoll.dart'; // Import the new CamRoll file

// ProfilePicEditor class (keeping this unchanged)
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
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _imageLoaded = false;

  @override
  void initState() {
    super.initState();
    // Simple initialization - mark as loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _imageLoaded = true;
      });
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    // Reset any previous state if needed
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      // Handle scaling
      if (details.scale != 1.0) {
        _scale = (_scale * details.scale).clamp(0.5, 3.0);
      }

      // Handle panning (both touch and mouse)
      _offset += details.focalPointDelta;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // Optional: Add any cleanup or final adjustments here
  }

  Future<void> _cropAndSave() async {
    try {
      final RenderRepaintBoundary boundary =
      _cropKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Create a temporary file in the system temp directory
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
          // Full screen background image (static, shows original image layout)
          Positioned.fill(
            child: Image.file(
              widget.imageFile,
              fit: BoxFit.contain, // This will show the full image with borders/corners
            ),
          ),
          // Dark translucent overlay over everything
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.7),
            ),
          ),
          // Clear circular "hole" in the overlay to show the crop area
          Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
              ),
              child: ClipOval(
                child: Container(
                  color: Colors.transparent,
                  child: Stack(
                    children: [
                      // The actual interactive cropping area
                      Listener(
                        onPointerSignal: (event) {
                          if (event.runtimeType.toString() == 'PointerScrollEvent') {
                            setState(() {
                              // Use reflection to get scroll delta
                              final scrollDelta = (event as dynamic).scrollDelta.dy as double;
                              final scaleDelta = scrollDelta > 0 ? 0.9 : 1.1;
                              _scale = (_scale * scaleDelta).clamp(0.5, 3.0);
                            });
                          }
                        },
                        child: GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
                          child: RepaintBoundary(
                            key: _cropKey,
                            child: ClipOval(
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..translate(_offset.dx, _offset.dy)
                                  ..scale(_scale),
                                child: Image.file(
                                  widget.imageFile,
                                  fit: BoxFit.cover,
                                  width: 300,
                                  height: 300,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Circle border
          Center(
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

          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Text(
              'Drag to move • Pinch/scroll to zoom',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

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

// ProfilePicScreen class - Now using CamRoll for camera roll functionality
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
    // Use the new CamRoll function
    final XFile? image = await CamRoll.openCameraRoll(context);

    if (image != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProfilePicEditor(
            imageFile: File(image.path),
            onImageCropped: (File croppedFile) {
              print('Image cropped! Path: ${croppedFile.path}');

              // Update local state immediately
              setState(() {
                _selectedImage = croppedFile;
              });

              // Update global manager (this should trigger listeners)
              ProfilePicManager.globalProfilePic = croppedFile;

              print('ProfilePicManager.globalProfilePic set to: ${ProfilePicManager.globalProfilePic?.path}');

              // Call the callback if provided
              if (widget.onProfilePicChanged != null) {
                widget.onProfilePicChanged!(croppedFile);
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Profile picture updated!'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ),
      );
    }
  }

  void _openDrawingPad() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          onDrawingComplete: (File drawingFile) {
            print('Drawing completed! File: ${drawingFile.path}');

            // Navigate to ProfilePicEditor with the drawing
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfilePicEditor(
                  imageFile: drawingFile,
                  onImageCropped: (File croppedFile) {
                    print('Drawing cropped! Path: ${croppedFile.path}');

                    // Update local state immediately
                    setState(() {
                      _selectedImage = croppedFile;
                    });

                    // Update global manager
                    ProfilePicManager.globalProfilePic = croppedFile;

                    // Call the callback if provided
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
              // Top half - White background with profile picture
              Expanded(
                flex: 1,
                child: Container(
                  width: double.infinity,
                  color: Colors.white,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60),
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
                                ? Image.file(
                              _selectedImage!,
                              fit: BoxFit.cover,
                              width: 200,
                              height: 200,
                            )
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
              // Bottom half - Grey background with buttons
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
                              onTap: _openCameraRoll, // Now calls the simplified function
                              enabled: true, // Always enabled for testing
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
                          'Tap Photos to select from your camera roll',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Back button
          Positioned(
            top: 50,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.black,
                  size: 24,
                ),
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
            Icon(
              icon,
              size: 32,
              color: enabled ? Colors.grey[700] : Colors.grey[500],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: enabled ? Colors.grey[700] : Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}