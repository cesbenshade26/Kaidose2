import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

/// Works out the shape (width / height) of a photo or video in a Daily
/// message so cards can size themselves to it, and remembers it for the
/// rest of the session.
///
/// Photos: read from the image itself (shares Flutter's image cache and
/// the disk cache the cards use, so nothing is downloaded twice). Videos: from the still frame saved with
/// newer posts; older videos without one are opened briefly just to read
/// their size.
class MediaAspect {
  MediaAspect._();

  static final Map<String, double> _cache = {};
  static final Map<String, Future<double?>> _pending = {};

  static bool _remote(String p) =>
      p.startsWith('http://') || p.startsWith('https://');

  /// Already known (no waiting), or null.
  static double? known(String path) => _cache[path];

  static Future<double?> of(String path,
      {required bool isVideo, String? thumb}) {
    final hit = _cache[path];
    if (hit != null) return Future.value(hit);
    return _pending[path] ??= _resolve(path, isVideo, thumb).then((a) {
      _pending.remove(path);
      if (a != null && a.isFinite && a > 0) _cache[path] = a;
      return a;
    });
  }

  static Future<double?> _resolve(
      String path, bool isVideo, String? thumb) async {
    try {
      if (!isVideo) {
        return _imageAspect(_remote(path) ? CachedNetworkImageProvider(path) : FileImage(File(path)));
      }
      if (thumb != null && thumb.isNotEmpty) {
        final a = await _imageAspect(_remote(thumb)
            ? CachedNetworkImageProvider(thumb)
            : FileImage(File(thumb)) as ImageProvider);
        if (a != null) return a;
      }
      final c = _remote(path)
          ? VideoPlayerController.networkUrl(Uri.parse(path))
          : VideoPlayerController.file(File(path));
      try {
        await c.initialize().timeout(const Duration(seconds: 10));
        final s = c.value.size;
        return s.height > 0 ? s.width / s.height : null;
      } finally {
        c.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<double?> _imageAspect(ImageProvider provider) {
    final done = Completer<double?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!done.isCompleted) {
        done.complete(info.image.width / info.image.height);
      }
      stream.removeListener(listener);
    }, onError: (_, __) {
      if (!done.isCompleted) done.complete(null);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return done.future.timeout(const Duration(seconds: 15), onTimeout: () {
      stream.removeListener(listener);
      return null;
    });
  }

  /// The box a piece of media should take: as wide as allowed, but a tall
  /// one gets narrower instead of taller than [maxH]. Never narrower than
  /// [minW] (it's cropped a touch at that point).
  static Size box(double? aspect,
      {required double maxW, required double maxH, double minW = 0}) {
    final a = (aspect == null || aspect <= 0) ? 4 / 5 : aspect;
    var w = maxW;
    var h = w / a;
    if (h > maxH) {
      h = maxH;
      w = h * a;
    }
    if (w < minW) w = minW;
    return Size(w, h);
  }
}

/// Builds [builder] with the media's shape: right away if it's already
/// known, otherwise once it's worked out (null until then).
class MediaAspectBuilder extends StatefulWidget {
  final String path;
  final bool isVideo;
  final String? thumb;
  final Widget Function(BuildContext context, double? aspect) builder;

  const MediaAspectBuilder({
    Key? key,
    required this.path,
    required this.isVideo,
    this.thumb,
    required this.builder,
  }) : super(key: key);

  @override
  State<MediaAspectBuilder> createState() => _MediaAspectBuilderState();
}

class _MediaAspectBuilderState extends State<MediaAspectBuilder> {
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MediaAspectBuilder old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  void _load() {
    _aspect = MediaAspect.known(widget.path);
    if (_aspect != null) return;
    final path = widget.path;
    MediaAspect.of(path, isVideo: widget.isVideo, thumb: widget.thumb)
        .then((a) {
      if (mounted && path == widget.path && a != null) {
        setState(() => _aspect = a);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _aspect);
}

/// Your own just-posted photos/videos: once uploaded, a message's paths
/// change from the file on your phone to a download URL. Showing the
/// local file for those (while it's still on the phone) means no
/// re-download, no spinner and no flicker when that happens.
class LocalMediaAlias {
  LocalMediaAlias._();

  static final Map<String, String> _byUrl = {};
  static final Map<String, bool> _exists = {};

  static void remember(String url, String localPath) {
    if (url == localPath) return;
    _byUrl[url] = localPath;
    final a = MediaAspect.known(localPath);
    if (a != null) MediaAspect._cache[url] = a;
  }

  /// The local file for [path] if we have one, otherwise [path] itself.
  static String resolve(String path) {
    final local = _byUrl[path];
    if (local == null) return path;
    final ok = _exists[local] ??= File(local).existsSync();
    return ok ? local : path;
  }
}

/// Starts downloading a photo into the same caches the Daily cards and
/// messages use (memory + disk via CachedNetworkImageProvider), so it shows
/// instantly when it comes on screen, now and after the app restarts.
void precacheNetworkImage(String url) {
  if (!url.startsWith('http')) return;
  final stream = CachedNetworkImageProvider(url).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
        (_, __) => stream.removeListener(listener),
    onError: (_, __) => stream.removeListener(listener),
  );
  stream.addListener(listener);
}