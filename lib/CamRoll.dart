import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
// import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class CamRoll {
  static final ImagePicker _picker = ImagePicker();

  /*
  static Future<bool> _checkAndRequestPermission() async {
    // Check and request camera permission only when called
    try {
      PermissionStatus status = await Permission.camera.status;

      if (status.isGranted) {
        return true;
      } else if (status.isPermanentlyDenied) {
        return false; // Handle this in the calling function
      } else {
        // For any other status, request permission
        PermissionStatus newStatus = await Permission.camera.request();

        if (newStatus.isGranted) {
          return true;
        } else if (newStatus.isPermanentlyDenied) {
          return false; // Handle this in the calling function
        }
        return false;
      }
    } catch (e) {
      // On simulator, permission might not be needed or might fail
      // Let's assume we have permission and try anyway
      print('Camera permission check failed (likely simulator): $e');
      return true;
    }
  }

  static void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission Required'),
          content: const Text('Please enable camera access in Settings to take a photo.'),
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

  static Future<XFile?> openCameraRoll(BuildContext context) async {
    print("Photos button tapped!");

    /*
    // Check permission when the button is tapped
    bool hasPermission = await _checkAndRequestPermission();

    if (!hasPermission) {
      print('No permission to access camera');
      _showSettingsDialog(context);
      return null;
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
        print('Selected image path: ${image.path}');
        return image;
      } else {
        print('No image selected - user cancelled');
        return null;
      }
    } catch (e) {
      print('Error selecting image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accessing photos: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }
}