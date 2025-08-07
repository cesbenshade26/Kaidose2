import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'; // Add this for PointerScrollEvent
import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'CamRoll.dart'; // Import the CamRoll utility

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drawing App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: DrawingScreen(),
    );
  }
}

enum DrawingTool { pencil, eraser, straightLine, shapes, text, photos }

enum ShapeType { rectangle, circle, triangle, heart, star, arrow }

class DrawingScreen extends StatefulWidget {
  final Function(File)? onDrawingComplete;

  const DrawingScreen({Key? key, this.onDrawingComplete}) : super(key: key);

  @override
  _DrawingScreenState createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  Map<File, ui.Image?> _imageCache = {};
  bool _isDraggingImage = false;
  String? _activeHandle;
  final GlobalKey _canvasKey = GlobalKey();
  List<DrawnElement> elements = <DrawnElement>[];
  DrawnLine? currentLine;
  DrawingTool selectedTool = DrawingTool.pencil;
  ShapeType selectedShape = ShapeType.rectangle;
  Color selectedColor = Colors.black;
  double strokeWidth = 5.0;
  Offset? straightLineStart;
  DrawnLine? previewLine;
  Offset? shapeStart;
  DrawnShape? previewShape;
  bool showShapeMenu = false;

  // Text tool variables
  Offset? textStart;
  DrawnTextBox? previewTextBox;
  DrawnTextBox? selectedTextBox;
  bool showTextOptions = false;
  TextEditingController textController = TextEditingController();
  bool isEditingText = false;

  // Image tool variables
  Offset? imageStart;
  DrawnImage? previewImage;
  DrawnImage? selectedImage;
  bool isInImageEditMode = false;

  // Pinch zoom variables for image resizing
  double _initialImageScale = 1.0;
  Size? _initialImageSize;

  // Desktop interaction variables
  bool _isShiftPressed = false;
  bool _isAltPressed = false;
  Offset? _lastPanPosition;

  Paint get paint {
    Paint paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth;

    if (selectedTool == DrawingTool.eraser) {
      paint.blendMode = BlendMode.clear;
    } else {
      paint.color = selectedColor;
    }

    return paint;
  }

  PaintingStyle get paintingStyle {
    if (strokeWidth >= 25.0) {
      return PaintingStyle.fill;
    } else if (strokeWidth >= 15.0) {
      return PaintingStyle.stroke;
    } else {
      return PaintingStyle.stroke;
    }
  }

  double get effectiveStrokeWidth {
    if (strokeWidth >= 25.0) {
      return 0;
    } else if (strokeWidth >= 15.0) {
      return strokeWidth * 0.6;
    } else {
      return strokeWidth * 0.3;
    }
  }

  String? _getResizeHandle(Offset position, Rect bounds) {
    final handleSize = 16.0; // Size of the handle hit area
    final handleRadius = handleSize / 2;

    // Check each corner handle
    if ((position - bounds.topLeft).distance <= handleRadius) {
      return 'topLeft';
    } else if ((position - bounds.topRight).distance <= handleRadius) {
      return 'topRight';
    } else if ((position - bounds.bottomLeft).distance <= handleRadius) {
      return 'bottomLeft';
    } else if ((position - bounds.bottomRight).distance <= handleRadius) {
      return 'bottomRight';
    }

    return null;
  }

  DrawnImage _resizeImage(DrawnImage image, String handle, Offset currentPosition) {
    Rect bounds = image.bounds;
    Offset newStartPoint = image.startPoint;
    Offset newEndPoint = image.endPoint;

    // Minimum size constraint
    const double minSize = 50.0;

    switch (handle) {
      case 'topLeft':
        newStartPoint = Offset(
          min(currentPosition.dx, bounds.right - minSize),
          min(currentPosition.dy, bounds.bottom - minSize),
        );
        break;

      case 'topRight':
        newStartPoint = Offset(
          bounds.left,
          min(currentPosition.dy, bounds.bottom - minSize),
        );
        newEndPoint = Offset(
          max(currentPosition.dx, bounds.left + minSize),
          bounds.bottom,
        );
        break;

      case 'bottomLeft':
        newStartPoint = Offset(
          min(currentPosition.dx, bounds.right - minSize),
          bounds.top,
        );
        newEndPoint = Offset(
          bounds.right,
          max(currentPosition.dy, bounds.top + minSize),
        );
        break;

      case 'bottomRight':
        newEndPoint = Offset(
          max(currentPosition.dx, bounds.left + minSize),
          max(currentPosition.dy, bounds.top + minSize),
        );
        break;
    }

    return image.copyWith(
      startPoint: newStartPoint,
      endPoint: newEndPoint,
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
        focusNode: FocusNode(),
    autofocus: true,
    onKeyEvent: (KeyEvent event) {
    setState(() {
    _isShiftPressed = HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) ||
    HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftRight);
    _isAltPressed = HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.altLeft) ||
    HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.altRight);
    });
    },
    child: Scaffold(
    backgroundColor: Colors.white,
    body: Stack(
    children: [
    Column(
    children: [
    SafeArea(
    bottom: false,
    child: Container(
    padding: const EdgeInsets.all(8.0),
    child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
    IconButton(
    onPressed: () => Navigator.pop(context),
    icon: Icon(Icons.arrow_back),
    ),
    if (isInImageEditMode)
    ElevatedButton(
    onPressed: _finishImageEditing,
    style: ElevatedButton.styleFrom(
    backgroundColor: Colors.green,
    foregroundColor: Colors.white,
    ),
    child: Text('Done'),
    ),
    if (!isInImageEditMode)
    ElevatedButton(
    onPressed: _saveDrawingAndReturn,
    style: ElevatedButton.styleFrom(
    backgroundColor: Colors.blue,
    foregroundColor: Colors.white,
    ),
    child: Text('Confirm'),
    ),
    ],
    ),
    ),
    ),
    Expanded(
    child: Container(
    width: double.infinity,
    color: Colors.white,
    child: RepaintBoundary(
    key: _canvasKey,
    child: Container(
    color: Colors.white,
    child: Listener(
    onPointerSignal: (pointerSignal) {
    if (pointerSignal is PointerScrollEvent && isInImageEditMode && selectedImage != null) {
    // Handle scroll wheel for desktop resizing
    if (selectedImage!.bounds.contains(pointerSignal.position)) {
    setState(() {
    final scrollDelta = pointerSignal.scrollDelta.dy;
    final scaleFactor = scrollDelta > 0 ? 0.9 : 1.1; // Zoom out or in

    final center = selectedImage!.bounds.center;
    final currentSize = selectedImage!.bounds.size;
    final newSize = Size(
    currentSize.width * scaleFactor,
    currentSize.height * scaleFactor,
    );

    // Maintain proportions and center the scaling
    selectedImage = selectedImage!.copyWith(
    startPoint: Offset(
    center.dx - newSize.width / 2,
    center.dy - newSize.height / 2,
    ),
    endPoint: Offset(
    center.dx + newSize.width / 2,
    center.dy + newSize.height / 2,
    ),
    );

    // Update the element in the list
    final index = elements.indexWhere((element) => element == selectedImage);
    if (index != -1) {
    elements[index] = selectedImage!;
    }
    });
    }
    }
    },
    child: GestureDetector(
    onTapUp: _handleTapUp,
    onDoubleTap: _handleDoubleTap,
    onScaleStart: (details) {
    _lastPanPosition = details.localFocalPoint;

    if (isInImageEditMode && selectedImage != null) {
    // Check if the touch started on the image
    if (selectedImage!.bounds.contains(details.localFocalPoint)) {
    setState(() {
    _isDraggingImage = true;
    _initialImageScale = 1.0;
    _initialImageSize = selectedImage!.bounds.size;
    });
    return;
    }
    }

    if (isInImageEditMode) return; // Block other tools when in image edit mode

    // Handle other tools with single pointer
    if (details.pointerCount == 1) {
    _handlePanStart(details.localFocalPoint);
    }
    },
    onScaleUpdate: (details) {
    if (isInImageEditMode && selectedImage != null && _isDraggingImage) {
    setState(() {
    // Handle translation (dragging) - works on both mobile and desktop
    if (details.scale == 1.0 || details.pointerCount == 1) {
    final delta = details.localFocalPoint - _lastPanPosition!;
    selectedImage = selectedImage!.copyWith(
    startPoint: selectedImage!.startPoint + delta,
    endPoint: selectedImage!.endPoint + delta,
    );
    _lastPanPosition = details.localFocalPoint;
    }
    // Handle scaling (pinch zoom) - only works on mobile
    else if (details.pointerCount > 1 && _initialImageSize != null) {
    final scale = details.scale;
    final center = selectedImage!.bounds.center;
    final newSize = Size(
    _initialImageSize!.width * scale,
    _initialImageSize!.height * scale,
    );

    // Maintain proportions and center the scaling
    selectedImage = selectedImage!.copyWith(
    startPoint: Offset(
    center.dx - newSize.width / 2,
    center.dy - newSize.height / 2,
    ),
    endPoint: Offset(
    center.dx + newSize.width / 2,
    center.dy + newSize.height / 2,
    ),
    );
    }

    // Update the element in the list
    final index = elements.indexWhere((element) => element == selectedImage);
    if (index != -1) {
    elements[index] = selectedImage!;
    }
    });
    return;
    }

    if (isInImageEditMode) return; // Block other tools when in image edit mode

    // Handle other tools with single pointer
    if (details.pointerCount == 1) {
    final delta = details.localFocalPoint - _lastPanPosition!;
    _handlePanUpdate(details.localFocalPoint, delta);
    _lastPanPosition = details.localFocalPoint;
    }
    },
    onScaleEnd: (details) {
    setState(() {
    _isDraggingImage = false;
    _activeHandle = null;
    _initialImageScale = 1.0;
    _initialImageSize = null;
    _lastPanPosition = null;
    });

    if (isInImageEditMode) return; // Block other tools when in image edit mode

    _handlePanEnd();
    },
    child: CustomPaint(
    painter: DrawingPainter(
    elements,
    currentLine,
    previewLine,
    previewShape,
    previewTextBox,
    selectedTextBox,
    previewImage,
    selectedImage,
    _imageCache,
    ),
    size: Size.infinite,
    ),
    ),
    ),
    ),
    ),
    ),
    ),
    Container(
    decoration: BoxDecoration(
    color: Colors.black,
    borderRadius: BorderRadius.only(
    topLeft: Radius.circular(20),
    topRight: Radius.circular(20),
    ),
    ),
    child: SafeArea(
    top: false,
    child: Padding(
    padding: EdgeInsets.fromLTRB(8, 8, 8, 8),
    child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
    if (isInImageEditMode)
    Container(
    padding: EdgeInsets.all(16),
    child: Column(
    children: [
    Text(
    Platform.isIOS || Platform.isAndroid
    ? 'Drag to move • Two-finger pinch to resize'
        : 'Drag to move • Mouse wheel to resize',
    style: TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    ),
    textAlign: TextAlign.center,
    ),
    SizedBox(height: 4),
    Text(
    'Tap Done when finished',
    style: TextStyle(
    color: Colors.white70,
    fontSize: 14,
    ),
    textAlign: TextAlign.center,
    ),
    ],
    ),
    )
    else ...[
    Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
    _buildToolButton(DrawingTool.pencil, Icon(Icons.edit, color: Colors.white)),
    _buildToolButton(DrawingTool.eraser, Icon(Icons.cleaning_services, color: Colors.white)),
    _buildToolButton(DrawingTool.straightLine, Icon(Icons.remove, color: Colors.white)),
    _buildToolButton(DrawingTool.shapes, Icon(Icons.category, color: Colors.white)),
    _buildToolButton(DrawingTool.text, Icon(Icons.text_fields, color: Colors.white)),
    _buildToolButton(DrawingTool.photos, Icon(Platform.isIOS ? Icons.photo_library : Icons.photo, color: Colors.white)),
    ],
    ),
    SizedBox(height: 8),
    Row(
    children: [
    Expanded(
    child: Column(
    children: [
    Text('Thickness', style: TextStyle(color: Colors.white, fontSize: 12)),
    Slider(
    value: strokeWidth,
    min: 1.0,
    max: 30.0,
    divisions: 29,
    activeColor: Colors.white,
    inactiveColor: Colors.grey,
    onChanged: (value) {
    setState(() {
    strokeWidth = value;
    });
    },
    ),
    ],
    ),
    ),
    SizedBox(width: 16),
    Expanded(child: _buildColorPicker()),
    ],
    ),
    ],
    ],
    ),
    ),
    ),
    ),
    ],
    ),
    if (showShapeMenu)
    Positioned(
    bottom: 220,
    left: MediaQuery.of(context).size.width * 0.66 - 80,
    child: _buildShapeMenu(),
    ),
    if (showTextOptions && selectedTextBox != null)
    Positioned(
    left: selectedTextBox!.bounds.right + 10,
    top: selectedTextBox!.bounds.top,
    child: _buildTextOptionsMenu(),
    ),
    if (isEditingText && selectedTextBox != null)
    Positioned(
    left: selectedTextBox!.bounds.left,
    top: selectedTextBox!.bounds.top,
    width: selectedTextBox!.bounds.width,
    height: selectedTextBox!.bounds.height,
    child: _buildTextEditor(),
    ),
    if (isEditingText && selectedTextBox != null)
    Positioned(
    left: selectedTextBox!.bounds.right + 5,
    top: selectedTextBox!.bounds.bottom + 5,
    child: _buildDoneButton(),
    ),
    ],
    ),
    ));
  }

  void _handleDoubleTap() {
    if (isInImageEditMode) return; // Block double tap in image edit mode

    if (selectedTextBox != null) {
      _startTextEditing();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (isInImageEditMode) {
      // In image edit mode, only allow interaction with the selected image
      return;
    }

    if (isEditingText) {
      _finishTextEditing();
      return;
    }

    // Check if user tapped on the menu button of a selected text box
    if (selectedTextBox != null) {
      final menuButtonRect = Rect.fromLTWH(
        selectedTextBox!.bounds.right + 5,
        selectedTextBox!.bounds.top,
        20,
        20,
      );

      if (menuButtonRect.contains(details.localPosition)) {
        setState(() {
          showTextOptions = !showTextOptions;
        });
        return;
      }
    }

    // Check if user tapped on a text box
    for (var element in elements.reversed) {
      if (element is DrawnTextBox) {
        if (element.bounds.contains(details.localPosition)) {
          setState(() {
            selectedTextBox = element;
            showTextOptions = false;
            isEditingText = false;
            selectedImage = null; // Deselect image when selecting text
          });
          return;
        }
      } else if (element is DrawnImage) {
        if (element.bounds.contains(details.localPosition)) {
          setState(() {
            selectedImage = element;
            selectedTextBox = null; // Deselect text when selecting image
            showTextOptions = false;
            isEditingText = false;
          });
          return;
        }
      }
    }

    // If nothing was tapped, deselect everything
    setState(() {
      selectedTextBox = null;
      selectedImage = null;
      showTextOptions = false;
      isEditingText = false;
    });
  }

  Future<void> _loadImage(File imageFile) async {
    if (_imageCache.containsKey(imageFile)) return;

    try {
      final bytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _imageCache[imageFile] = frame.image;
    } catch (e) {
      print('Error loading image: $e');
      _imageCache[imageFile] = null;
    }
  }

  Future<void> _openPhotos() async {
    print("Photos button tapped in DrawPad!");

    final image = await CamRoll.openCameraRoll(context);

    if (image != null) {
      final File imageFile = File(image.path);

      // Load and cache the actual image
      await _loadImage(imageFile);

      final Size canvasSize = MediaQuery.of(context).size;
      final Offset center = Offset(canvasSize.width / 2, canvasSize.height / 2);

      final double defaultSize = 200.0;
      final Offset topLeft = Offset(center.dx - defaultSize / 2, center.dy - defaultSize / 2);
      final Offset bottomRight = Offset(center.dx + defaultSize / 2, center.dy + defaultSize / 2);

      final DrawnImage drawnImage = DrawnImage(
        startPoint: topLeft,
        endPoint: bottomRight,
        imageFile: imageFile,
      );

      setState(() {
        elements.add(drawnImage);
        selectedImage = drawnImage;
        selectedTextBox = null;
        showTextOptions = false;
        isEditingText = false;
        isInImageEditMode = true; // Enter image edit mode
      });

      print('Image added to drawing: ${imageFile.path}');
    }
  }

  void _finishImageEditing() {
    setState(() {
      isInImageEditMode = false;
      selectedImage = null; // Deselect the image
      _isDraggingImage = false;
      _activeHandle = null;
    });
  }

  void _handlePanStart(Offset localPosition) {
    if (selectedImage != null) {
      final handle = _getResizeHandle(localPosition, selectedImage!.bounds);
      if (handle != null) {
        setState(() {
          _activeHandle = handle;
          _isDraggingImage = false;
        });
        return;
      } else if (selectedImage!.bounds.contains(localPosition)) {
        setState(() {
          _isDraggingImage = true;
          _activeHandle = null;
        });
        return;
      }
    }
    if (selectedTool == DrawingTool.text) {
      setState(() {
        textStart = localPosition;
        previewTextBox = null;
        selectedTextBox = null;
        showTextOptions = false;
        isEditingText = false;
      });
    } else if (selectedTool == DrawingTool.straightLine) {
      setState(() {
        straightLineStart = localPosition;
        previewLine = null;
      });
    } else if (selectedTool == DrawingTool.shapes) {
      setState(() {
        shapeStart = localPosition;
        previewShape = null;
      });
    } else if (selectedTool == DrawingTool.pencil || selectedTool == DrawingTool.eraser) {
      setState(() {
        currentLine = DrawnLine([localPosition], paint);
      });
    }
  }

  void _handlePanUpdate(Offset localPosition, Offset delta) {
    if (selectedImage != null) {
      if (_activeHandle != null) {
        setState(() {
          selectedImage = _resizeImage(selectedImage!, _activeHandle!, localPosition);
          final index = elements.indexOf(selectedImage!);
          if (index != -1) {
            elements[index] = selectedImage!;
          }
        });
        return;
      } else if (_isDraggingImage) {
        setState(() {
          selectedImage = selectedImage!.copyWith(
            startPoint: selectedImage!.startPoint + delta,
            endPoint: selectedImage!.endPoint + delta,
          );
          final index = elements.indexOf(selectedImage!);
          if (index != -1) {
            elements[index] = selectedImage!;
          }
        });
        return;
      }
    }
    if (selectedTool == DrawingTool.text) {
      setState(() {
        if (textStart != null) {
          previewTextBox = DrawnTextBox(
            startPoint: textStart!,
            endPoint: localPosition,
            text: 'Text',
            fontSize: 16.0,
            fontFamily: 'Arial',
            color: selectedColor,
            isBold: false,
            isItalic: false,
            isUnderlined: false,
          );
        }
      });
    } else if (selectedTool == DrawingTool.straightLine) {
      setState(() {
        if (straightLineStart != null) {
          previewLine = DrawnLine([straightLineStart!, localPosition], paint);
        }
      });
    } else if (selectedTool == DrawingTool.shapes) {
      setState(() {
        if (shapeStart != null) {
          previewShape = DrawnShape(
            shapeStart!,
            localPosition,
            selectedShape,
            paint.color,
            paintingStyle,
            effectiveStrokeWidth,
          );
        }
      });
    } else if (selectedTool == DrawingTool.pencil || selectedTool == DrawingTool.eraser) {
      setState(() {
        currentLine = DrawnLine(
          [...currentLine!.path, localPosition],
          currentLine!.paint,
        );
      });
    }
  }

  void _handlePanEnd() {
    if (selectedTool == DrawingTool.text) {
      setState(() {
        if (textStart != null && previewTextBox != null) {
          elements.add(previewTextBox!);
        }
        textStart = null;
        previewTextBox = null;
      });
    } else if (selectedTool == DrawingTool.straightLine) {
      setState(() {
        if (straightLineStart != null && previewLine != null) {
          elements.add(previewLine!);
        }
        straightLineStart = null;
        previewLine = null;
      });
    } else if (selectedTool == DrawingTool.shapes) {
      setState(() {
        if (shapeStart != null && previewShape != null) {
          elements.add(previewShape!);
        }
        shapeStart = null;
        previewShape = null;
      });
    } else if (selectedTool == DrawingTool.pencil || selectedTool == DrawingTool.eraser) {
      setState(() {
        if (currentLine != null) {
          elements.add(currentLine!);
        }
        currentLine = null;
      });
    }
  }

  Widget _buildToolButton(DrawingTool tool, Widget icon) {
    bool isSelected = selectedTool == tool;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (tool == DrawingTool.shapes) {
            showShapeMenu = !showShapeMenu;
          } else {
            showShapeMenu = false;
          }

          if (tool == DrawingTool.photos) {
            _openPhotos();
            return;
          }

          selectedTool = tool;
          selectedTextBox = null;
          selectedImage = null;
          showTextOptions = false;
          isEditingText = false;
        });
      },
      child: Container(
        width: 42,
        height: 50,
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey[800] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Center(child: icon),
      ),
    );
  }

  Widget _buildShapeMenu() {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildShapeButton(ShapeType.rectangle, Icons.crop_square, 'Rectangle'),
          SizedBox(height: 4),
          _buildShapeButton(ShapeType.circle, Icons.circle_outlined, 'Circle'),
          SizedBox(height: 4),
          _buildShapeButton(ShapeType.triangle, Icons.change_history, 'Triangle'),
          SizedBox(height: 4),
          _buildShapeButton(ShapeType.heart, Icons.favorite, 'Heart'),
          SizedBox(height: 4),
          _buildShapeButton(ShapeType.star, Icons.star, 'Star'),
          SizedBox(height: 4),
          _buildShapeButton(ShapeType.arrow, Icons.arrow_forward, 'Arrow'),
        ],
      ),
    );
  }

  Widget _buildShapeButton(ShapeType shape, IconData icon, String label) {
    bool isSelected = selectedShape == shape;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedShape = shape;
          showShapeMenu = false;
        });
      },
      child: Container(
        width: 120,
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey[600] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(label, style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneButton() {
    return GestureDetector(
      onTap: _finishTextEditing,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          'Done',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildTextEditor() {
    return Container(
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue, width: 2),
        color: Colors.white.withOpacity(0.9),
      ),
      child: TextField(
        controller: textController,
        autofocus: true,
        maxLines: null,
        textInputAction: TextInputAction.done,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          fontSize: selectedTextBox!.fontSize,
          fontFamily: selectedTextBox!.fontFamily,
          color: selectedTextBox!.color,
          fontWeight: selectedTextBox!.isBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: selectedTextBox!.isItalic ? FontStyle.italic : FontStyle.normal,
          decoration: selectedTextBox!.isUnderlined ? TextDecoration.underline : TextDecoration.none,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.all(2),
          hintText: 'Type here...',
          hintStyle: TextStyle(
            color: Colors.grey.withOpacity(0.7),
            fontSize: selectedTextBox!.fontSize,
          ),
        ),
        onSubmitted: (value) => _finishTextEditing(),
        onChanged: (value) {
          // Update text in real-time if needed
          setState(() {
            final index = elements.indexOf(selectedTextBox!);
            if (index != -1) {
              elements[index] = selectedTextBox!.copyWith(text: value);
              selectedTextBox = elements[index] as DrawnTextBox;
            }
          });
        },
      ),
    );
  }

  void _startTextEditing() {
    if (selectedTextBox != null) {
      setState(() {
        textController.text = selectedTextBox!.text;
        isEditingText = true;
        showTextOptions = false;
      });
    }
  }

  void _finishTextEditing() {
    if (selectedTextBox != null && isEditingText) {
      setState(() {
        // Text is already updated via onChanged, so just finish editing
        isEditingText = false;
        // Hide keyboard
        FocusScope.of(context).unfocus();
      });
    }
  }

  Widget _buildTextOptionsMenu() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Font Size', style: TextStyle(color: Colors.white, fontSize: 12)),
          SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextOptionButton('-', () => _changeFontSize(-2)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('${selectedTextBox!.fontSize.toInt()}',
                    style: TextStyle(color: Colors.white)),
              ),
              _buildTextOptionButton('+', () => _changeFontSize(2)),
            ],
          ),
          SizedBox(height: 8),
          Text('Font Family', style: TextStyle(color: Colors.white, fontSize: 12)),
          SizedBox(height: 4),
          DropdownButton<String>(
            value: selectedTextBox!.fontFamily,
            dropdownColor: Colors.grey[700],
            style: TextStyle(color: Colors.white, fontSize: 12),
            items: ['Arial', 'Times New Roman', 'Helvetica', 'Georgia']
                .map((font) => DropdownMenuItem(
              value: font,
              child: Text(font, style: TextStyle(color: Colors.white)),
            ))
                .toList(),
            onChanged: (value) => _changeFontFamily(value!),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextStyleButton('B', selectedTextBox!.isBold, () => _toggleBold()),
              SizedBox(width: 4),
              _buildTextStyleButton('I', selectedTextBox!.isItalic, () => _toggleItalic()),
              SizedBox(width: 4),
              _buildTextStyleButton('U', selectedTextBox!.isUnderlined, () => _toggleUnderline()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextOptionButton(String text, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.grey[600],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(text, style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildTextStyleButton(String text, bool isActive, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.grey[600],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: text == 'B' && isActive ? FontWeight.bold : FontWeight.normal,
              fontStyle: text == 'I' && isActive ? FontStyle.italic : FontStyle.normal,
              decoration: text == 'U' && isActive ? TextDecoration.underline : TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }

  void _changeFontSize(double delta) {
    if (selectedTextBox != null) {
      setState(() {
        final index = elements.indexOf(selectedTextBox!);
        if (index != -1) {
          final newFontSize = (selectedTextBox!.fontSize + delta).clamp(8.0, 72.0);
          elements[index] = selectedTextBox!.copyWith(fontSize: newFontSize);
          selectedTextBox = elements[index] as DrawnTextBox;
        }
      });
    }
  }

  void _changeFontFamily(String fontFamily) {
    if (selectedTextBox != null) {
      setState(() {
        final index = elements.indexOf(selectedTextBox!);
        if (index != -1) {
          elements[index] = selectedTextBox!.copyWith(fontFamily: fontFamily);
          selectedTextBox = elements[index] as DrawnTextBox;
        }
      });
    }
  }

  void _toggleBold() {
    if (selectedTextBox != null) {
      setState(() {
        final index = elements.indexOf(selectedTextBox!);
        if (index != -1) {
          elements[index] = selectedTextBox!.copyWith(isBold: !selectedTextBox!.isBold);
          selectedTextBox = elements[index] as DrawnTextBox;
        }
      });
    }
  }

  void _toggleItalic() {
    if (selectedTextBox != null) {
      setState(() {
        final index = elements.indexOf(selectedTextBox!);
        if (index != -1) {
          elements[index] = selectedTextBox!.copyWith(isItalic: !selectedTextBox!.isItalic);
          selectedTextBox = elements[index] as DrawnTextBox;
        }
      });
    }
  }

  void _toggleUnderline() {
    if (selectedTextBox != null) {
      setState(() {
        final index = elements.indexOf(selectedTextBox!);
        if (index != -1) {
          elements[index] = selectedTextBox!.copyWith(isUnderlined: !selectedTextBox!.isUnderlined);
          selectedTextBox = elements[index] as DrawnTextBox;
        }
      });
    }
  }

  Widget _buildColorPicker() {
    List<Color> colors = [
      Colors.black,
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.yellow,
      Colors.orange,
      Colors.purple,
      Colors.pink,
    ];

    return GridView.builder(
      shrinkWrap: true,
      itemCount: colors.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        Color color = colors[index];
        bool isSelected = selectedColor == color;
        return GestureDetector(
          onTap: () {
            setState(() {
              selectedColor = color;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.grey,
                width: isSelected ? 2 : 1,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveDrawingAndReturn() async {
    try {
      final RenderRepaintBoundary boundary =
      _canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final String fileName = 'drawing_${DateTime.now().millisecondsSinceEpoch}.png';
      final Directory tempDir = Directory.systemTemp;
      final File drawingFile = File('${tempDir.path}/$fileName');
      await drawingFile.writeAsBytes(pngBytes);

      print('Drawing saved to: ${drawingFile.path}');

      if (widget.onDrawingComplete != null) {
        widget.onDrawingComplete!(drawingFile);
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error saving drawing: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving drawing: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

abstract class DrawnElement {}

class DrawnLine extends DrawnElement {
  final List<Offset> path;
  final Paint paint;

  DrawnLine(this.path, this.paint);
}

class DrawnShape extends DrawnElement {
  final Offset startPoint;
  final Offset endPoint;
  final ShapeType shapeType;
  final Color color;
  final PaintingStyle style;
  final double strokeWidth;

  DrawnShape(this.startPoint, this.endPoint, this.shapeType, this.color, this.style, this.strokeWidth);

  Rect get bounds {
    return Rect.fromPoints(startPoint, endPoint);
  }
}

class DrawnImage extends DrawnElement {
  final Offset startPoint;
  final Offset endPoint;
  final File imageFile;

  DrawnImage({
    required this.startPoint,
    required this.endPoint,
    required this.imageFile,
  });

  Rect get bounds {
    return Rect.fromPoints(startPoint, endPoint);
  }

  DrawnImage copyWith({
    Offset? startPoint,
    Offset? endPoint,
    File? imageFile,
  }) {
    return DrawnImage(
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      imageFile: imageFile ?? this.imageFile,
    );
  }
}

class DrawnTextBox extends DrawnElement {
  final Offset startPoint;
  final Offset endPoint;
  final String text;
  final double fontSize;
  final String fontFamily;
  final Color color;
  final bool isBold;
  final bool isItalic;
  final bool isUnderlined;

  DrawnTextBox({
    required this.startPoint,
    required this.endPoint,
    required this.text,
    required this.fontSize,
    required this.fontFamily,
    required this.color,
    required this.isBold,
    required this.isItalic,
    required this.isUnderlined,
  });

  Rect get bounds {
    return Rect.fromPoints(startPoint, endPoint);
  }

  DrawnTextBox copyWith({
    Offset? startPoint,
    Offset? endPoint,
    String? text,
    double? fontSize,
    String? fontFamily,
    Color? color,
    bool? isBold,
    bool? isItalic,
    bool? isUnderlined,
  }) {
    return DrawnTextBox(
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      color: color ?? this.color,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderlined: isUnderlined ?? this.isUnderlined,
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawnElement> elements;
  final DrawnLine? currentLine;
  final DrawnLine? previewLine;
  final DrawnShape? previewShape;
  final DrawnTextBox? previewTextBox;
  final DrawnTextBox? selectedTextBox;
  final DrawnImage? previewImage;
  final DrawnImage? selectedImage;
  final Map<File, ui.Image?> imageCache;

  DrawingPainter(
      this.elements,
      this.currentLine,
      this.previewLine,
      this.previewShape,
      this.previewTextBox,
      this.selectedTextBox,
      this.previewImage,
      this.selectedImage,
      this.imageCache,
      );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (var element in elements) {
      if (element is DrawnLine) {
        _drawLine(canvas, element);
      } else if (element is DrawnShape) {
        _drawShape(canvas, element);
      } else if (element is DrawnTextBox) {
        _drawTextBox(canvas, element, element == selectedTextBox);
      } else if (element is DrawnImage) {
        _drawImage(canvas, element, element == selectedImage);
      }
    }

    if (currentLine != null) {
      _drawLine(canvas, currentLine!);
    }

    if (previewLine != null && previewLine!.path.length == 2) {
      final previewPaint = Paint()
        ..color = previewLine!.paint.color.withOpacity(0.7)
        ..strokeWidth = previewLine!.paint.strokeWidth
        ..strokeCap = previewLine!.paint.strokeCap
        ..strokeJoin = previewLine!.paint.strokeJoin;
      canvas.drawLine(previewLine!.path[0], previewLine!.path[1], previewPaint);
    }

    if (previewShape != null) {
      _drawShape(canvas, previewShape!, isPreview: true);
    }

    if (previewTextBox != null) {
      _drawTextBox(canvas, previewTextBox!, false, isPreview: true);
    }

    if (previewImage != null) {
      _drawImage(canvas, previewImage!, false, isPreview: true);
    }

    canvas.restore();
  }

  void _drawLine(Canvas canvas, DrawnLine line) {
    if (line.path.length > 1) {
      for (int i = 0; i < line.path.length - 1; i++) {
        canvas.drawLine(line.path[i], line.path[i + 1], line.paint);
      }
    }
  }

  void _drawShape(Canvas canvas, DrawnShape shape, {bool isPreview = false}) {
    final paint = Paint()
      ..color = isPreview ? shape.color.withOpacity(0.7) : shape.color
      ..style = shape.style
      ..strokeWidth = shape.strokeWidth;

    final bounds = shape.bounds;

    switch (shape.shapeType) {
      case ShapeType.rectangle:
        canvas.drawRect(bounds, paint);
        break;
      case ShapeType.circle:
        final center = bounds.center;
        final radius = (bounds.width + bounds.height) / 4;
        canvas.drawCircle(center, radius, paint);
        break;
      case ShapeType.triangle:
        final path = Path();
        path.moveTo(bounds.center.dx, bounds.top);
        path.lineTo(bounds.left, bounds.bottom);
        path.lineTo(bounds.right, bounds.bottom);
        path.close();
        canvas.drawPath(path, paint);
        break;
      case ShapeType.heart:
        final path = _createHeartPath(bounds);
        canvas.drawPath(path, paint);
        break;
      case ShapeType.star:
        final path = _createStarPath(bounds);
        canvas.drawPath(path, paint);
        break;
      case ShapeType.arrow:
        final path = _createArrowPath(bounds);
        canvas.drawPath(path, paint);
        break;
    }
  }

  void _drawImage(Canvas canvas, DrawnImage drawnImage, bool isSelected, {bool isPreview = false}) {
    final bounds = drawnImage.bounds;

    // Try to get the cached image
    final ui.Image? cachedImage = imageCache[drawnImage.imageFile];

    if (cachedImage != null) {
      // Draw the actual image
      canvas.drawImageRect(
        cachedImage,
        Rect.fromLTWH(0, 0, cachedImage.width.toDouble(), cachedImage.height.toDouble()),
        bounds,
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      // Draw placeholder while image loads
      final placeholderPaint = Paint()
        ..color = isPreview ? Colors.grey.withOpacity(0.3) : Colors.grey.withOpacity(0.1);

      canvas.drawRect(bounds, placeholderPaint);

      // Draw a camera icon as placeholder
      final iconSize = bounds.width * 0.3;
      final iconCenter = bounds.center;
      final iconBounds = Rect.fromCenter(
        center: iconCenter,
        width: iconSize,
        height: iconSize,
      );

      final iconPaint = Paint()
        ..color = Colors.grey[600]!
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(iconBounds, Radius.circular(4)),
        iconPaint,
      );

      final lensRadius = iconSize * 0.25;
      canvas.drawCircle(iconCenter, lensRadius, Paint()..color = Colors.grey[800]!);
    }

    // Draw image border when selected or preview
    if (isSelected || isPreview) {
      final borderPaint = Paint()
        ..color = isSelected ? Colors.blue : Colors.grey.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.0 : 1.0;

      canvas.drawRect(bounds, borderPaint);

      // Add a subtle instruction text for interactions when selected
      if (isSelected) {
        final textStyle = TextStyle(
          fontSize: 12,
          color: Colors.blue.withOpacity(0.8),
          fontWeight: FontWeight.w500,
        );

        final instructionText = Platform.isIOS || Platform.isAndroid
            ? 'Drag to move • Pinch to resize'
            : 'Drag to move • Scroll to resize';

        final textSpan = TextSpan(
          text: instructionText,
          style: textStyle,
        );

        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );

        textPainter.layout();

        // Position the text below the image
        final textPosition = Offset(
          bounds.center.dx - textPainter.width / 2,
          bounds.bottom + 8,
        );

        textPainter.paint(canvas, textPosition);
      }
    }
  }

  void _drawResizeHandles(Canvas canvas, Rect bounds) {
    final handleSize = 8.0;
    final handlePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    // Corner handles
    final handles = [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ];

    for (final handle in handles) {
      canvas.drawCircle(handle, handleSize / 2, handlePaint);
    }
  }

  void _drawTextBox(Canvas canvas, DrawnTextBox textBox, bool isSelected, {bool isPreview = false}) {
    final bounds = textBox.bounds;

    // Draw text box border when selected or preview
    if (isSelected || isPreview) {
      final borderPaint = Paint()
        ..color = isSelected ? Colors.blue : Colors.grey.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.0 : 1.0;

      canvas.drawRect(bounds, borderPaint);
    }

    // Draw text
    final textStyle = TextStyle(
      fontSize: textBox.fontSize,
      fontFamily: textBox.fontFamily,
      color: isPreview ? textBox.color.withOpacity(0.7) : textBox.color,
      fontWeight: textBox.isBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: textBox.isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: textBox.isUnderlined ? TextDecoration.underline : TextDecoration.none,
    );

    final textSpan = TextSpan(text: textBox.text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    textPainter.layout(maxWidth: bounds.width);
    textPainter.paint(canvas, bounds.topLeft + Offset(4, 4));

    // Draw menu button (three lines) when selected
    if (isSelected) {
      final menuButtonRect = Rect.fromLTWH(
        bounds.right + 5,
        bounds.top,
        20,
        20,
      );

      // Draw button background
      final buttonPaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(menuButtonRect, Radius.circular(4)),
        buttonPaint,
      );

      // Draw three horizontal lines
      final linePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5;

      final lineStart = menuButtonRect.left + 4;
      final lineEnd = menuButtonRect.right - 4;

      // Top line
      canvas.drawLine(
        Offset(lineStart, menuButtonRect.top + 5),
        Offset(lineEnd, menuButtonRect.top + 5),
        linePaint,
      );

      // Middle line
      canvas.drawLine(
        Offset(lineStart, menuButtonRect.center.dy),
        Offset(lineEnd, menuButtonRect.center.dy),
        linePaint,
      );

      // Bottom line
      canvas.drawLine(
        Offset(lineStart, menuButtonRect.bottom - 5),
        Offset(lineEnd, menuButtonRect.bottom - 5),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;

  Path _createHeartPath(Rect bounds) {
    final path = Path();
    final width = bounds.width;
    final height = bounds.height;
    final left = bounds.left;
    final top = bounds.top;

    path.moveTo(left + width * 0.5, top + height * 0.25);
    path.cubicTo(
      left + width * 0.2, top,
      left, top + height * 0.22,
      left + width * 0.5, top + height * 0.6,
    );
    path.cubicTo(
      left + width, top + height * 0.22,
      left + width * 0.8, top,
      left + width * 0.5, top + height * 0.25,
    );
    path.close();
    return path;
  }

  Path _createStarPath(Rect bounds) {
    final path = Path();
    final centerX = bounds.center.dx;
    final centerY = bounds.center.dy;
    final outerRadius = bounds.width.abs() / 2;
    final innerRadius = outerRadius * 0.4;

    for (int i = 0; i < 10; i++) {
      final angle = (i * 36 - 90) * (3.14159 / 180);
      final radius = i % 2 == 0 ? outerRadius : innerRadius;
      final x = centerX + radius * cos(angle);
      final y = centerY + radius * sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  Path _createArrowPath(Rect bounds) {
    final path = Path();
    final left = bounds.left;
    final right = bounds.right;
    final top = bounds.top;
    final bottom = bounds.bottom;
    final centerY = bounds.center.dy;
    final width = bounds.width;
    final height = bounds.height;

    // Arrow pointing right
    path.moveTo(left, centerY - height * 0.1);
    path.lineTo(right - width * 0.3, centerY - height * 0.1);
    path.lineTo(right - width * 0.3, top);
    path.lineTo(right, centerY);
    path.lineTo(right - width * 0.3, bottom);
    path.lineTo(right - width * 0.3, centerY + height * 0.1);
    path.lineTo(left, centerY + height * 0.1);
    path.close();
    return path;
  }}