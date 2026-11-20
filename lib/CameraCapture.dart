import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'AppColors.dart';
import 'UnifiedMediaPicker.dart' show PickedMedia;

/// The one way Kaidose opens the phone's camera.
///
/// Every screen that can take a photo or film a video goes through here, so
/// they all look and behave the same and handle a missing camera or denied
/// permission the same way. What happens with the result is up to the
/// screen (preview box, editor, pending strip of a chat...).
///
///   final shot = await CameraCapture.capture(context);            // photo or video
///   final pic  = await CameraCapture.takePhoto(context, selfie: true); // photo only
///
/// Both return a [PickedMedia] (the same thing the library picker returns),
/// or null if the person backed out.
class CameraCapture {
  CameraCapture._();

  static final ImagePicker _picker = ImagePicker();

  /// Stops a double tap from opening the camera twice.
  static bool _busy = false;

  /// Asks "Take a photo / Record a video", then opens the camera.
  /// With [allowVideo] false it goes straight to taking a photo.
  static Future<PickedMedia?> capture(
      BuildContext context, {
        bool allowVideo = true,
        Duration maxVideoLength = const Duration(seconds: 60),
        bool selfie = false,
      }) async {
    FocusScope.of(context).unfocus();
    if (!allowVideo) return takePhoto(context, selfie: selfie);

    final video = await _chooseMode(context);
    if (video == null || !context.mounted) return null;
    return video
        ? recordVideo(context, maxLength: maxVideoLength, selfie: selfie)
        : takePhoto(context, selfie: selfie);
  }

  /// Opens the camera for a photo.
  static Future<PickedMedia?> takePhoto(BuildContext context,
      {bool selfie = false}) {
    return _run(
      context,
      isVideo: false,
      open: () => _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 88,
        preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
      ),
    );
  }

  /// Opens the camera for a video. Recording stops at [maxLength].
  static Future<PickedMedia?> recordVideo(
      BuildContext context, {
        Duration maxLength = const Duration(seconds: 60),
        bool selfie = false,
      }) {
    return _run(
      context,
      isVideo: true,
      open: () => _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: maxLength,
        preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
      ),
    );
  }

  static Future<PickedMedia?> _run(
      BuildContext context, {
        required bool isVideo,
        required Future<XFile?> Function() open,
      }) async {
    if (_busy) return null;
    _busy = true;
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final shot = await open();
      if (shot == null) return null; // backed out
      return PickedMedia(file: File(shot.path), isVideo: isVideo);
    } on PlatformException catch (e) {
      print('CameraCapture: ${e.code} / ${e.message}');
      _tell(messenger, _messageFor(e.code, isVideo));
      return null;
    } catch (e) {
      print('CameraCapture: $e');
      _tell(messenger, "Couldn't open the camera. Try again.");
      return null;
    } finally {
      _busy = false;
    }
  }

  static String _messageFor(String code, bool isVideo) {
    final c = code.toLowerCase();
    if (c.contains('microphone')) {
      return 'Kaidose needs microphone access to film. '
          "Turn it on in your phone's Settings.";
    }
    if (c.contains('denied') || c.contains('access')) {
      return 'Kaidose needs camera access. '
          "Turn it on in your phone's Settings.";
    }
    if (c.contains('no_available_camera') || c.contains('camera_unavailable')) {
      return "This device doesn't have a camera.";
    }
    return isVideo
        ? "Couldn't record a video. Try again."
        : "Couldn't take a photo. Try again.";
  }

  static void _tell(ScaffoldMessengerState? messenger, String text) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 3),
      ));
  }

  /// true = video, false = photo, null = closed.
  static Future<bool?> _chooseMode(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = ctx.colors;
        Widget option(IconData icon, String label, bool video) {
          return ListTile(
            leading: Icon(icon, color: colors.text),
            title: Text(label,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colors.text)),
            onTap: () => Navigator.pop(ctx, video),
          );
        }

        return Material(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                option(Icons.photo_camera_outlined, 'Take a photo', false),
                option(Icons.videocam_outlined, 'Record a video', true),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }
}