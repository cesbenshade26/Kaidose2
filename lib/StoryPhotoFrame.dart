import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Shape of a posted Daily (width / height).
const double kStoryAspect = 9 / 16;

/// How a Daily photo looks when it's posted: a blurred, darkened copy fills
/// the screen and the photo sits on top, full width with rounded corners.
/// The editor and the Add screen both use this so what you see is what you
/// post. Pass [aspect] (width / height) if you know it, otherwise it's read
/// from the file.
class StoryPhotoFrame extends StatefulWidget {
  final File file;
  final double? aspect;

  const StoryPhotoFrame({Key? key, required this.file, this.aspect})
      : super(key: key);

  @override
  State<StoryPhotoFrame> createState() => _StoryPhotoFrameState();
}

class _StoryPhotoFrameState extends State<StoryPhotoFrame> {
  double? _aspect;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _aspect = widget.aspect;
    if (_aspect == null) _resolve();
  }

  @override
  void didUpdateWidget(StoryPhotoFrame old) {
    super.didUpdateWidget(old);
    if (widget.aspect != null) {
      _aspect = widget.aspect;
    } else if (old.file.path != widget.file.path) {
      _aspect = null;
      _resolve();
    }
  }

  void _resolve() {
    _detach();
    final stream = FileImage(widget.file).resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _aspect = info.image.width / info.image.height);
      }
      _detach();
    }, onError: (_, __) => _detach());
    _stream = stream;
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final a = _aspect;
      // A picture that's already story-shaped (edited in the Daily editor)
      // carries its own background, so it's shown as-is: no second
      // backdrop, padding or rounded corners on top of it.
      final composite = a != null && (a - kStoryAspect).abs() < 0.006;
      final pad = composite ? 0.0 : w * 0.03;
      double pw = w - pad * 2, ph = 0;
      if (a != null) {
        ph = pw / a;
        if (ph > h - pad * 2) {
          ph = h - pad * 2;
          pw = ph * a;
        }
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
                sigmaX: 30, sigmaY: 30, tileMode: TileMode.clamp),
            child: Image.file(widget.file,
                fit: BoxFit.cover,
                width: w,
                height: h,
                cacheWidth: 200,
                errorBuilder: (_, __, ___) => Container(color: Colors.black)),
          ),
          Container(color: Colors.black.withOpacity(0.35)),
          // Until the photo's shape is known (or if it can't be read), still
          // show the photo itself so this is never an empty black screen.
          if (a == null)
            Padding(
              padding: EdgeInsets.all(w * 0.03),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(w * 0.045),
                  child: Image.file(
                    widget.file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 48),
                  ),
                ),
              ),
            ),
          if (a != null)
            Center(
              child: SizedBox(
                width: pw,
                height: ph,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(composite ? 0 : w * 0.045),
                  child: Image.file(
                    widget.file,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 44),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}