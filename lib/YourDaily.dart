import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'CamRoll.dart';
import 'dart:io';
import 'DailyPhotoManager.dart';
import 'DailyPhotoTracker.dart';

class UseCam {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> openCamera(BuildContext context) async {
    print("Camera button tapped!");

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image != null) {
        print('Captured image path: ${image.path}');
        return image;
      } else {
        print('No image captured - user cancelled');
        return null;
      }
    } catch (e) {
      print('Error accessing camera: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accessing camera: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }
}

class YourDailyWidget extends StatefulWidget {
  const YourDailyWidget({Key? key}) : super(key: key);

  @override
  State<YourDailyWidget> createState() => _YourDailyWidgetState();
}

class _YourDailyWidgetState extends State<YourDailyWidget> with TickerProviderStateMixin {
  File? _selectedPhoto;
  File? _currentDisplayPhoto;
  int _currentPhotoIndex = -1;
  List<File> _todaysPhotos = [];
  VoidCallback? _trackerListener;

  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    _initializeTracker();

    _trackerListener = () {
      if (mounted) {
        setState(() {
          _todaysPhotos = DailyPhotoTracker.todaysPhotos;
          if (_todaysPhotos.isNotEmpty && _currentPhotoIndex == -1 && _selectedPhoto == null) {
            _currentPhotoIndex = _todaysPhotos.length - 1;
            _currentDisplayPhoto = _todaysPhotos[_currentPhotoIndex];
          }
        });
      }
    };

    DailyPhotoTracker.addListener(_trackerListener!);
  }

  @override
  void dispose() {
    _slideController.dispose();
    if (_trackerListener != null) {
      DailyPhotoTracker.removeListener(_trackerListener!);
    }
    super.dispose();
  }

  Future<void> _initializeTracker() async {
    await DailyPhotoTracker.initialize();
    if (mounted) {
      setState(() {
        _todaysPhotos = DailyPhotoTracker.todaysPhotos;
        if (_todaysPhotos.isNotEmpty) {
          _currentPhotoIndex = _todaysPhotos.length - 1;
          _currentDisplayPhoto = _todaysPhotos[_currentPhotoIndex];
        }
      });
    }
  }

  Future<void> _openCameraRoll() async {
    print("Opening camera roll...");
    final XFile? pickedFile = await CamRoll.openCameraRoll(context);
    if (pickedFile != null) {
      print('Camera roll image selected: ${pickedFile.path}');
      final File imageFile = File(pickedFile.path);

      await _slideToPosition(-1);

      setState(() {
        _selectedPhoto = imageFile;
        _currentDisplayPhoto = imageFile;
        _currentPhotoIndex = -1;
      });
      print('Selected photo set in state: ${_selectedPhoto?.path}');
    } else {
      print('No image selected from camera roll');
    }
  }

  Future<void> _openCamera() async {
    print("Opening camera...");
    final XFile? pickedFile = await UseCam.openCamera(context);
    if (pickedFile != null) {
      print('Camera image captured: ${pickedFile.path}');
      final File imageFile = File(pickedFile.path);

      await _slideToPosition(-1);

      setState(() {
        _selectedPhoto = imageFile;
        _currentDisplayPhoto = imageFile;
        _currentPhotoIndex = -1;
      });
      print('Selected photo set in state: ${_selectedPhoto?.path}');
    } else {
      print('No image captured from camera');
    }
  }

  Future<void> _addAnotherDaily() async {
    print("Add another daily tapped!");

    await _slideToPosition(-1);

    setState(() {
      _selectedPhoto = null;
      _currentDisplayPhoto = null;
      _currentPhotoIndex = -1;
    });
  }

  Future<void> _slideToPosition(int targetIndex, [int direction = 1]) async {
    if (targetIndex == _currentPhotoIndex || _isAnimating) return;

    setState(() {
      _isAnimating = true;
    });

    _slideController.reset();

    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: direction > 0 ? 1.0 : -1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    await _slideController.forward();

    setState(() {
      _isAnimating = false;
    });

    _slideController.reset();
  }

  void _navigatePhotos(int direction) async {
    if (_todaysPhotos.isEmpty || _isAnimating) return;

    int newIndex;
    if (_currentPhotoIndex == -1) {
      if (direction > 0) {
        newIndex = 0;
      } else {
        return;
      }
    } else {
      newIndex = (_currentPhotoIndex + direction).clamp(-1, _todaysPhotos.length - 1);
      if (newIndex == -1) {
        await _slideToPosition(-1, direction);
        setState(() {
          _selectedPhoto = null;
          _currentDisplayPhoto = null;
          _currentPhotoIndex = -1;
        });
        return;
      }
    }

    if (newIndex >= 0 && newIndex < _todaysPhotos.length) {
      await _slideToPosition(newIndex, direction);
      setState(() {
        _currentPhotoIndex = newIndex;
        _currentDisplayPhoto = _todaysPhotos[_currentPhotoIndex];
        _selectedPhoto = null;
      });
    }
  }

  Future<void> _confirmPhoto(String buttonType) async {
    print('========== CONFIRM PHOTO DEBUG ($buttonType) ==========');
    print('_selectedPhoto: ${_selectedPhoto?.path ?? "NULL"}');
    print('_selectedPhoto exists: ${_selectedPhoto?.existsSync() ?? false}');

    if (_selectedPhoto != null && _selectedPhoto!.existsSync()) {
      print('Valid photo found, proceeding with save...');

      if (buttonType == "Share with Friends") {
        if (mounted) {
          showDialog(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: const Text('Coming Soon!'),
              content: const Text('Share with friends settings coming soon.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it!'),
                ),
              ],
            ),
          );
        }
        return;
      }

      try {
        await DailyPhotoTracker.addPhoto(_selectedPhoto!);
        await DailyPhotoManager.setDailyPhoto(_selectedPhoto!);

        print('Photo saved via both systems');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Daily photo saved as $buttonType!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }

        setState(() {
          _todaysPhotos = DailyPhotoTracker.todaysPhotos;
          _currentPhotoIndex = _todaysPhotos.length - 1;
          _currentDisplayPhoto = _todaysPhotos[_currentPhotoIndex];
          _selectedPhoto = null;
        });

        print('Daily photo confirmed and saved successfully as $buttonType');
      } catch (e) {
        print('ERROR in _confirmPhoto: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving photo: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      print('NO VALID PHOTO - showing dialog');
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Your Daily Awaits!'),
            content: const Text('Select a photo from Camera Roll or take a new one to create Your Daily moment.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it!'),
              ),
            ],
          ),
        );
      }
    }
    print('========== END CONFIRM PHOTO DEBUG ==========');
  }

  bool get _isInNewPhotoMode => _currentPhotoIndex == -1;
  bool get _canNavigateLeft => _todaysPhotos.isNotEmpty && (_currentPhotoIndex > 0 || (_isInNewPhotoMode && _todaysPhotos.isNotEmpty));
  bool get _canNavigateRight => _todaysPhotos.isNotEmpty && _currentPhotoIndex < _todaysPhotos.length - 1;

  @override
  Widget build(BuildContext context) {
    print('YourDaily build - Current photo index: $_currentPhotoIndex');
    print('Today\'s photos count: ${_todaysPhotos.length}');
    print('Is in new photo mode: $_isInNewPhotoMode');

    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!, width: 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedBuilder(
                        animation: _slideAnimation,
                        builder: (context, child) {
                          return Stack(
                            children: [
                              Transform.translate(
                                offset: Offset(-_slideAnimation.value * MediaQuery.of(context).size.width, 0),
                                child: Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  child: _currentDisplayPhoto != null && _currentDisplayPhoto!.existsSync()
                                      ? Image.file(
                                    _currentDisplayPhoto!,
                                    fit: BoxFit.cover,
                                    key: ValueKey('current_${_currentDisplayPhoto!.path}'),
                                    errorBuilder: (context, error, stackTrace) {
                                      print('Error loading preview image: $error');
                                      return Container(
                                        color: Colors.grey[200],
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                                              const SizedBox(height: 8),
                                              Text('Error loading image', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                      : Container(
                                    color: Colors.grey[50],
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.photo_size_select_actual_outlined, size: 64, color: Colors.grey[400]),
                                          const SizedBox(height: 16),
                                          Text('Photo Preview', style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_isAnimating && _slideAnimation.value > 0) ...[
                                Transform.translate(
                                  offset: Offset(MediaQuery.of(context).size.width - (_slideAnimation.value * MediaQuery.of(context).size.width), 0),
                                  child: Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    child: _currentPhotoIndex + 1 < _todaysPhotos.length && _currentPhotoIndex >= 0
                                        ? Image.file(_todaysPhotos[_currentPhotoIndex + 1], fit: BoxFit.cover, key: ValueKey('next_${_todaysPhotos[_currentPhotoIndex + 1].path}'))
                                        : (_currentPhotoIndex == -1 && _todaysPhotos.isNotEmpty)
                                        ? Image.file(_todaysPhotos[0], fit: BoxFit.cover, key: ValueKey('first_${_todaysPhotos[0].path}'))
                                        : Container(color: Colors.grey[50]),
                                  ),
                                ),
                              ],
                              if (_isAnimating && _slideAnimation.value < 0) ...[
                                Transform.translate(
                                  offset: Offset(-MediaQuery.of(context).size.width - (_slideAnimation.value * MediaQuery.of(context).size.width), 0),
                                  child: Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    child: _currentPhotoIndex - 1 >= 0
                                        ? Image.file(_todaysPhotos[_currentPhotoIndex - 1], fit: BoxFit.cover, key: ValueKey('prev_${_todaysPhotos[_currentPhotoIndex - 1].path}'))
                                        : Container(
                                      color: Colors.grey[50],
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.photo_size_select_actual_outlined, size: 64, color: Colors.grey[400]),
                                            const SizedBox(height: 16),
                                            Text('Photo Preview', style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (_canNavigateLeft && !_isAnimating)
                  Positioned(
                    left: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => _navigatePhotos(-1),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle),
                          child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                if (_canNavigateRight && !_isAnimating)
                  Positioned(
                    right: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => _navigatePhotos(1),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle),
                          child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!_isInNewPhotoMode && _todaysPhotos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Posted photo ${_currentPhotoIndex + 1} of ${_todaysPhotos.length}', style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500), textAlign: TextAlign.center),
          ),
        if (_isInNewPhotoMode && _selectedPhoto != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _confirmPhoto("Share with Friends"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Share with Friends!', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _confirmPhoto("Daily Post"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Daily Post!', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (_isInNewPhotoMode) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _openCameraRoll,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library, size: 24),
                            SizedBox(width: 12),
                            Text('Camera Roll', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _openCamera,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, size: 24),
                            SizedBox(width: 12),
                            Text('Camera', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ] else if (DailyPhotoTracker.hasPhotosToday) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _addAnotherDaily,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate, size: 24),
                            SizedBox(width: 12),
                            Text('Add another daily', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}