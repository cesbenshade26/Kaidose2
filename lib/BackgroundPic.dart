import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:image_picker/image_picker.dart';
// UNCOMMENT TO ADD ASK FOR PERMISSION TO PHOTOS:
// import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'BackgroundPicManager.dart';

// BackgroundPicEditor class - Custom shape editor for background
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
      final String fileName = 'cropped_background_${DateTime.now().millisecondsSinceEpoch}.png';
      final Directory tempDir = Directory.systemTemp;
      final File croppedFile = File('${tempDir.path}/$fileName');
      await croppedFile.writeAsBytes(pngBytes);

      widget.onImageCropped(croppedFile);
      Navigator.pop(context);
    } catch (e) {
      print('Error cropping background image: $e');
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
              fit: BoxFit.contain,
            ),
          ),
          // Dark translucent overlay over everything
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.7),
            ),
          ),
          // Clear phone screen shaped "hole" in the overlay to show the crop area
          Center(
            child: Container(
              width: 350,
              height: 600,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                color: Colors.transparent,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
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
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..translate(_offset.dx, _offset.dy)
                                  ..scale(_scale),
                                child: Image.file(
                                  widget.imageFile,
                                  fit: BoxFit.cover,
                                  width: 350,
                                  height: 600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Profile picture placeholder overlay (to show where profile pic will be)
                      Positioned(
                        top: 80,
                        left: (350 - 160) / 2, // Center horizontally
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.3),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'Profile Pic',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Settings icon placeholder
                      Positioned(
                        top: 50,
                        right: 16,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.settings,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Phone screen border
          Center(
            child: Container(
              width: 350,
              height: 600,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
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

// BackgroundPicScreen class - PERMISSIONS COMMENTED OUT FOR QUICK TESTING
class BackgroundPicScreen extends StatefulWidget {
  final Function(File?)? onBackgroundPicChanged;

  const BackgroundPicScreen({Key? key, this.onBackgroundPicChanged}) : super(key: key);

  @override
  State<BackgroundPicScreen> createState() => _BackgroundPicScreenState();
}

class _BackgroundPicScreenState extends State<BackgroundPicScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _selectedImage = BackgroundPicManager.globalBackgroundPic;
  }

  // UNCOMMENT TO ADD ASK FOR PERMISSION TO PHOTOS:
  /*
  Future<bool> _checkAndRequestPermission() async {
    // Check and request permission only when called
    try {
      PermissionStatus status = await Permission.photos.status;

      if (status.isGranted) {
        return true;
      } else if (status.isPermanentlyDenied) {
        _showSettingsDialog();
        return false;
      } else {
        // For any other status, request permission
        PermissionStatus newStatus = await Permission.photos.request();

        if (newStatus.isGranted) {
          return true;
        } else if (newStatus.isPermanentlyDenied) {
          _showSettingsDialog();
          return false;
        }
        return false;
      }
    } catch (e) {
      // On simulator, permission might not be needed or might fail
      // Let's assume we have permission and try anyway
      print('Permission check failed (likely simulator): $e');
      return true;
    }
  }
  */

  Future<void> _openCameraRoll() async {
    print("Background Photos button tapped!");

    // UNCOMMENT TO ADD ASK FOR PERMISSION TO PHOTOS:
    /*
    // Check permission when the button is tapped
    bool hasPermission = await _checkAndRequestPermission();

    if (!hasPermission) {
      print('No permission to access photos');
      return;
    }
    */

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 80,
      );

      if (image != null) {
        print('Selected background image path: ${image.path}');

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BackgroundPicEditor(
              imageFile: File(image.path),
              onImageCropped: (File croppedFile) {
                print('Background image cropped! Path: ${croppedFile.path}');

                // Update local state immediately
                setState(() {
                  _selectedImage = croppedFile;
                });

                // Update global manager (this should trigger listeners)
                BackgroundPicManager.globalBackgroundPic = croppedFile;

                print('BackgroundPicManager.globalBackgroundPic set to: ${BackgroundPicManager.globalBackgroundPic?.path}');

                // Call the callback if provided
                if (widget.onBackgroundPicChanged != null) {
                  widget.onBackgroundPicChanged!(croppedFile);
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Background picture updated!'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          ),
        );
      } else {
        print('No background image selected - user cancelled');
      }
    } catch (e) {
      print('Error selecting background image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accessing photos: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // UNCOMMENT TO ADD ASK FOR PERMISSION TO PHOTOS:
  /*
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission Required'),
          content: const Text('Please enable photo access in Settings to select a background picture.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Settings'),
            ),
          ],
        );
      },
    );
  }
  */

  void _openDrawingPad() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Background drawing pad coming soon!'),
        duration: Duration(seconds: 2),
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
              // Top half - Current background preview
              Expanded(
                flex: 1,
                child: Container(
                  width: double.infinity,
                  color: _selectedImage != null ? Colors.transparent : Colors.white,
                  child: _selectedImage != null
                      ? Stack(
                    children: [
                      // Background image
                      Positioned.fill(
                        child: Image.file(
                          _selectedImage!,
                          fit: BoxFit.cover,
                        ),
                      ),
                      // Profile picture placeholder overlay
                      Positioned(
                        top: 80,
                        left: (MediaQuery.of(context).size.width - 160) / 2,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.3),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.8),
                              width: 3,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'Profile Pic',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Settings icon placeholder
                      Positioned(
                        top: 50,
                        right: 16,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.8),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.settings,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  )
                      : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60),
                        Icon(
                          Icons.wallpaper,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Background Set',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
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
                              onTap: _openCameraRoll,
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
                        const SizedBox(height: 16),
                        if (_selectedImage != null)
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _selectedImage = null;
                                BackgroundPicManager.globalBackgroundPic = null;
                              });
                              if (widget.onBackgroundPicChanged != null) {
                                widget.onBackgroundPicChanged!(null);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Background picture removed!'),
                                  duration: Duration(seconds: 2),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[600],
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Remove Background'),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'Tap Photos to select a background image',
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