import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ClipMusic.dart';
import 'MusicSearch.dart';
import 'StoryMediaItem.dart';

/// Remembers which song goes with which of YOUR posted Dailies, so it plays
/// when you open them again. Matched by the file's contents (not its path),
/// so it still works after the app copies the file around. Friends get the
/// song from the post itself (see FriendDailyService).
class StoryMusic {
  static const String _key = 'story_music_v1';
  static const int _max = 200;

  static Future<String?> _fingerprint(File f) async {
    try {
      final len = await f.length();
      final raf = await f.open();
      try {
        final head = await raf.read(4096);
        var tail = <int>[];
        if (len > 8192) {
          await raf.setPosition(len - 4096);
          tail = await raf.read(4096);
        }
        var h = 17;
        for (final b in head) {
          h = (h * 31 + b) & 0x7fffffff;
        }
        for (final b in tail) {
          h = (h * 31 + b) & 0x7fffffff;
        }
        return '$len-$h';
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _load(SharedPreferences p) async {
    try {
      final raw = p.getString(_key);
      if (raw == null) return {};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static Future<void> remember(File file, MusicTrack track) async {
    try {
      final fp = await _fingerprint(file);
      if (fp == null) return;
      final p = await SharedPreferences.getInstance();
      final map = await _load(p);
      map.remove(fp);
      map[fp] = track.toMap();
      while (map.length > _max) {
        map.remove(map.keys.first);
      }
      await p.setString(_key, jsonEncode(map));
    } catch (e) {
      print('StoryMusic: remember failed: $e');
    }
  }

  static Future<MusicTrack?> lookup(File file) async {
    try {
      final fp = await _fingerprint(file);
      if (fp == null) return null;
      final p = await SharedPreferences.getInstance();
      final map = await _load(p);
      return MusicTrack.fromMap(map[fp]);
    } catch (_) {
      return null;
    }
  }
}

/// Plays the song for a story item while it's on screen. Drop it into a
/// story viewer's Stack, keyed to the item being shown.
class StoryMusicLayer extends StatefulWidget {
  final StoryMediaItem item;
  const StoryMusicLayer({Key? key, required this.item}) : super(key: key);

  @override
  State<StoryMusicLayer> createState() => _StoryMusicLayerState();
}

class _StoryMusicLayerState extends State<StoryMusicLayer> {
  MusicTrack? _track;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(StoryMusicLayer old) {
    super.didUpdateWidget(old);
    if (old.item.file.path != widget.item.file.path) {
      _track = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final item = widget.item;
    final t = item.music ?? await StoryMusic.lookup(item.file);
    if (mounted && item == widget.item) setState(() => _track = t);
  }

  @override
  Widget build(BuildContext context) =>
      ClipMusicPlayer(track: _track, active: true);
}