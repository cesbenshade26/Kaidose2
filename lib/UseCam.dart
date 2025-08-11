import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

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
        preferredCameraDevice: CameraDevice.rear, // Use rear camera by default
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

      // Show user-friendly error message
      String errorMessage = 'Unable to access camera';
      if (e.toString().contains('camera_access_denied')) {
        errorMessage = 'Camera access denied. Please enable camera permission in settings.';
      } else if (e.toString().contains('no_available_camera')) {
        errorMessage = 'No camera available on this device.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
      return null;
    }
  }
}