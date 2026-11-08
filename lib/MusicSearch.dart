import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// A song attached to a photo, Daily or Clip: just the details needed to
/// show "who / what" and (for Clips) play the 30-second preview.
class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String artworkUrl;
  final String previewUrl;
  final String trackUrl;

  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUrl,
    required this.previewUrl,
    this.trackUrl = '',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artworkUrl': artworkUrl,
    'previewUrl': previewUrl,
    'trackUrl': trackUrl,
  };

  static MusicTrack? fromMap(dynamic m) {
    if (m is! Map) return null;
    final title = m['title'];
    if (title is! String || title.isEmpty) return null;
    return MusicTrack(
      id: '${m['id'] ?? ''}',
      title: title,
      artist: '${m['artist'] ?? ''}',
      artworkUrl: '${m['artworkUrl'] ?? ''}',
      previewUrl: '${m['previewUrl'] ?? ''}',
      trackUrl: '${m['trackUrl'] ?? ''}',
    );
  }
}

/// Song search through Apple's free iTunes Search API (no key needed).
class MusicSearchService {
  static Future<List<MusicTrack>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': q,
      'media': 'music',
      'entity': 'song',
      'limit': '25',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('search failed');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final out = <MusicTrack>[];
    for (final r in (data['results'] as List? ?? const [])) {
      if (r is! Map) continue;
      final name = r['trackName'];
      if (name is! String) continue;
      out.add(MusicTrack(
        id: '${r['trackId']}',
        title: name,
        artist: '${r['artistName'] ?? ''}',
        artworkUrl: ('${r['artworkUrl100'] ?? ''}')
            .replaceAll('100x100', '300x300'),
        previewUrl: '${r['previewUrl'] ?? ''}',
        trackUrl: '${r['trackViewUrl'] ?? ''}',
      ));
    }
    return out;
  }
}

/// Bottom sheet for picking a song. Returns the chosen [MusicTrack].
class MusicPicker {
  static Future<MusicTrack?> show(BuildContext context) {
    return showModalBottomSheet<MusicTrack>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MusicPickerSheet(),
    );
  }
}

class _MusicPickerSheet extends StatefulWidget {
  const _MusicPickerSheet();

  @override
  State<_MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends State<_MusicPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _player = AudioPlayer();
  Timer? _debounce;
  int _searchId = 0;

  List<MusicTrack> _results = [];
  bool _loading = false;
  bool _error = false;
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _player.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
        _error = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(text));
  }

  Future<void> _search(String text) async {
    final id = ++_searchId;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final r = await MusicSearchService.search(text);
      if (!mounted || id != _searchId) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _searchId) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _togglePreview(MusicTrack t) async {
    if (_playingId == t.id) {
      await _player.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    if (t.previewUrl.isEmpty) return;
    setState(() => _playingId = t.id);
    try {
      await _player.stop();
      await _player.play(UrlSource(t.previewUrl));
    } catch (_) {
      if (mounted) setState(() => _playingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: const BoxDecoration(
          color: Color(0xFF161616),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: Colors.cyan,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search songs or artists',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon:
                  const Icon(Icons.search_rounded, color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white10,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.cyan, strokeWidth: 2.5),
      );
    }
    if (_error) {
      return const Center(
        child: Text("Couldn't search right now",
            style: TextStyle(color: Colors.white54)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _controller.text.trim().isEmpty
              ? 'Search for a song to add'
              : 'No songs found',
          style: const TextStyle(color: Colors.white38, fontSize: 15),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final t = _results[i];
        final playing = _playingId == t.id;
        return InkWell(
          onTap: () => Navigator.of(context).pop(t),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: t.artworkUrl.isEmpty
                        ? Container(color: Colors.white12)
                        : Image.network(t.artworkUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: Colors.white12)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                ),
                if (t.previewUrl.isNotEmpty)
                  GestureDetector(
                    onTap: () => _togglePreview(t),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: playing ? Colors.cyan : Colors.white12,
                      ),
                      child: Icon(
                        playing
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}