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
import 'ProfilePicManager.dart'; // Import to access profile picture
import 'CamRoll.dart'; // Import the CamRoll functionality
import 'DrawPad.dart'; // Import the DrawPad functionality

// BackgroundPicEditor class - Custom rectangular editor for background
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

    // Get screen dimensions for proper sizing
    final screenSize = MediaQuery.of(context).size;
    final cropWidth = screenSize.width; // Full screen width
    // Height should match the background area: from top to midline of profile pic
    // Profile pic starts at 80px from top, has 160px height, so midline is at 80 + 80 = 160px
    const double cropHeight = 160.0; // Top padding + half profile pic height

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
          // Clear rectangular "hole" in the overlay to show the crop area
          Positioned(
            top: (MediaQuery.of(context).size.height - cropHeight) / 2,
            left: (MediaQuery.of(context).size.width - cropWidth) / 2,
            child: Container(
              width: cropWidth,
              height: cropHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(0), // No border radius for full-width background
                color: Colors.transparent,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(0),
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
                              borderRadius: BorderRadius.circular(0),
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..translate(_offset.dx, _offset.dy)
                                  ..scale(_scale),
                                child: Image.file(
                                  widget.imageFile,
                                  fit: BoxFit.cover,
                                  width: cropWidth,
                                  height: cropHeight,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Profile picture placeholder overlay (to show where profile pic will be)
                      Positioned(
                        bottom: 0, // Position at bottom of background area (midline of profile pic)
                        left: (cropWidth - 160) / 2, // Center horizontally
                        child: Container(
                          width: 160,
                          height: 80, // Only show top half of profile pic (the part that overlaps background)
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(80),
                              topRight: Radius.circular(80),
                            ),
                            color: Colors.black.withOpacity(0.3),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: const Center(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 20),
                              child: Text(
                                'Profile Pic',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Settings icon placeholder
                      Positioned(
                        top: 30,
                        right: 16,
                        child: Container(
                          width: 30,
                          height: 30,
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
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Rectangular border
          Positioned(
            top: (MediaQuery.of(context).size.height - cropHeight) / 2,
            left: (MediaQuery.of(context).size.width - cropWidth) / 2,
            child: Container(
              width: cropWidth,
              height: cropHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(0),
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

// BackgroundPicScreen class - Updated to use CamRoll
class BackgroundPicScreen extends StatefulWidget {
  final Function(File?)? onBackgroundPicChanged;

  const BackgroundPicScreen({Key? key, this.onBackgroundPicChanged}) : super(key: key);

  @override
  State<BackgroundPicScreen> createState() => _BackgroundPicScreenState();
}

class _BackgroundPicScreenState extends State<BackgroundPicScreen> {
  File? _selectedImage;
  File? _profilePic;
  VoidCallback? _profilePicListener;

  @override
  void initState() {
    super.initState();
    _selectedImage = BackgroundPicManager.globalBackgroundPic;
    _profilePic = ProfilePicManager.globalProfilePic;

    // Load profile pic from storage
    _loadProfilePicFromStorage();

    // Create listener for profile pic changes
    _profilePicListener = () {
      print('BackgroundPicScreen: Profile pic changed!');
      if (mounted) {
        setState(() {
          _profilePic = ProfilePicManager.globalProfilePic;
        });
      }
    };

    // Add the listener
    ProfilePicManager.addListener(_profilePicListener!);
  }

  Future<void> _loadProfilePicFromStorage() async {
    await ProfilePicManager.loadProfilePicFromStorage();
    if (mounted) {
      setState(() {
        _profilePic = ProfilePicManager.globalProfilePic;
      });
    }
  }

  @override
  void dispose() {
    if (_profilePicListener != null) {
      ProfilePicManager.removeListener(_profilePicListener!);
    }
    super.dispose();
  }

  Future<void> _openCameraRoll() async {
    print("Background Photos button tapped!");

    // Use CamRoll to open camera roll
    final image = await CamRoll.openCameraRoll(context);

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
  }

  void _openDrawingPad() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          onDrawingComplete: (File drawingFile) {
            print('Background drawing completed! File: ${drawingFile.path}');

            // Navigate to BackgroundPicEditor with the drawing
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BackgroundPicEditor(
                  imageFile: drawingFile,
                  onImageCropped: (File croppedFile) {
                    print('Background drawing cropped! Path: ${croppedFile.path}');

                    // Update local state immediately
                    setState(() {
                      _selectedImage = croppedFile;
                    });

                    // Update global manager
                    BackgroundPicManager.globalBackgroundPic = croppedFile;

                    // Call the callback if provided
                    if (widget.onBackgroundPicChanged != null) {
                      widget.onBackgroundPicChanged!(croppedFile);
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Background picture updated from drawing!'),
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
          // Background and content area
          Column(
            children: [
              // Top portion - Background area (matching profile screen layout)
              Container(
                width: double.infinity,
                height: 160, // Same height as profile screen background area
                color: _selectedImage != null ? Colors.transparent : Colors.white,
                child: _selectedImage != null
                    ? Stack(
                  children: [
                    // Background image - covers full area
                    Positioned.fill(
                      child: Image.file(
                        _selectedImage!,
                        fit: BoxFit.cover,
                        // Add a unique key to force Flutter to reload the image
                        key: ValueKey(_selectedImage!.path + _selectedImage!.lastModifiedSync().toString()),
                        errorBuilder: (context, error, stackTrace) {
                          print('Error loading background image: $error');
                          return Container(
                            color: Colors.grey[300],
                            child: Center(
                              child: Icon(
                                Icons.error,
                                size: 50,
                                color: Colors.grey[600],
                              ),
                            ),
                          );
                        },
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
                          color: Colors.white.withOpacity(0.8),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              spreadRadius: 1,
                              blurRadius: 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.settings,
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                )
                    : Container(
                  color: Colors.white,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wallpaper,
                          size: 50,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No Background Set',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Profile picture area - overlapping the background boundary
              Transform.translate(
                offset: const Offset(0, -80), // Move up to overlap background area
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[300],
                    border: Border.all(
                      color: Colors.grey[400]!,
                      width: 3,
                    ),
                  ),
                  child: ClipOval(
                    child: _profilePic != null && _profilePic!.existsSync()
                        ? Image.file(
                      _profilePic!,
                      fit: BoxFit.cover,
                      width: 160,
                      height: 160,
                      // Add a unique key to force Flutter to reload the image
                      key: ValueKey(_profilePic!.path + _profilePic!.lastModifiedSync().toString()),
                      errorBuilder: (context, error, stackTrace) {
                        print('Error loading profile image: $error');
                        return const DefaultProfilePic(size: 160, borderWidth: 0);
                      },
                    )
                        : const DefaultProfilePic(size: 160, borderWidth: 0),
                  ),
                ),
              ),
              // Bottom area - Grey background with buttons (adjusted for overlapping profile pic)
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -80), // Move up to account for overlapping profile pic
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
                      padding: const EdgeInsets.only(top: 100, left: 20, right: 20, bottom: 20), // Extra top padding for profile pic
                      child: Column(
                        children: [
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