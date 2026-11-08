import 'dart:async';
import 'dart:collection';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:video_player/video_player.dart';

/// Keeps videos and photos ready BEFORE they're needed, so a clip shows (or
/// plays) the instant someone scrolls to it.
///
/// VIDEOS: a controller here is already initialised (the video's header is
/// read and its first seconds are buffered), looping, paused and sitting at
/// the start. Nothing is downloaded beyond that first buffer, so it's cheap.
///
/// PHOTOS: the image is downloaded and decoded ahead of time into Flutter's
/// image cache (and saved on disk), so it appears with no loading. Show it
/// with `Image(image: PreloadedMediaPool.imageProvider(url))` and it's found
/// instantly.
///
/// Two things keep controllers alive:
///  * a scroll WINDOW: [preloadAround] keeps the clip being watched, the next
///    few below it and one above ready, and drops the rest as you scroll.
///    Any scrolling video feed uses this (your own clips now, the Clips feed
///    next).
///  * PROTECTED clips: [setProtected] keeps a small fixed set ready no matter
///    what (your pinned clips, so they open instantly from your profile).
///
/// A screen that shows a video BORROWS its controller with [lease] and gives
/// it back with [release]. The pool owns every controller and is the only
/// thing that disposes one, and never while it's borrowed.
class PreloadedMediaPool {
  static final PreloadedMediaPool instance = PreloadedMediaPool._();
  PreloadedMediaPool._();

  /// The one image provider to use for a preloaded photo, so the warmed copy
  /// is the one that gets shown.
  static ImageProvider imageProvider(String url) =>
      CachedNetworkImageProvider(url);

  final Set<String> _warmedImages = {};

  final Map<String, _Entry> _entries = {};
  Set<String> _protected = {};
  Set<String> _window = {};
  int _generation = 0;

  /// Returns the video's controller (initialised, paused, looping, at the
  /// start), using one that was warmed up earlier if there is one. Null if
  /// the video couldn't be loaded. Call [release] when the screen is done.
  Future<VideoPlayerController?> lease(String id, String url) {
    final entry = _ensure(id, url);
    entry.inUse = true;
    return entry.future;
  }

  /// Gives a borrowed controller back. It's kept if it's still wanted (in the
  /// window or protected), otherwise disposed.
  void release(String id) {
    final entry = _entries[id];
    if (entry == null) return;
    entry.inUse = false;

    // If it's being kept, rewind it for the next time it's shown. Done here
    // (awaited, errors swallowed) so it can never touch a disposed controller.
    if (_protected.contains(id) || _window.contains(id)) {
      entry.future.then((c) async {
        if (c == null || entry.inUse || _entries[id] != entry) return;
        try {
          await c.pause();
          if (entry.inUse || _entries[id] != entry) return;
          await c.seekTo(Duration.zero);
        } catch (_) {}
      });
    }
    _sweep();
  }

  /// Downloads photos ahead of time so they show instantly.
  Future<void> warmImages(Iterable<String> urls) async {
    for (final u in urls) {
      await _warmImage(u);
    }
  }

  /// Keeps a fixed set of videos ready (id -> url), replacing the previous
  /// set, and warms the given photo urls. Use for things that should always
  /// open instantly.
  void setProtected(Map<String, String> videos,
      {Iterable<String> images = const []}) {
    _protected = videos.keys.toSet();
    for (final e in videos.entries) {
      if (e.value.isEmpty) continue;
      _ensure(e.key, e.value);
    }
    for (final url in images) {
      _warmImage(url);
    }
    _sweep();
  }

  /// For a vertically scrolling list of videos and photos: keeps the one at
  /// [index], the next [ahead] below it and [behind] above it ready, and lets
  /// go of the rest. Call it when the screen opens and every time the page
  /// changes. Items with an empty url are skipped. [isImage] says which items
  /// are photos (everything else is a video).
  ///
  /// The clip being watched is prepared first, then the ones below it in
  /// order, so the next one is always ready first.
  void preloadAround<T>(
      List<T> items,
      int index, {
        required String Function(T item) id,
        required String Function(T item) url,
        bool Function(T item)? isImage,
        List<String> Function(T item)? photos,
        int ahead = 3,
        int behind = 1,
      }) {
    final order = <int>[
      index,
      for (var i = 1; i <= ahead; i++) index + i,
      for (var i = 1; i <= behind; i++) index - i,
    ];

    // id -> url, in the order they should be prepared; photos are tracked
    // separately because they have no controller to keep.
    final wanted = LinkedHashMap<String, String>();
    final photoIds = <String>{};
    // The rest of the current clip's photos (a multi-photo clip), warmed
    // after the first photos of the clips below it.
    var morePhotos = <String>[];
    for (final i in order) {
      if (i < 0 || i >= items.length) continue;
      final u = url(items[i]);
      if (u.isEmpty) continue;
      final key = id(items[i]);
      wanted[key] = u;
      if (isImage != null && isImage(items[i])) {
        photoIds.add(key);
        if (i == index && photos != null) {
          morePhotos = photos(items[i]).where((p) => p != u).toList();
        }
      }
    }

    _window = wanted.keys.where((k) => !photoIds.contains(k)).toSet();
    _sweep();

    // One at a time, in order, so the next clip finishes before the one
    // after it. Stops if the window moves on.
    final generation = ++_generation;
    () async {
      for (final e in wanted.entries) {
        if (generation != _generation) return;
        if (photoIds.contains(e.key)) {
          await _warmImage(e.value);
        } else {
          await _ensure(e.key, e.value).future;
        }
      }
      for (final u in morePhotos) {
        if (generation != _generation) return;
        await _warmImage(u);
      }
    }();
  }

  /// Done scrolling (the screen closed): stops keeping the window ready.
  void clearWindow() {
    _generation++;
    _window = {};
    _sweep();
  }

  /// Drops everything that isn't borrowed (e.g. on logout).
  void clear() {
    _generation++;
    _protected = {};
    _window = {};
    _sweep();
  }

  // -------------------------------------------------------------------------

  /// Downloads and decodes a photo into the image cache. Completes when it's
  /// ready (or failed); does nothing if it's already been warmed.
  Future<void> _warmImage(String url) {
    if (url.isEmpty || !_warmedImages.add(url)) return Future.value();

    final done = Completer<void>();
    final stream = imageProvider(url).resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
          (info, _) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete();
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        _warmedImages.remove(url); // try again next time
        if (!done.isCompleted) done.complete();
      },
    );
    stream.addListener(listener);
    return done.future;
  }

  _Entry _ensure(String id, String url) {
    final existing = _entries[id];
    if (existing != null && existing.url == url) return existing;
    if (existing != null) _drop(id); // same clip, new url

    final entry = _Entry(id, url);
    _entries[id] = entry;
    entry.future = _open(entry);
    return entry;
  }

  Future<VideoPlayerController?> _open(_Entry entry) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.networkUrl(Uri.parse(entry.url));
      await controller.initialize();
      await controller.setLooping(true);

      // Let go of it if it was dropped while it was loading.
      if (_entries[entry.id] != entry) {
        await controller.dispose();
        return null;
      }
      return controller;
    } catch (e) {
      print('PreloadedMediaPool: could not load ${entry.id}: $e');
      if (_entries[entry.id] == entry) _entries.remove(entry.id);
      try {
        await controller?.dispose();
      } catch (_) {}
      return null;
    }
  }

  void _drop(String id) {
    final entry = _entries.remove(id);
    entry?.future.then((c) async {
      try {
        await c?.dispose();
      } catch (_) {}
    });
  }

  void _sweep() {
    final keep = {..._protected, ..._window};
    final drop = _entries.values
        .where((e) => !e.inUse && !keep.contains(e.id))
        .map((e) => e.id)
        .toList();
    for (final id in drop) {
      _drop(id);
    }
  }
}

class _Entry {
  final String id;
  final String url;
  bool inUse = false;
  late Future<VideoPlayerController?> future;

  _Entry(this.id, this.url);
}