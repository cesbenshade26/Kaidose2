import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'MusicSearch.dart';

/// Invisible widget that plays a clip's song (its 30-second preview, looped)
/// while the clip is the one on screen, and stops when it isn't. Put it
/// anywhere in the clip page's Stack. The clip's own audio is muted by the
/// page when a song is attached.
class ClipMusicPlayer extends StatefulWidget {
  final MusicTrack? track;
  final bool active;

  const ClipMusicPlayer({Key? key, required this.track, required this.active})
      : super(key: key);

  @override
  State<ClipMusicPlayer> createState() => _ClipMusicPlayerState();
}

class _ClipMusicPlayerState extends State<ClipMusicPlayer> {
  AudioPlayer? _player;
  bool _playing = false;
  String? _playingUrl;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ClipMusicPlayer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  Future<void> _sync() async {
    final t = widget.track;
    final want = t != null && t.previewUrl.isNotEmpty && widget.active;
    try {
      if (want && (!_playing || _playingUrl != t.previewUrl)) {
        _playing = true;
        _playingUrl = t.previewUrl;
        _player ??= AudioPlayer();
        await _player!.setReleaseMode(ReleaseMode.loop);
        await _player!.play(UrlSource(t.previewUrl));
      } else if (!want && _playing) {
        _playing = false;
        _playingUrl = null;
        await _player?.pause();
      }
    } catch (e) {
      print('ClipMusicPlayer: $e');
      _playing = false;
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}