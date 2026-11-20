import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'AppColors.dart';
import 'package:flutter/rendering.dart';
import 'BackgroundPicManager.dart';
import 'ProfilePicManager.dart';
import 'UnifiedMediaPicker.dart';
import 'DrawPad.dart';

/// Which banner someone shows when they have no background photo: the soft
/// sky-blue fade ([sky], the original) or plain white ([plain]). Saved on
/// the user doc as `bannerStyle` so other people see the same thing.
class BannerStyle {
  BannerStyle._();

  static const String sky = 'sky';
  static const String plain = 'plain';

  /// Your own choice; Profile and the background screen listen to it.
  static final ValueNotifier<String> mine = ValueNotifier<String>(sky);
  static String? _loadedFor;

  // Bumped on every set(): a load that started before a tap must not put
  // the old choice back when its answer arrives late.
  static int _changes = 0;

  static String parse(dynamic value) => value == plain ? plain : sky;

  static String _key(String uid) => 'bannerStyle_$uid';

  /// Your saved choice: instantly from this phone, then from your account.
  static Future<void> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_loadedFor != uid) {
      _loadedFor = uid;
      mine.value = sky;
      try {
        final prefs = await SharedPreferences.getInstance();
        mine.value = parse(prefs.getString(_key(uid)));
      } catch (_) {}
    }
    final startedAt = _changes;
    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final value = parse(doc.data()?['bannerStyle']);
      if (FirebaseAuth.instance.currentUser?.uid != uid) return;
      if (_changes != startedAt) return; // you picked something meanwhile
      mine.value = value;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(uid), value);
    } catch (_) {}
  }

  static Future<void> set(String style) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final value = parse(style);
    _changes++;
    mine.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(uid), value);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'bannerStyle': value}, SetOptions(merge: true));
    } catch (e) {
      print('BannerStyle: save failed: $e');
    }
  }
}

/// The background you just picked or removed in this session, shown on
/// Profile right away.
///
/// BackgroundPicManager saves the photo (to the phone and your account) on
/// its own schedule and doesn't always tell Profile when it's done, so the
/// new banner used to appear only after a reload. This hands Profile the
/// freshly cropped file (a new file name every time, so no stale cached
/// picture) the moment you tap "Use this photo".
class BannerPhoto {
  BannerPhoto._();

  /// Bumps whenever the banner photo is picked or removed.
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static File? _picked;
  static bool _removed = false;
  static String? _for;

  static bool get _sameUser =>
      _for != null && _for == FirebaseAuth.instance.currentUser?.uid;

  /// What Profile should show instead of the saved photo: the fresh crop,
  /// "none" after removing, or [saved] when nothing changed this session.
  static File? resolve(File? saved) {
    if (!_sameUser) return saved;
    if (_removed) return null;
    return _picked ?? saved;
  }

  static void picked(File file) {
    _for = FirebaseAuth.instance.currentUser?.uid;
    _picked = file;
    _removed = false;
    changed.value++;
  }

  static void removed() {
    _for = FirebaseAuth.instance.currentUser?.uid;
    _picked = null;
    _removed = true;
    changed.value++;
  }
}

/// Shared look of the profile banner so Profile, the selector and the crop
/// screen always agree.
class BackgroundSpec {
  static const double bannerHeight = 130.0;
  static const double avatarSize = 100.0;

  /// Soft cyan -> white, shown when no photo is set.
  static const BoxDecoration defaultDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF4DD0E1), Color(0xFFE0F7FA), Colors.white],
      stops: [0.0, 0.7, 1.0],
    ),
  );

  /// True when the banner is just the page color (no photo, plain style):
  /// icons on it need to be dark, and it gets no shadow at the top.
  static bool isPlain({required bool hasPhoto, String? style}) =>
      !hasPhoto && (style ?? BannerStyle.mine.value) == BannerStyle.plain;

  /// The default banner (no photo) for someone's [style] (yours when not
  /// given), in the current light/dark mode. Plain is just the page color;
  /// sky is the soft cyan fade, which in dark mode fades into the dark page.
  static BoxDecoration defaultDecorationFor(BuildContext context,
      {String? style}) {
    if ((style ?? BannerStyle.mine.value) == BannerStyle.plain) {
      return BoxDecoration(color: context.colors.background);
    }
    if (!context.isDark) return defaultDecoration;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00838F),
          const Color(0xFF123438),
          context.colors.background,
        ],
        stops: const [0.0, 0.7, 1.0],
      ),
    );
  }

  /// Light dark scrim at the top so status bar / icons stay readable.
  static const BoxDecoration scrimDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x59000000), Color(0x00000000)],
    ),
  );
}

// ---------------------------------------------------------------------------
// Crop screen: choose which part of the photo becomes the banner.
// ---------------------------------------------------------------------------
class BackgroundPicEditor extends StatefulWidget {
  final File imageFile;
  final Function(File) onImageCropped;

  const BackgroundPicEditor({
    Key? key,
    required this.imageFile,
    required this.onImageCropped,
  }) : super(key: key);

  @override
  State<BackgroundPicEditor> createState() => _BackgroundPicEditorState();
}

class _BackgroundPicEditorState extends State<BackgroundPicEditor> {
  final GlobalKey _cropKey = GlobalKey();
  Size? _imageSize;
  double _scale = 1.0; // user zoom on top of "cover"
  Offset _offset = Offset.zero; // image center relative to frame center
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  bool _saving = false;
  File? _profilePic;

  @override
  void initState() {
    super.initState();
    _profilePic = ProfilePicManager.globalProfilePic;
    final stream = FileImage(widget.imageFile).resolve(const ImageConfiguration());
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _imageSize =
            Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
      stream.removeListener(l);
    }, onError: (_, __) {
      if (mounted) Navigator.pop(context);
    });
    stream.addListener(l);
  }

  double _base(Size frame) =>
      (frame.width / _imageSize!.width) > (frame.height / _imageSize!.height)
          ? frame.width / _imageSize!.width
          : frame.height / _imageSize!.height;

  Offset _clamp(Offset o, Size frame) {
    final disp = _imageSize! * (_base(frame) * _scale);
    final maxX = ((disp.width - frame.width) / 2).clamp(0.0, double.infinity);
    final maxY = ((disp.height - frame.height) / 2).clamp(0.0, double.infinity);
    return Offset(o.dx.clamp(-maxX, maxX), o.dy.clamp(-maxY, maxY));
  }

  Future<void> _save(Size frame) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
      _cropKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1200 / frame.width);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
          '${Directory.systemTemp.path}/cropped_background_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data!.buffer.asUint8List());
      widget.onImageCropped(file);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not crop that photo. Try another.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // Same size the banner has on the profile (full width x bannerHeight).
    final frame = Size(width, BackgroundSpec.bannerHeight);
    const avatar = BackgroundSpec.avatarSize;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.colors.text),
        title: Text('Position photo',
            style: TextStyle(color: context.colors.text, fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: true,
      ),
      body: _imageSize == null
          ? Center(child: CircularProgressIndicator(color: kc.adapt(const Color(0xFFB0B5BC))))
          : Column(
        children: [
          const SizedBox(height: 24),
          // Exactly what the profile will show.
          SizedBox(
            width: frame.width,
            height: frame.height + avatar / 2 + 8,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onScaleStart: (d) {
                    _startScale = _scale;
                    _startOffset = _offset;
                    _startFocal = d.focalPoint;
                  },
                  onScaleUpdate: (d) {
                    setState(() {
                      _scale = (_startScale * d.scale).clamp(1.0, 4.0);
                      _offset = _clamp(
                          _startOffset + (d.focalPoint - _startFocal), frame);
                    });
                  },
                  child: RepaintBoundary(
                    key: _cropKey,
                    child: SizedBox(
                      width: frame.width,
                      height: frame.height,
                      child: ClipRect(
                        child: Stack(
                          children: [
                            Positioned(
                              left: frame.width / 2 -
                                  (_imageSize!.width * _base(frame) * _scale) / 2 +
                                  _offset.dx,
                              top: frame.height / 2 -
                                  (_imageSize!.height * _base(frame) * _scale) / 2 +
                                  _offset.dy,
                              width: _imageSize!.width * _base(frame) * _scale,
                              height: _imageSize!.height * _base(frame) * _scale,
                              child: Image.file(widget.imageFile, fit: BoxFit.fill),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Preview-only overlays (not part of the saved crop).
                IgnorePointer(
                  child: Container(
                    width: frame.width,
                    height: frame.height,
                    decoration: BackgroundSpec.scrimDecoration,
                  ),
                ),
                Positioned(
                  top: frame.height - avatar / 2,
                  left: (frame.width - avatar) / 2,
                  child: IgnorePointer(
                    child: Container(
                      width: avatar,
                      height: avatar,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.colors.border,
                      ),
                      child: ClipOval(
                        child: _profilePic != null && _profilePic!.existsSync()
                            ? Image.file(_profilePic!, fit: BoxFit.cover)
                            : const DefaultProfilePic(size: avatar, borderWidth: 0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('Drag to move, pinch to zoom',
              style: TextStyle(color: context.colors.textMuted, fontSize: 14)),
          const SizedBox(height: 4),
          Text('This is how it will look on your profile',
              style: TextStyle(color: context.colors.textFaint, fontSize: 12)),
          const Spacer(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : () => _save(frame),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                    foregroundColor: Colors.white,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Text('Use this photo',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selector screen: live preview on top, inline photo picker below.
// ---------------------------------------------------------------------------
class BackgroundPicScreen extends StatefulWidget {
  final Function(File?)? onBackgroundPicChanged;

  const BackgroundPicScreen({Key? key, this.onBackgroundPicChanged}) : super(key: key);

  @override
  State<BackgroundPicScreen> createState() => _BackgroundPicScreenState();
}

class _BackgroundPicScreenState extends State<BackgroundPicScreen> {
  File? _selectedImage;
  File? _profilePic;
  VoidCallback? _listener;

  @override
  void initState() {
    super.initState();
    _selectedImage = BackgroundPicManager.globalBackgroundPic;
    _profilePic = ProfilePicManager.globalProfilePic;
    BannerStyle.mine.addListener(_onStyle);
    BannerStyle.load();
    _listener = () {
      if (mounted) setState(() => _selectedImage = BackgroundPicManager.globalBackgroundPic);
    };
    BackgroundPicManager.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) BackgroundPicManager.removeListener(_listener!);
    BannerStyle.mine.removeListener(_onStyle);
    super.dispose();
  }

  void _onStyle() {
    if (mounted) setState(() {});
  }

  /// With no photo: pick the soft blue fade or plain white.
  Widget _styleChoice() {
    Widget option(String style, String label) {
      final selected = BannerStyle.mine.value == style;
      final plainStyle = style == BannerStyle.plain;
      return Expanded(
        child: GestureDetector(
          onTap: () => BannerStyle.set(style),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? Colors.cyan : context.colors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(selected ? 10 : 11),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                          decoration: BackgroundSpec.defaultDecorationFor(
                              context,
                              style: style)),
                      if (selected)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.cyan,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: plainStyle || selected
                      ? context.colors.text
                      : context.colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          option(BannerStyle.sky, 'Sky'),
          const SizedBox(width: 12),
          option(BannerStyle.plain, 'Plain'),
        ],
      ),
    );
  }

  /// Crop screen. "Use this photo" saves it (BackgroundPicManager uploads
  /// it to your account) and brings you straight back out, the same as
  /// Instagram, with a quick confirmation.
  Future<void> _openEditor(File file) async {
    var used = false;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BackgroundPicEditor(
          imageFile: file,
          onImageCropped: (cropped) {
            used = true;
            // Same file path can come back from the cache: drop the old one.
            FileImage(cropped).evict();
            BackgroundPicManager.globalBackgroundPic = cropped;
            BannerPhoto.picked(cropped);
            widget.onBackgroundPicChanged?.call(cropped);
          },
        ),
      ),
    );
    if (!used || !mounted) return;
    setState(() => _selectedImage = BackgroundPicManager.globalBackgroundPic);
    _done(message: 'Background updated');
  }

  /// Leave the screen (the choice is already saved).
  void _done({String? message}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.maybePop(context);
    if (message != null) {
      messenger?.showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _openDrawingPad() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrawingScreen(
          onDrawingComplete: (File drawing) {
            Navigator.pop(context); // close the drawing pad
            _openEditor(drawing);
          },
        ),
      ),
    );
  }

  void _removeBackground() {
    BackgroundPicManager.globalBackgroundPic = null;
    BannerPhoto.removed();
    setState(() => _selectedImage = null);
    widget.onBackgroundPicChanged?.call(null);
  }

  bool get _plain => BackgroundSpec.isPlain(
      hasPhoto: _selectedImage != null && _selectedImage!.existsSync());

  Widget _preview() {
    const h = BackgroundSpec.bannerHeight;
    const a = BackgroundSpec.avatarSize;
    final hasPic = _selectedImage != null && _selectedImage!.existsSync();

    return SizedBox(
      width: double.infinity,
      height: h + a / 2 + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: h,
            child: hasPic
                ? Image.file(
              _selectedImage!,
              fit: BoxFit.cover,
              key: ValueKey(
                  _selectedImage!.path + _selectedImage!.lastModifiedSync().toString()),
              errorBuilder: (_, __, ___) =>
                  Container(decoration: BackgroundSpec.defaultDecorationFor(context)),
            )
                : Container(decoration: BackgroundSpec.defaultDecorationFor(context)),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: h,
            child: IgnorePointer(
                child: BackgroundSpec.isPlain(hasPhoto: hasPic)
                    ? const SizedBox.shrink()
                    : Container(decoration: BackgroundSpec.scrimDecoration)),
          ),
          Positioned(
            top: h - a / 2,
            left: (MediaQuery.of(context).size.width - a) / 2,
            child: Container(
              width: a,
              height: a,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.border,
              ),
              child: ClipOval(
                child: _profilePic != null && _profilePic!.existsSync()
                    ? Image.file(_profilePic!, fit: BoxFit.cover)
                    : const DefaultProfilePic(size: a, borderWidth: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPic = _selectedImage != null;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Column(
        children: [
          _preview(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Choose a photo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                if (hasPic)
                  TextButton(
                    onPressed: _removeBackground,
                    style: TextButton.styleFrom(foregroundColor: context.colors.textMuted),
                    child: const Text('Remove'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                hasPic
                    ? 'Pick a new photo to replace your background.'
                    : 'Optional. Without a photo, choose a default:',
                style: TextStyle(color: context.colors.textMuted, fontSize: 13),
              ),
            ),
          ),
          if (!hasPic) _styleChoice(),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => UnifiedMediaPickerPanel(
                height: c.maxHeight,
                title: 'Photos',
                initialFilter: MediaFilter.photos,
                allowFilterToggle: false,
                singleSelect: true,
                showDraw: true,
                onDrawTap: _openDrawingPad,
                onClose: () => Navigator.pop(context),
                onMediaSelected: (items) {
                  if (items.isEmpty) return;
                  _openEditor(items.first.file);
                },
              ),
            ),
          ),
        ],
      ),
      // Back button floats over the banner.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // Dark back arrow on a plain white banner, white over a photo or
        // the blue fade.
        iconTheme: IconThemeData(
          color: _plain ? context.colors.text : Colors.white,
        ),
        // Everything here saves as you choose it; Done just closes.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: () => _done(),
              style: TextButton.styleFrom(
                backgroundColor: _plain
                    ? kc.adapt(const Color(0xFFF1F3F5))
                    : Colors.black.withOpacity(0.35),
                foregroundColor: _plain ? context.colors.text : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text('Done',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}