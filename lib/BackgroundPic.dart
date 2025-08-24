import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'BackgroundPicManager.dart';
import 'ProfilePicManager.dart';
import 'CamRoll.dart';
import 'DrawPad.dart';

// BackgroundPicEditor - Updated to show profile picture preview
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
  File? _profilePic;

  @override
  void initState() {
    super.initState();
    _profilePic = ProfilePicManager.globalProfilePic;
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
      final RenderRepaintBoundary boundary =
      _cropKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final String fileName = 'cropped_background_${DateTime.now().millisecondsSinceEpoch}.png';
      final Directory tempDir = Directory.systemTemp;
      final File croppedFile = File('${tempDir.path}/$fileName');
      await croppedFile.writeAsBytes(pngBytes);

      widget.onImageCropped(croppedFile);
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cropping image: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_imageLoaded) {
      return const Scaffold(
        backgroundColor: Colors.black54,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    const double cropHeight = 160.0;
    const double profilePicSize = 160.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.file(widget.imageFile, fit: BoxFit.contain),
          ),
          // Dark overlay
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.7)),
          ),
          // Crop area with profile picture preview
          Positioned(
            top: (screenSize.height - cropHeight) / 2,
            left: 0,
            right: 0,
            height: cropHeight,
            child: Stack(
              children: [
                // Editable background crop area
                GestureDetector(
                  onScaleUpdate: _onScaleUpdate,
                  child: RepaintBoundary(
                    key: _cropKey,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..translate(_offset.dx, _offset.dy)
                        ..scale(_scale),
                      child: Image.file(
                        widget.imageFile,
                        fit: BoxFit.cover,
                        width: screenSize.width,
                        height: cropHeight,
                      ),
                    ),
                  ),
                ),
                // Profile picture preview overlay (non-interactive)
                Positioned(
                  top: cropHeight - (profilePicSize * 3/4), // Position so 3/4 overlaps background, 1/4 extends below
                  left: (screenSize.width - profilePicSize) / 2, // Center horizontally
                  child: Container(
                    width: profilePicSize,
                    height: profilePicSize,
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
                        width: profilePicSize,
                        height: profilePicSize,
                      )
                          : DefaultProfilePic(size: profilePicSize, borderWidth: 0),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Border around crop area
          Positioned(
            top: (screenSize.height - cropHeight) / 2,
            left: 0,
            right: 0,
            height: cropHeight,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
          // Instructions
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Text(
              'Drag to move • Pinch to zoom\nProfile picture preview shown',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          // Back button
          Positioned(
            top: 50,
            left: 16,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white, size: 24),
              onPressed: () => Navigator.pop(context),
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
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: Text('Confirm', style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// BackgroundPicScreen - Fixed profile picture positioning
class BackgroundPicScreen extends StatefulWidget {
  final Function(File?)? onBackgroundPicChanged;

  const BackgroundPicScreen({Key? key, this.onBackgroundPicChanged}) : super(key: key);

  @override
  State<BackgroundPicScreen> createState() => _BackgroundPicScreenState();
}

class _BackgroundPicScreenState extends State<BackgroundPicScreen> {
  File? _selectedImage;
  File? _profilePic;
  bool _showSeparator = false;
  Color _separatorColor = Colors.black;

  final List<Color> _colorOptions = [
    Colors.black,
    Colors.grey,
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.purple,
    Colors.orange,
  ];

  @override
  void initState() {
    super.initState();
    _selectedImage = BackgroundPicManager.globalBackgroundPic;
    _profilePic = ProfilePicManager.globalProfilePic;
    _showSeparator = BackgroundPicManager.showSeparator;
    _separatorColor = BackgroundPicManager.separatorColor;
  }

  Future<void> _openCameraRoll() async {
    final image = await CamRoll.openCameraRoll(context);
    if (image != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BackgroundPicEditor(
            imageFile: File(image.path),
            onImageCropped: (File croppedFile) {
              setState(() {
                _selectedImage = croppedFile;
              });
              BackgroundPicManager.globalBackgroundPic = croppedFile;
              if (widget.onBackgroundPicChanged != null) {
                widget.onBackgroundPicChanged!(croppedFile);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Background updated!'), backgroundColor: Colors.green),
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
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BackgroundPicEditor(
                  imageFile: drawingFile,
                  onImageCropped: (File croppedFile) {
                    setState(() {
                      _selectedImage = croppedFile;
                    });
                    BackgroundPicManager.globalBackgroundPic = croppedFile;
                    if (widget.onBackgroundPicChanged != null) {
                      widget.onBackgroundPicChanged!(croppedFile);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Background updated from drawing!'), backgroundColor: Colors.green),
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

  void _removeBackground() {
    setState(() {
      _selectedImage = null;
      _showSeparator = false;
    });
    BackgroundPicManager.globalBackgroundPic = null;
    if (widget.onBackgroundPicChanged != null) {
      widget.onBackgroundPicChanged!(null);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Background removed!'), backgroundColor: Colors.orange),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // Background area
              Container(
                width: double.infinity,
                height: 160, // Background height
                color: Colors.white,
                child: Stack(
                  children: [
                    // Background image (if exists)
                    if (_selectedImage != null)
                      Image.file(_selectedImage!, fit: BoxFit.cover, width: double.infinity, height: 160),

                    // Separator line at bottom of background (if enabled)
                    if (_showSeparator && _selectedImage != null)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(height: 3, color: _separatorColor),
                      ),

                    // Settings gear icon preview
                    if (_selectedImage != null)
                      Positioned(
                        top: 50,
                        right: 16,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.8),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.settings, size: 20),
                        ),
                      ),

                    // No background state
                    if (_selectedImage == null)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wallpaper, size: 50, color: Colors.grey[400]),
                            SizedBox(height: 8),
                            Text('No Background Set', style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Profile picture - Fixed positioning to match main profile screen
              Transform.translate(
                offset: Offset(0, -120), // Position so only 1/4 (40px) extends below background
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[300],
                    border: Border.all(color: Colors.grey[400]!, width: 3),
                  ),
                  child: ClipOval(
                    child: _profilePic != null
                        ? Image.file(_profilePic!, fit: BoxFit.cover)
                        : DefaultProfilePic(size: 160, borderWidth: 0),
                  ),
                ),
              ),

              // Content area - Adjusted spacing
              Expanded(
                child: Transform.translate(
                  offset: Offset(0, -120), // Adjusted to maintain proper spacing with new profile position
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(top: 100, left: 20, right: 20, bottom: 20),
                      child: Column(
                        children: [
                          // Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildButton(Icons.photo, 'Photos', _openCameraRoll),
                              _buildButton(Icons.edit, 'Draw', _openDrawingPad),
                            ],
                          ),
                          SizedBox(height: 16),
                          if (_selectedImage != null)
                            ElevatedButton(
                              onPressed: _removeBackground,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[600]),
                              child: Text('Remove Background', style: TextStyle(color: Colors.white)),
                            ),
                          SizedBox(height: 16),
                          Text(
                            'Tap Photos to select a background image',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                          Spacer(),
                          // Border options
                          Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  spreadRadius: 1,
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _showSeparator,
                                      onChanged: (value) {
                                        setState(() => _showSeparator = value ?? false);
                                        BackgroundPicManager.setSeparatorSettings(_showSeparator, _separatorColor);
                                      },
                                    ),
                                    Text('Add bottom border', style: TextStyle(fontSize: 16)),
                                  ],
                                ),
                                if (_showSeparator) ...[
                                  SizedBox(height: 12),
                                  Text('Border color:', style: TextStyle(color: Colors.grey)),
                                  SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: _colorOptions.map((color) {
                                      return GestureDetector(
                                        onTap: () {
                                          setState(() => _separatorColor = color);
                                          BackgroundPicManager.setSeparatorSettings(_showSeparator, color);
                                        },
                                        child: Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: color,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _separatorColor == color ? Colors.blue : Colors.grey[300]!,
                                              width: _separatorColor == color ? 3 : 1,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
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
            child: IconButton(
              icon: Icon(Icons.arrow_back, size: 24),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 3,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.grey[700]),
            SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}