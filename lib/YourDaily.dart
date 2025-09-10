import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'CamRoll.dart';
import 'dart:io';
import 'DailyPhotoManager.dart';

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

class _YourDailyWidgetState extends State<YourDailyWidget> {
  File? _selectedPhoto; // Mirror ProfilePic's approach

  Future<void> _openCameraRoll() async {
    print("Opening camera roll...");
    final XFile? pickedFile = await CamRoll.openCameraRoll(context);
    if (pickedFile != null) {
      print('Camera roll image selected: ${pickedFile.path}');
      final File imageFile = File(pickedFile.path);
      print('File exists: ${imageFile.existsSync()}');

      setState(() {
        _selectedPhoto = imageFile;
      });
      print('Selected photo set in state: ${_selectedPhoto?.path}');
      print('File still exists after setState: ${_selectedPhoto?.existsSync()}');
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
      print('File exists: ${imageFile.existsSync()}');

      setState(() {
        _selectedPhoto = imageFile;
      });
      print('Selected photo set in state: ${_selectedPhoto?.path}');
      print('File still exists after setState: ${_selectedPhoto?.existsSync()}');
    } else {
      print('No image captured from camera');
    }
  }

  Future<void> _confirmPhoto() async {
    print('========== CONFIRM PHOTO DEBUG ==========');
    print('_selectedPhoto: ${_selectedPhoto?.path ?? "NULL"}');
    print('_selectedPhoto exists: ${_selectedPhoto?.existsSync() ?? false}');

    if (_selectedPhoto != null && _selectedPhoto!.existsSync()) {
      print('Valid photo found, proceeding with save...');
      print('Photo path: ${_selectedPhoto!.path}');
      print('Photo size: ${_selectedPhoto!.lengthSync()} bytes');

      try {
        // Save the photo using DailyPhotoManager (using the new listener system like ProfilePicManager)
        await DailyPhotoManager.setDailyPhoto(_selectedPhoto!);

        print('DailyPhotoManager.setDailyPhoto completed');

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Daily photo saved!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }

        // Clear the preview
        setState(() {
          _selectedPhoto = null;
        });

        print('Daily photo confirmed and saved successfully');
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

  @override
  Widget build(BuildContext context) {
    print('YourDaily build - Selected photo: ${_selectedPhoto?.path ?? "null"}');

    return Column(
      children: [
        // Preview area
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _selectedPhoto != null && _selectedPhoto!.existsSync()
                      ? Image.file(
                    _selectedPhoto!,
                    fit: BoxFit.cover,
                    key: ValueKey(_selectedPhoto!.path),
                    errorBuilder: (context, error, stackTrace) {
                      print('Error loading preview image: $error');
                      return Container(
                        color: Colors.grey[200],
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Error loading image',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
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
                          Icon(
                            Icons.photo_size_select_actual_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Photo Preview',
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
              ),
            ),
          ),
        ),

        // Confirm button - ALWAYS HERE
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _confirmPhoto,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Confirm Photo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),

        // Bottom buttons
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _openCameraRoll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}