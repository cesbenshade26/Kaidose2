import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'MusicSearch.dart';
import 'ClipMusic.dart';
import 'StoryPhotoFrame.dart';

/// What the editor hands back.
class EditResult {
  /// The edited photo or video (edits are baked in).
  final File file;

  /// The song picked, if any. Only returned when the editor was opened with
  /// `withAudio: true` (Clips); for Dailies the song is just the sticker.
  final MusicTrack? music;

  /// True when the file is a full story-shaped picture (blurred background,
  /// the photo, and the text/drawing around it) rather than just the photo.
  final bool composite;

  const EditResult(this.file, {this.music, this.composite = false});
}

/// Full-screen editor for photos AND videos, used by Your Daily and Clips.
///
///   final r = await PhotoEditor.open(context, file, isVideo: false);
///   if (r != null) { use r.file instead of the original }
///
/// Tools: Crop (photos), Text (fonts, colors, bold/italic, alignment,
/// highlight box), Draw (pen, colors, thickness, undo) and Music (a "now
/// playing" song sticker). Everything is drawn into a transparent layer on
/// top of the media and baked in on Done: photos are re-saved as JPEG, videos
/// are re-encoded with the layer laid over them (ffmpeg), so no other screen
/// needs to know about edits. Returns null if nothing changed.
class PhotoEditor {
  static Future<EditResult?> open(
      BuildContext context,
      File file, {
        bool isVideo = false,
        bool withAudio = false,
        bool storyLayout = false,
        bool allowCrop = true,
      }) {
    return Navigator.of(context).push<EditResult>(
      PageRouteBuilder<EditResult>(
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _PhotoEditorScreen(
          file: file,
          isVideo: isVideo,
          withAudio: withAudio,
          storyLayout: storyLayout && !isVideo,
          allowCrop: allowCrop,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
                begin: const Offset(0, 0.04), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─── Look ───────────────────────────────────────────────────────────────────

const Color _accent = Colors.cyan;

const List<Color> _palette = [
  Color(0xFFFFFFFF),
  Color(0xFF111111),
  Color(0xFF26C6DA),
  Color(0xFFFFB300),
  Color(0xFFFF7043),
  Color(0xFFEF5350),
  Color(0xFFEC407A),
  Color(0xFF7E57C2),
  Color(0xFF42A5F5),
  Color(0xFF66BB6A),
];

const List<String> _fontLabels = [
  'Clean',
  'Serif',
  'Hand',
  'Tall',
  'Mono',
  'Kaidose',
];

TextStyle _fontStyle(
    int font, {
      required Color color,
      required double size,
      required bool bold,
      required bool italic,
      List<Shadow>? shadows,
    }) {
  final base = TextStyle(
    color: color,
    fontSize: size,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    height: 1.15,
    shadows: shadows,
  );
  switch (font) {
    case 1:
      return GoogleFonts.playfairDisplay(
          textStyle: base,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500);
    case 2:
      return GoogleFonts.caveat(
          textStyle: base.copyWith(fontSize: size * 1.3),
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500);
    case 3:
      return GoogleFonts.bebasNeue(
          textStyle: base.copyWith(fontSize: size * 1.2, letterSpacing: 1),
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    case 4:
      return GoogleFonts.spaceMono(
          textStyle: base,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    case 5:
      return base.copyWith(fontFamily: 'Slackey');
    default:
      return GoogleFonts.poppins(
          textStyle: base,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500);
  }
}

Color _contrast(Color c) =>
    c.computeLuminance() > 0.55 ? const Color(0xFF111111) : Colors.white;

// ─── Text ───

// ─── Items on the photo ─────────────────────────────────────────────────────

class _TextItem {
  final int id;
  String text;
  int font;
  Color color;
  Color? highlight; // null = just the text
  bool bold;
  bool italic;
  TextAlign align;
  Offset pos; // center, as a fraction of the canvas
  double scale;
  double rotation;
  MusicTrack? track; // non-null = this is the song sticker

  _TextItem({
    required this.id,
    this.text = '',
    this.font = 0,
    this.color = Colors.white,
    this.highlight,
    this.bold = true,
    this.italic = false,
    this.align = TextAlign.center,
    this.pos = const Offset(0.5, 0.5),
    this.scale = 1,
    this.rotation = 0,
    this.track,
  });

  bool get isMusic => track != null;

  _TextItem copy() => _TextItem(
    id: id,
    text: text,
    font: font,
    color: color,
    highlight: highlight,
    bold: bold,
    italic: italic,
    align: align,
    pos: pos,
    scale: scale,
    rotation: rotation,
    track: track,
  );
}

class _Stroke {
  final List<Offset> pts; // fractions of the canvas
  final Color color;
  final double width; // fraction of canvas width
  _Stroke(this.pts, this.color, this.width);
}

class _StrokesPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final int revision;
  _StrokesPainter(this.strokes, this.revision);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      Offset p(int i) => Offset(s.pts[i].dx * size.width, s.pts[i].dy * size.height);
      if (s.pts.length == 1) {
        canvas.drawCircle(p(0), paint.strokeWidth / 2,
            Paint()..color = s.color);
        continue;
      }
      final path = Path()..moveTo(p(0).dx, p(0).dy);
      for (var i = 1; i < s.pts.length - 1; i++) {
        final mid = Offset((p(i).dx + p(i + 1).dx) / 2, (p(i).dy + p(i + 1).dy) / 2);
        path.quadraticBezierTo(p(i).dx, p(i).dy, mid.dx, mid.dy);
      }
      path.lineTo(p(s.pts.length - 1).dx, p(s.pts.length - 1).dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokesPainter old) => true;
}

/// "Now playing" card: artwork, title and artist.
class _MusicSticker extends StatelessWidget {
  final MusicTrack track;
  final double fontSize;

  const _MusicSticker({required this.track, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final art = fontSize * 1.9;
    return Container(
      padding: EdgeInsets.all(fontSize * 0.4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(fontSize * 0.7),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(fontSize * 0.4),
            child: SizedBox(
              width: art,
              height: art,
              child: track.artworkUrl.isEmpty
                  ? Container(color: Colors.grey[300])
                  : Image.network(track.artworkUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: Colors.grey[300])),
            ),
          ),
          SizedBox(width: fontSize * 0.5),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: fontSize * 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.graphic_eq_rounded,
                        size: fontSize * 0.75, color: Colors.cyan[700]),
                    SizedBox(width: fontSize * 0.2),
                    Flexible(
                      child: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: fontSize * 0.72,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: fontSize * 0.6,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          SizedBox(width: fontSize * 0.25),
        ],
      ),
    );
  }
}

/// The text as it appears on the photo: plain, or inside a rounded box of the
/// highlight color that hugs it.
class _StyledText extends StatelessWidget {
  final _TextItem item;
  final double fontSize;

  const _StyledText({required this.item, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      item.text,
      textAlign: item.align,
      style: _fontStyle(
        item.font,
        color: item.color,
        size: fontSize,
        bold: item.bold,
        italic: item.italic,
        shadows: item.highlight == null
            ? const [Shadow(color: Color(0x40000000), blurRadius: 6)]
            : null,
      ),
    );
    if (item.highlight == null) return text;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: fontSize * 0.55, vertical: fontSize * 0.28),
      decoration: BoxDecoration(
        color: item.highlight,
        borderRadius: BorderRadius.circular(fontSize * 0.5),
      ),
      child: text,
    );
  }
}

// ─── The editor ─────────────────────────────────────────────────────────────

enum _Mode { normal, draw }

class _PhotoEditorScreen extends StatefulWidget {
  final File file;
  final bool isVideo;
  final bool withAudio;
  final bool storyLayout; // Daily photos: edit on the whole story screen
  final bool allowCrop;
  const _PhotoEditorScreen({
    required this.file,
    required this.isVideo,
    required this.withAudio,
    required this.storyLayout,
    required this.allowCrop,
  });

  @override
  State<_PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<_PhotoEditorScreen> {
  late File _current = widget.file;
  Size? _originalSize;
  Size? _imgSize; // size of _current
  Rect? _cropRect; // normalized, in the original
  VideoPlayerController? _video;

  final List<_TextItem> _items = [];
  final List<_Stroke> _strokes = [];
  int _nextId = 1;

  int? _activeId;
  double _baseScale = 1;
  double _baseRotation = 0;
  bool _overBin = false;

  _Mode _mode = _Mode.normal;
  Color _penColor = Colors.white;
  double _penWidth = 0.012; // fraction of canvas width
  _Stroke? _liveStroke;

  _TextItem? _editing;
  bool _editingIsNew = false;

  final GlobalKey _canvasKey = GlobalKey();
  final GlobalKey _overlayKey = GlobalKey();
  Size _canvasSize = Size.zero;
  bool _saving = false;
  bool _pickingMusic = false;
  String _savingLabel = '';

  bool get _changed =>
      _cropRect != null || _items.isNotEmpty || _strokes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _initVideo();
    } else {
      _readSize();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    try {
      final c = VideoPlayerController.file(widget.file);
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _video = c;
        _originalSize = c.value.size;
        _imgSize = c.value.size;
      });
    } catch (e) {
      print('PhotoEditor: could not open video: $e');
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _readSize() async {
    try {
      final bytes = await widget.file.readAsBytes();
      final img = await decodeImageFromList(bytes);
      final s = Size(img.width.toDouble(), img.height.toDouble());
      img.dispose();
      if (!mounted) return;
      setState(() {
        _originalSize = s;
        _imgSize = s;
      });
    } catch (e) {
      print('PhotoEditor: could not read image: $e');
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ─── Crop (photos) ────────────────────────────────────────────────────────

  Future<void> _openCrop() async {
    if (_originalSize == null || widget.isVideo) return;
    final rect = await Navigator.of(context).push<Rect>(
      PageRouteBuilder<Rect>(
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => _CropScreen(
          file: widget.file,
          imageSize: _originalSize!,
          initial: _cropRect,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (rect == null || !mounted) return;

    final isFull = rect.left <= 0.001 &&
        rect.top <= 0.001 &&
        rect.right >= 0.999 &&
        rect.bottom >= 0.999;
    if (isFull) {
      setState(() {
        _cropRect = null;
        _current = widget.file;
        _imgSize = _originalSize;
      });
      return;
    }

    setState(() {
      _saving = true;
      _savingLabel = '';
    });
    try {
      final result = await _applyCrop(rect);
      if (!mounted) return;
      setState(() {
        _cropRect = rect;
        _current = result.$1;
        _imgSize = result.$2;
      });
    } catch (e) {
      print('PhotoEditor: crop failed: $e');
      if (mounted) _toast("Couldn't crop this photo");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<(File, Size)> _applyCrop(Rect n) async {
    final bytes = await widget.file.readAsBytes();
    final src = await decodeImageFromList(bytes);
    final sw = src.width.toDouble();
    final sh = src.height.toDouble();
    final srcRect =
    Rect.fromLTWH(n.left * sw, n.top * sh, n.width * sw, n.height * sh);
    final k = math.min(1.0, 2048 / math.max(srcRect.width, srcRect.height));
    final dw = math.max(1, (srcRect.width * k).round());
    final dh = math.max(1, (srcRect.height * k).round());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      src,
      srcRect,
      Rect.fromLTWH(0, 0, dw.toDouble(), dh.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final out = await recorder.endRecording().toImage(dw, dh);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    src.dispose();
    out.dispose();
    final file = await _saveJpeg(data!.buffer.asUint8List());
    return (file, Size(dw.toDouble(), dh.toDouble()));
  }

  Future<File> _saveJpeg(Uint8List png) async {
    final jpg = await FlutterImageCompress.compressWithList(
      png,
      minWidth: 4096,
      minHeight: 4096,
      quality: 90,
      format: CompressFormat.jpeg,
    );
    final dir = await getTemporaryDirectory();
    final f = File(
        '${dir.path}/kaidose_edit_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await f.writeAsBytes(jpg);
    return f;
  }

  // ─── Text + music ─────────────────────────────────────────────────────────

  void _addText() {
    setState(() {
      _editing = _TextItem(id: _nextId++);
      _editingIsNew = true;
    });
  }

  Future<void> _pickMusic() async {
    setState(() => _pickingMusic = true);
    final track = await MusicPicker.show(context);
    if (mounted) setState(() => _pickingMusic = false);
    if (track == null || !mounted) return;
    setState(() {
      // One song per post: replace the old sticker.
      final existing = _items.indexWhere((e) => e.isMusic);
      if (existing >= 0) {
        _items[existing].track = track;
      } else {
        _items.add(_TextItem(
          id: _nextId++,
          track: track,
          pos: const Offset(0.5, 0.82),
        ));
      }
    });
  }

  void _editExisting(_TextItem item) {
    if (item.isMusic) {
      _pickMusic();
      return;
    }
    setState(() {
      _editing = item.copy();
      _editingIsNew = false;
    });
  }

  void _finishEditing(_TextItem result) {
    setState(() {
      final text = result.text.trim();
      if (_editingIsNew) {
        if (text.isNotEmpty) {
          result.text = text;
          _items.add(result);
        }
      } else {
        final i = _items.indexWhere((e) => e.id == result.id);
        if (i >= 0) {
          if (text.isEmpty) {
            _items.removeAt(i);
          } else {
            result.text = text;
            _items[i] = result;
          }
        }
      }
      _editing = null;
    });
  }

  bool _inBinZone(Offset global) {
    final mq = MediaQuery.of(context);
    return global.dy > mq.size.height - mq.padding.bottom - 170 &&
        (global.dx - mq.size.width / 2).abs() < 90;
  }

  void _onItemScaleStart(_TextItem item, ScaleStartDetails d) {
    setState(() {
      _activeId = item.id;
      _baseScale = item.scale;
      _baseRotation = item.rotation;
      _items.remove(item);
      _items.add(item);
    });
  }

  void _onItemScaleUpdate(_TextItem item, ScaleUpdateDetails d) {
    final w = _canvasSize.width, h = _canvasSize.height;
    if (w == 0 || h == 0) return;
    final over = _inBinZone(d.focalPoint);
    if (over && !_overBin) HapticFeedback.selectionClick();
    setState(() {
      item.pos = Offset(
        (item.pos.dx + d.focalPointDelta.dx / w).clamp(-0.1, 1.1),
        (item.pos.dy + d.focalPointDelta.dy / h).clamp(-0.1, 1.1),
      );
      item.scale = (_baseScale * d.scale).clamp(0.4, 5.0);
      item.rotation = _baseRotation + d.rotation;
      _overBin = over;
    });
  }

  void _onItemScaleEnd(_TextItem item, ScaleEndDetails d) {
    setState(() {
      if (_overBin) _items.removeWhere((e) => e.id == item.id);
      _activeId = null;
      _overBin = false;
    });
  }

  // ─── Drawing ──────────────────────────────────────────────────────────────

  Offset _frac(Offset local) => Offset(
    (local.dx / _canvasSize.width).clamp(0.0, 1.0),
    (local.dy / _canvasSize.height).clamp(0.0, 1.0),
  );

  void _drawStart(DragStartDetails d) {
    setState(() {
      _liveStroke = _Stroke([_frac(d.localPosition)], _penColor, _penWidth);
      _strokes.add(_liveStroke!);
    });
  }

  void _drawUpdate(DragUpdateDetails d) {
    final s = _liveStroke;
    if (s == null) return;
    setState(() => s.pts.add(_frac(d.localPosition)));
  }

  void _drawEnd() => setState(() => _liveStroke = null);

  void _drawTap(TapUpDetails d) {
    setState(() => _strokes
        .add(_Stroke([_frac(d.localPosition)], _penColor, _penWidth)));
  }

  // ─── Finish ───────────────────────────────────────────────────────────────

  MusicTrack? get _music {
    for (final i in _items) {
      if (i.isMusic) return i.track;
    }
    return null;
  }

  Future<void> _done() async {
    if (_saving) return;
    if (!_changed) {
      Navigator.of(context).pop();
      return;
    }
    final music = widget.withAudio ? _music : null;
    final hasOverlay = _items.isNotEmpty || _strokes.isNotEmpty;

    if (!widget.isVideo && !hasOverlay) {
      // Crop only: the cropped file is already the result.
      Navigator.of(context).pop(EditResult(_current));
      return;
    }

    setState(() {
      _saving = true;
      _savingLabel = widget.isVideo ? 'Saving video…' : '';
    });
    try {
      final File out =
      widget.isVideo ? await _exportVideo() : await _exportPhoto();
      if (mounted) {
        Navigator.of(context).pop(EditResult(out,
            music: music, composite: widget.storyLayout && !widget.isVideo));
      }
    } catch (e) {
      print('PhotoEditor: export failed: $e');
      if (mounted) {
        setState(() => _saving = false);
        _toast("Couldn't save your edits. Try again.");
      }
    }
  }

  Future<File> _exportPhoto() async {
    final boundary = _canvasKey.currentContext!.findRenderObject()
    as RenderRepaintBoundary;
    final cw = boundary.size.width, ch = boundary.size.height;
    final ratio = widget.storyLayout
        ? (1080 / cw).clamp(0.5, 4.0).toDouble()
        : math
        .min(_imgSize!.width / cw, 2048 / math.max(cw, ch))
        .clamp(0.5, 4.0)
        .toDouble();
    final img = await boundary.toImage(pixelRatio: ratio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return _saveJpeg(data!.buffer.asUint8List());
  }

  /// Renders the transparent overlay to a PNG, then lays it over the video
  /// with ffmpeg (the video's audio is copied untouched).
  Future<File> _exportVideo() async {
    await _video?.pause();

    final boundary = _overlayKey.currentContext!.findRenderObject()
    as RenderRepaintBoundary;
    final vw = _imgSize!.width, vh = _imgSize!.height;
    final ew = (vw / 2).floor() * 2, eh = (vh / 2).floor() * 2;
    final cw = boundary.size.width;
    final ratio = math.min(ew / cw, 3.0).clamp(0.5, 3.0).toDouble();
    final img = await boundary.toImage(pixelRatio: ratio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final overlay = File('${dir.path}/kaidose_overlay_$stamp.png');
    await overlay.writeAsBytes(data!.buffer.asUint8List());

    final encoders = <List<String>>[
      ['libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p'],
      if (Platform.isIOS) ['h264_videotoolbox', '-b:v', '6M'],
      if (Platform.isAndroid) ['h264_mediacodec', '-b:v', '6M'],
      ['mpeg4', '-q:v', '4'],
    ];

    final out = File('${dir.path}/kaidose_edit_$stamp.mp4');
    final filter = '[0:v]scale=$ew:$eh[b];[1:v]scale=$ew:$eh[o];'
        '[b][o]overlay=0:0:format=auto[v]';

    for (final enc in encoders) {
      if (await out.exists()) await out.delete();
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i', widget.file.path,
        '-i', overlay.path,
        '-filter_complex', filter,
        '-map', '[v]',
        '-map', '0:a?',
        '-c:v', ...enc,
        '-c:a', 'copy',
        '-movflags', '+faststart',
        out.path,
      ]);
      final code = await session.getReturnCode();
      if (ReturnCode.isSuccess(code) && await out.exists()) {
        overlay.delete().catchError((_) => overlay);
        return out;
      }
      print('PhotoEditor: ffmpeg failed with ${enc.first}');
    }
    throw Exception('video export failed');
  }

  Future<void> _close() async {
    if (_saving) return;
    if (!_changed) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard edits?'),
        content: const Text('Your changes will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
              const Text('Discard', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.black87,
      duration: const Duration(seconds: 2),
    ));
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final drawing = _mode == _Mode.draw;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _topBar(drawing),
                Expanded(child: _canvasArea(drawing)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: drawing ? _drawBar() : _bottomBar(),
                ),
              ],
            ),
          ),
          // The song plays while you edit (not while searching for another).
          ClipMusicPlayer(
            track: _music,
            active: !_pickingMusic && !_saving,
          ),
          _bin(),
          if (_editing != null)
            Positioned.fill(
              child: _TextEditLayer(
                key: ValueKey('edit-${_editing!.id}'),
                item: _editing!,
                onDone: _finishEditing,
                onCancel: () => setState(() => _editing = null),
              ),
            ),
          if (_saving)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                          color: _accent, strokeWidth: 2.5),
                      if (_savingLabel.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(_savingLabel,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _topBar(bool drawing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: drawing ? () => setState(() => _mode = _Mode.normal) : _close,
            icon: Icon(drawing ? Icons.arrow_back_ios_new_rounded : Icons.close,
                color: Colors.white, size: drawing ? 20 : 24),
          ),
          const Spacer(),
          GestureDetector(
            onTap: drawing ? () => setState(() => _mode = _Mode.normal) : _done,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(drawing ? 'Done drawing' : 'Done',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Padding(
      key: const ValueKey('tools'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!widget.isVideo && widget.allowCrop)
            _ToolButton(
                icon: Icons.crop_rounded, label: 'Crop', onTap: _openCrop),
          _ToolButton(
              icon: Icons.text_fields_rounded, label: 'Text', onTap: _addText),
          _ToolButton(
              icon: Icons.brush_rounded,
              label: 'Draw',
              onTap: () => setState(() => _mode = _Mode.draw)),
          _ToolButton(
              icon: Icons.music_note_rounded,
              label: 'Music',
              onTap: _pickMusic),
        ],
      ),
    );
  }

  Widget _drawBar() {
    return Padding(
      key: const ValueKey('draw'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _strokes.isEmpty
                    ? null
                    : () => setState(() => _strokes.removeLast()),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white12),
                  child: Icon(Icons.undo_rounded,
                      color: _strokes.isEmpty ? Colors.white24 : Colors.white,
                      size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _penWidth,
                    min: 0.004,
                    max: 0.04,
                    onChanged: (v) => setState(() => _penWidth = v),
                  ),
                ),
              ),
              // Size preview
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Container(
                    width: 6 + _penWidth * 400,
                    height: 6 + _penWidth * 400,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: _penColor),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _palette.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final c = _palette[i];
                final selected = _penColor.value == c.value;
                return GestureDetector(
                  onTap: () => setState(() => _penColor = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 34,
                    height: 34,
                    margin: EdgeInsets.all(selected ? 0 : 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.white38,
                        width: selected ? 3 : 1.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _base() {
    if (widget.isVideo) {
      final v = _video;
      if (v == null || !v.value.isInitialized) {
        return const ColoredBox(color: Colors.black);
      }
      return FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: v.value.size.width,
          height: v.value.size.height,
          child: VideoPlayer(v),
        ),
      );
    }
    if (widget.storyLayout) {
      return StoryPhotoFrame(
        file: _current,
        aspect: _imgSize == null ? null : _imgSize!.width / _imgSize!.height,
      );
    }
    return Image.file(
      _current,
      key: ValueKey(_current.path),
      fit: BoxFit.fill,
      gaplessPlayback: true,
    );
  }

  Widget _canvasArea(bool drawing) {
    final size = _imgSize;
    if (size == null) {
      return const Center(
        child: CircularProgressIndicator(color: _accent, strokeWidth: 2.5),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final availW = box.maxWidth - 24;
      final availH = box.maxHeight - 8;
      final aspect =
      widget.storyLayout ? kStoryAspect : size.width / size.height;
      double w = availW, h = availW / aspect;
      if (h > availH) {
        h = availH;
        w = availH * aspect;
      }
      _canvasSize = Size(w, h);
      final fontSize = w * 0.075;

      return Center(
        child: SizedBox(
          width: w,
          height: h,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: RepaintBoundary(
              key: _canvasKey,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(child: _base()),
                  // Everything the person adds lives in this transparent
                  // layer (it's what gets laid over a video).
                  Positioned.fill(
                    child: RepaintBoundary(
                      key: _overlayKey,
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter:
                              _StrokesPainter(_strokes, _strokes.length),
                            ),
                          ),
                          for (final item in _items)
                            if (!(_editing != null && _editing!.id == item.id))
                              _buildItem(item, w, h, fontSize, drawing),
                        ],
                      ),
                    ),
                  ),
                  if (drawing)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _drawStart,
                        onPanUpdate: _drawUpdate,
                        onPanEnd: (_) => _drawEnd(),
                        onPanCancel: _drawEnd,
                        onTapUp: _drawTap,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildItem(
      _TextItem item, double w, double h, double fontSize, bool drawing) {
    final content = item.isMusic
        ? _MusicSticker(track: item.track!, fontSize: fontSize)
        : ConstrainedBox(
      constraints: BoxConstraints(maxWidth: w * 0.86),
      child: _StyledText(item: item, fontSize: fontSize),
    );
    return Positioned(
      left: item.pos.dx * w,
      top: item.pos.dy * h,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: IgnorePointer(
          ignoring: drawing,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _editExisting(item),
            onScaleStart: (d) => _onItemScaleStart(item, d),
            onScaleUpdate: (d) => _onItemScaleUpdate(item, d),
            onScaleEnd: (d) => _onItemScaleEnd(item, d),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..rotateZ(item.rotation)
                ..scale(item.scale),
              child: Opacity(
                opacity: (_activeId == item.id && _overBin) ? 0.5 : 1,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The bin appears while something is being dragged.
  Widget _bin() {
    final show = _activeId != null;
    final bottom = MediaQuery.of(context).padding.bottom + 36;
    return Positioned(
      bottom: bottom,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: show ? 1 : 0,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: _overBin ? 64 : 52,
              height: _overBin ? 64 : 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _overBin ? Colors.red : Colors.white24,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                  color: Colors.white12, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Text editing layer ─────────────────────────────────────────────────────

class _TextEditLayer extends StatefulWidget {
  final _TextItem item;
  final ValueChanged<_TextItem> onDone;
  final VoidCallback onCancel;

  const _TextEditLayer({
    Key? key,
    required this.item,
    required this.onDone,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<_TextEditLayer> createState() => _TextEditLayerState();
}

class _TextEditLayerState extends State<_TextEditLayer> {
  late _TextItem _it = widget.item.copy();
  late final TextEditingController _controller =
  TextEditingController(text: _it.text);
  final FocusNode _focus = FocusNode();
  bool _colorsForHighlight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => _it.text = _controller.text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _pickColor(Color? c) {
    setState(() {
      if (_colorsForHighlight) {
        _it.highlight = c;
        // Keep the text readable on the box.
        if (c != null && _it.color.value == c.value) _it.color = _contrast(c);
      } else {
        _it.color = c ?? Colors.white;
      }
    });
  }

  void _cycleAlign() {
    setState(() {
      _it.align = _it.align == TextAlign.center
          ? TextAlign.left
          : (_it.align == TextAlign.left ? TextAlign.right : TextAlign.center);
    });
  }

  IconData get _alignIcon => _it.align == TextAlign.left
      ? Icons.format_align_left_rounded
      : (_it.align == TextAlign.right
      ? Icons.format_align_right_rounded
      : Icons.format_align_center_rounded);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = math.max(mq.viewInsets.bottom, mq.padding.bottom);
    const fs = 30.0;

    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: false,
      maxLines: null,
      maxLength: 160,
      textAlign: _it.align,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: _it.highlight != null ? _contrast(_it.highlight!) : Colors.white,
      style: _fontStyle(_it.font,
          color: _it.color, size: fs, bold: _it.bold, italic: _it.italic),
      decoration: const InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        counterText: '',
      ),
    );

    final preview = _it.highlight == null
        ? field
        : Container(
      padding: const EdgeInsets.symmetric(
          horizontal: fs * 0.55, vertical: fs * 0.28),
      decoration: BoxDecoration(
        color: _it.highlight,
        borderRadius: BorderRadius.circular(fs * 0.5),
      ),
      child: field,
    );

    final colors = <Color?>[
      if (_colorsForHighlight) null,
      ..._palette,
    ];

    return Material(
      color: Colors.black.withOpacity(0.84),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.white70, fontSize: 15)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => widget.onDone(_it),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 9),
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Done',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: mq.size.width * 0.86, minWidth: 60),
                      child: IntrinsicWidth(child: preview),
                    ),
                  ),
                ),
              ),
              // Style row: bold, italic, align, then which color is being set.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    _StyleToggle(
                      icon: Icons.format_bold_rounded,
                      active: _it.bold,
                      onTap: () => setState(() => _it.bold = !_it.bold),
                    ),
                    const SizedBox(width: 8),
                    _StyleToggle(
                      icon: Icons.format_italic_rounded,
                      active: _it.italic,
                      onTap: () => setState(() => _it.italic = !_it.italic),
                    ),
                    const SizedBox(width: 8),
                    _StyleToggle(
                      icon: _alignIcon,
                      active: false,
                      onTap: _cycleAlign,
                    ),
                    const Spacer(),
                    _Segmented(
                      left: 'Text',
                      right: 'Highlight',
                      rightSelected: _colorsForHighlight,
                      onChanged: (v) =>
                          setState(() => _colorsForHighlight = v),
                    ),
                  ],
                ),
              ),
              // Colors
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: colors.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final c = colors[i];
                    final selected = _colorsForHighlight
                        ? (c == null
                        ? _it.highlight == null
                        : _it.highlight?.value == c.value)
                        : (c != null && _it.color.value == c.value);
                    return GestureDetector(
                      onTap: () => _pickColor(c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 34,
                        height: 34,
                        margin: EdgeInsets.all(selected ? 0 : 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c ?? Colors.transparent,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.white38,
                            width: selected ? 3 : 1.5,
                          ),
                        ),
                        child: c == null
                            ? const Icon(Icons.block_rounded,
                            color: Colors.white70, size: 18)
                            : null,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Fonts
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _fontLabels.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final selected = _it.font == i;
                    return GestureDetector(
                      onTap: () => setState(() => _it.font = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : Colors.white12,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(
                          _fontLabels[i],
                          style: _fontStyle(
                            i,
                            color: selected ? Colors.black : Colors.white,
                            size: 16,
                            bold: false,
                            italic: false,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleToggle extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _StyleToggle(
      {required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.white : Colors.white12,
        ),
        child: Icon(icon, size: 22, color: active ? Colors.black : Colors.white),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final String left;
  final String right;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;

  const _Segmented({
    required this.left,
    required this.right,
    required this.rightSelected,
    required this.onChanged,
  });

  Widget _seg(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.black : Colors.white70)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(left, !rightSelected, () => onChanged(false)),
          _seg(right, rightSelected, () => onChanged(true)),
        ],
      ),
    );
  }
}

// ─── Crop ───────────────────────────────────────────────────────────────────

enum _Grab { none, move, tl, tr, bl, br, left, right, top, bottom }

class _CropScreen extends StatefulWidget {
  final File file;
  final Size imageSize;
  final Rect? initial;

  const _CropScreen({
    required this.file,
    required this.imageSize,
    this.initial,
  });

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  static const double _handle = 32;
  static const double _minPx = 70;

  // null = free, otherwise width / height of the box in image pixels.
  double? _ratio;
  late Rect _n = widget.initial ?? const Rect.fromLTRB(0, 0, 1, 1);

  Rect _imgRect = Rect.zero; // where the image sits on screen
  _Grab _grab = _Grab.none;

  Rect get _px => Rect.fromLTRB(
    _imgRect.left + _n.left * _imgRect.width,
    _imgRect.top + _n.top * _imgRect.height,
    _imgRect.left + _n.right * _imgRect.width,
    _imgRect.top + _n.bottom * _imgRect.height,
  );

  void _setPx(Rect r) {
    if (_imgRect.width == 0) return;
    setState(() {
      _n = Rect.fromLTRB(
        ((r.left - _imgRect.left) / _imgRect.width).clamp(0.0, 1.0),
        ((r.top - _imgRect.top) / _imgRect.height).clamp(0.0, 1.0),
        ((r.right - _imgRect.left) / _imgRect.width).clamp(0.0, 1.0),
        ((r.bottom - _imgRect.top) / _imgRect.height).clamp(0.0, 1.0),
      );
    });
  }

  void _preset(double? ratio) {
    setState(() {
      _ratio = ratio;
      if (ratio == null) return;
      final iw = widget.imageSize.width, ih = widget.imageSize.height;
      var nw = 1.0;
      var nh = iw / (ratio * ih);
      if (nh > 1) {
        nh = 1;
        nw = ratio * ih / iw;
      }
      _n = Rect.fromLTWH((1 - nw) / 2, (1 - nh) / 2, nw, nh);
    });
  }

  void _reset() {
    setState(() {
      _ratio = null;
      _n = const Rect.fromLTRB(0, 0, 1, 1);
    });
  }

  _Grab _hit(Offset p) {
    final r = _px;
    bool near(Offset a) => (p - a).distance < _handle;
    if (near(r.topLeft)) return _Grab.tl;
    if (near(r.topRight)) return _Grab.tr;
    if (near(r.bottomLeft)) return _Grab.bl;
    if (near(r.bottomRight)) return _Grab.br;
    if (_ratio == null) {
      const e = 22.0;
      final inX = p.dx > r.left + e && p.dx < r.right - e;
      final inY = p.dy > r.top + e && p.dy < r.bottom - e;
      if ((p.dx - r.left).abs() < e && p.dy > r.top && p.dy < r.bottom) {
        return _Grab.left;
      }
      if ((p.dx - r.right).abs() < e && p.dy > r.top && p.dy < r.bottom) {
        return _Grab.right;
      }
      if ((p.dy - r.top).abs() < e && p.dx > r.left && p.dx < r.right) {
        return _Grab.top;
      }
      if ((p.dy - r.bottom).abs() < e && p.dx > r.left && p.dx < r.right) {
        return _Grab.bottom;
      }
      if (inX && inY) return _Grab.move;
    }
    return r.contains(p) ? _Grab.move : _Grab.none;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_grab == _Grab.none) return;
    final r = _px;
    final b = _imgRect;
    final delta = d.delta;

    if (_grab == _Grab.move) {
      var dx = delta.dx, dy = delta.dy;
      dx = dx.clamp(b.left - r.left, b.right - r.right);
      dy = dy.clamp(b.top - r.top, b.bottom - r.bottom);
      _setPx(r.shift(Offset(dx, dy)));
      return;
    }

    final isCorner = _grab == _Grab.tl ||
        _grab == _Grab.tr ||
        _grab == _Grab.bl ||
        _grab == _Grab.br;

    if (isCorner) {
      final fixed = switch (_grab) {
        _Grab.tl => r.bottomRight,
        _Grab.tr => r.bottomLeft,
        _Grab.bl => r.topRight,
        _ => r.topLeft,
      };
      final moving = switch (_grab) {
        _Grab.tl => r.topLeft,
        _Grab.tr => r.topRight,
        _Grab.bl => r.bottomLeft,
        _ => r.bottomRight,
      };
      var p = moving + delta;
      p = Offset(p.dx.clamp(b.left, b.right), p.dy.clamp(b.top, b.bottom));
      final dirX = moving.dx < fixed.dx ? -1.0 : 1.0;
      final dirY = moving.dy < fixed.dy ? -1.0 : 1.0;

      if (_ratio != null) {
        final k = _ratio!;
        final maxW = dirX > 0 ? b.right - fixed.dx : fixed.dx - b.left;
        final maxH = dirY > 0 ? b.bottom - fixed.dy : fixed.dy - b.top;
        var w = (p.dx - fixed.dx).abs();
        w = math.min(w, math.min(maxW, maxH * k));
        w = math.max(w, math.min(_minPx, math.min(maxW, maxH * k)));
        final h = w / k;
        _setPx(Rect.fromPoints(
            fixed, Offset(fixed.dx + dirX * w, fixed.dy + dirY * h)));
      } else {
        var x = p.dx, y = p.dy;
        if ((x - fixed.dx).abs() < _minPx) {
          x = (fixed.dx + dirX * _minPx).clamp(b.left, b.right);
        }
        if ((y - fixed.dy).abs() < _minPx) {
          y = (fixed.dy + dirY * _minPx).clamp(b.top, b.bottom);
        }
        _setPx(Rect.fromPoints(fixed, Offset(x, y)));
      }
      return;
    }

    // Edges (free mode only)
    var l = r.left, t = r.top, rt = r.right, bt = r.bottom;
    switch (_grab) {
      case _Grab.left:
        l = (l + delta.dx).clamp(b.left, rt - _minPx);
        break;
      case _Grab.right:
        rt = (rt + delta.dx).clamp(l + _minPx, b.right);
        break;
      case _Grab.top:
        t = (t + delta.dy).clamp(b.top, bt - _minPx);
        break;
      case _Grab.bottom:
        bt = (bt + delta.dy).clamp(t + _minPx, b.bottom);
        break;
      default:
        break;
    }
    _setPx(Rect.fromLTRB(l, t, rt, bt));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white70, fontSize: 15)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _reset,
                    child: const Text('Reset',
                        style: TextStyle(color: Colors.white70, fontSize: 15)),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(_n),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 9),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Done',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                const pad = 20.0;
                final aw = box.maxWidth - pad * 2;
                final ah = box.maxHeight - pad * 2;
                final aspect = widget.imageSize.width / widget.imageSize.height;
                var w = aw, h = aw / aspect;
                if (h > ah) {
                  h = ah;
                  w = ah * aspect;
                }
                _imgRect = Rect.fromLTWH(
                    (box.maxWidth - w) / 2, (box.maxHeight - h) / 2, w, h);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => _grab = _hit(d.localPosition),
                  onPanUpdate: _onUpdate,
                  onPanEnd: (_) => _grab = _Grab.none,
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: _imgRect,
                        child: Image.file(
                          widget.file,
                          fit: BoxFit.fill,
                          cacheWidth: 1600,
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _CropPainter(_imgRect, _px),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _chip('Free', _ratio == null, () => _preset(null)),
                  _chip('Screen', _ratio == 3 / 4, () => _preset(3 / 4)),
                  _chip('Square', _ratio == 1, () => _preset(1)),
                  _chip('Wide', _ratio == 16 / 9, () => _preset(16 / 9)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.black : Colors.white70)),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final Rect image;
  final Rect crop;
  _CropPainter(this.image, this.crop);

  @override
  void paint(Canvas canvas, Size size) {
    // Dim everything outside the box.
    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(image),
      Path()..addRect(crop),
    );
    canvas.drawPath(dim, Paint()..color = Colors.black.withOpacity(0.6));

    // Thirds grid
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), grid);
    }

    // Border
    canvas.drawRect(
      crop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withOpacity(0.9),
    );

    // Corner brackets
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    const l = 20.0;
    void corner(Offset c, double sx, double sy) {
      canvas.drawLine(c, c + Offset(sx * l, 0), p);
      canvas.drawLine(c, c + Offset(0, sy * l), p);
    }

    corner(crop.topLeft, 1, 1);
    corner(crop.topRight, -1, 1);
    corner(crop.bottomLeft, 1, -1);
    corner(crop.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.crop != crop;
}