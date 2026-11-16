import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'clip_service.dart';
import 'DailyPhotoManager.dart';
import 'DailyPhotoTracker.dart';
import 'DailyVideoTracker.dart';
import 'FriendDailyService.dart';
import 'MusicSearch.dart';
import 'PhotoEditor.dart';
import 'StoryMusic.dart';

/// One photo or video of a Daily message: a download URL, or a local path
/// while it's still uploading.
class MyDailyMedia {
  final String path;
  final bool isVideo;
  const MyDailyMedia(this.path, this.isVideo);
}

/// "Add to My Daily": turns a clip or a Daily message into a post on your
/// own Daily (your story). It opens straight in the Your Daily editor so
/// you can add text, drawings or a song; "Post" puts it up.
///
///  * Video (clip or message) -> posted as a story video.
///  * Photo with no text      -> the photo, like any Daily photo.
///  * Text, or photo + text   -> a clean message card (the sender's name
///                               and picture, the photo, the text) on a
///                               blurred or soft gradient background.
///
/// Posts from a Daily remember which one; a public Daily shows a small
/// "From ___" tag on the story that opens it.
class AddToMyDaily {
  AddToMyDaily._();

  // ─── Entry points ─────────────────────────────────────────────────────────

  static Future<void> fromClip(BuildContext context, String clipId) async {
    final ready = await _withSpinner<_Prepared?>(context, () async {
      final doc = await FirebaseFirestore.instance
          .collection('clips')
          .doc(clipId)
          .get();
      if (!doc.exists) return null;
      final clip = ClipData.fromFirestore(doc.data()!, doc.id);
      if (clip.isPhoto) {
        if (clip.allPhotos.isEmpty) return null;
        final f = await _fetch(clip.allPhotos.first, 'jpg');
        return f == null
            ? null
            : _Prepared(f, isVideo: false, kind: _Kind.photo, music: clip.music);
      }
      if (clip.videoUrl.isEmpty) return null;
      final f = await _fetch(clip.videoUrl, 'mp4');
      return f == null
          ? null
          : _Prepared(f, isVideo: true, kind: _Kind.video, music: clip.music);
    });
    if (!context.mounted) return;
    await _editAndPost(context, ready);
  }

  static Future<void> fromDailyMessage(
      BuildContext context, {
        required String text,
        required List<MyDailyMedia> media,
        required String authorUid,
        required String authorName,
        required String dailyId,
        required String dailyTitle,
        required bool isPrivate,
      }) async {
    final source = <String, dynamic>{
      'dailyId': dailyId,
      'dailyTitle': isPrivate ? '' : dailyTitle,
      'private': isPrivate,
    };
    final trimmed = text.trim();
    final video = media.where((m) => m.isVideo).toList();
    final photos = media.where((m) => !m.isVideo).toList();

    final ready = await _withSpinner<_Prepared?>(context, () async {
      // A video wins: it posts as a video (add words in the editor).
      if (video.isNotEmpty && photos.isEmpty) {
        final f = await _fetch(video.first.path, 'mp4');
        return f == null
            ? null
            : _Prepared(f, isVideo: true, kind: _Kind.video, source: source);
      }
      File? photo;
      if (photos.isNotEmpty) photo = await _fetch(photos.first.path, 'jpg');
      if (photo != null && trimmed.isEmpty) {
        return _Prepared(photo, isVideo: false, kind: _Kind.photo, source: source);
      }
      if (photo == null && trimmed.isEmpty) {
        // Only a video we couldn't get, or nothing at all.
        if (video.isNotEmpty) {
          final f = await _fetch(video.first.path, 'mp4');
          if (f != null) {
            return _Prepared(f, isVideo: true, kind: _Kind.video, source: source);
          }
        }
        return null;
      }
      final card = await _renderCard(
        text: trimmed,
        photo: photo,
        authorUid: authorUid,
        authorName: authorName,
      );
      return card == null
          ? null
          : _Prepared(card, isVideo: false, kind: _Kind.card, source: source);
    });
    if (!context.mounted) return;
    await _editAndPost(context, ready);
  }

  // ─── Editor + post ────────────────────────────────────────────────────────

  static Future<void> _editAndPost(BuildContext context, _Prepared? p) async {
    final messenger = ScaffoldMessenger.of(context);
    if (p == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't load this. Try again in a moment."),
        duration: Duration(seconds: 2),
      ));
      return;
    }

    final result = await PhotoEditor.open(
      context,
      p.file,
      isVideo: p.isVideo,
      withAudio: true,
      storyLayout: p.kind == _Kind.photo,
      allowCrop: p.kind == _Kind.photo,
      composite: p.kind == _Kind.card,
      doneLabel: 'Post',
      returnUnchanged: true,
    );
    if (result == null) return; // closed with X

    final file = result.file;
    final music = result.music ?? p.music;
    messenger.showSnackBar(const SnackBar(
      content: Text('Adding to your Daily…'),
      duration: Duration(seconds: 1),
    ));

    try {
      if (p.isVideo) {
        await DailyVideoTracker.addVideo(file);
      } else {
        await DailyPhotoTracker.addPhoto(file);
        await DailyPhotoManager.setDailyPhoto(file);
      }
      if (music != null) await StoryMusic.remember(file, music);
      if (p.source != null) await StorySource.remember(file, p.source!);

      if (p.isVideo) {
        await FriendDailyService.uploadMyDailyVideo(file,
            music: music, source: p.source);
      } else {
        await FriendDailyService.uploadMyDailyPhoto(file,
            music: music, source: p.source);
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
        content: Text('Added to your Daily'),
        backgroundColor: Colors.black87,
        duration: Duration(seconds: 2),
      ));
    } catch (e) {
      print('AddToMyDaily: post failed: $e');
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't add to your Daily: $e"),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  static Future<T> _withSpinner<T>(
      BuildContext context, Future<T> Function() work) async {
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black38,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
      ),
    );
    try {
      return await work();
    } catch (e) {
      print('AddToMyDaily: prepare failed: $e');
      return null as T;
    } finally {
      nav.pop();
    }
  }

  // ─── Files ────────────────────────────────────────────────────────────────

  static Future<File> _temp(String ext) async {
    final dir = await getTemporaryDirectory();
    return File(
        '${dir.path}/add_to_daily_${DateTime.now().microsecondsSinceEpoch}.$ext');
  }

  /// A local path is used as-is; a URL is downloaded.
  static Future<File?> _fetch(String path, String ext) async {
    if (!path.startsWith('http')) {
      final f = File(path);
      return await f.exists() ? f : null;
    }
    final out = await _temp(ext);
    try {
      await FirebaseStorage.instance.refFromURL(path).writeToFile(out);
      if (await out.exists() && await out.length() > 0) return out;
    } catch (_) {}
    try {
      final req = await HttpClient().getUrl(Uri.parse(path));
      final res = await req.close();
      if (res.statusCode == 200) {
        await res.pipe(out.openWrite());
        return out;
      }
    } catch (e) {
      print('AddToMyDaily: download failed: $e');
    }
    return null;
  }

  static Future<ui.Image?> _decode(Uint8List bytes, {int? width}) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image?> _avatar(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final b64 = doc.data()?['profilePicBase64'] as String?;
      if (b64 == null || b64.isEmpty) return null;
      return _decode(base64Decode(b64), width: 200);
    } catch (_) {
      return null;
    }
  }

  // ─── The message card ─────────────────────────────────────────────────────

  static const double _w = 1080, _h = 1920;

  /// Draws the card straight onto a 1080x1920 canvas (story-shaped, so it
  /// fills the story with no extra frame).
  static Future<File?> _renderCard({
    required String text,
    required File? photo,
    required String authorUid,
    required String authorName,
  }) async {
    final photoImg = photo == null
        ? null
        : await _decode(await photo.readAsBytes(), width: 1080);
    final avatarImg = await _avatar(authorUid);

    final rec = ui.PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, _w, _h));
    const full = Rect.fromLTWH(0, 0, _w, _h);

    // Background: the photo, blurred and dimmed; or a soft brand gradient.
    if (photoImg != null) {
      final src = _coverSrc(photoImg, full.size);
      c.drawImageRect(
        photoImg,
        src,
        full.inflate(80),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ui.ImageFilter.blur(
              sigmaX: 50, sigmaY: 50, tileMode: TileMode.clamp),
      );
      c.drawRect(full, Paint()..color = Colors.black.withOpacity(0.32));
    } else {
      c.drawRect(
        full,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF26C6DA), Color(0xFF00838F), Color(0xFF0B3A4A)],
            stops: [0.0, 0.5, 1.0],
          ).createShader(full),
      );
      // A couple of soft glows so it doesn't look flat.
      c.drawCircle(
          const Offset(_w * 0.15, _h * 0.12),
          520,
          Paint()
            ..color = Colors.white.withOpacity(0.10)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 160));
      c.drawCircle(
          const Offset(_w * 0.95, _h * 0.9),
          600,
          Paint()
            ..color = Colors.black.withOpacity(0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 180));
    }

    // Card layout
    const cardW = 920.0, pad = 48.0, avatarD = 84.0, gap = 34.0;
    const innerW = cardW - pad * 2;
    const maxCardH = _h - 360;

    double photoH = 0;
    if (photoImg != null) {
      photoH = innerW * photoImg.height / photoImg.width;
      photoH = math.min(photoH, text.isEmpty ? 1100 : 860);
    }

    // Short text reads big; long text gets smaller (and is cut off if huge).
    final len = text.length;
    final fontSize = photoImg != null
        ? (len < 80 ? 46.0 : 40.0)
        : (len < 40 ? 72.0 : len < 120 ? 58.0 : len < 260 ? 48.0 : 42.0);
    final textMaxH =
        maxCardH - pad * 2 - avatarD - gap - (photoH > 0 ? photoH + gap : 0);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF1C1C1E),
          fontSize: fontSize,
          height: 1.3,
          fontWeight: photoImg == null && len < 120
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: math.max(1, (textMaxH / (fontSize * 1.3)).floor()),
      ellipsis: '…',
    )..layout(maxWidth: innerW);

    final textH = text.isEmpty ? 0.0 : tp.height;
    final cardH = pad +
        avatarD +
        (photoH > 0 ? gap + photoH : 0) +
        (textH > 0 ? gap + textH : 0) +
        pad;
    final card = Rect.fromLTWH((_w - cardW) / 2, (_h - cardH) / 2, cardW, cardH);
    final cardR = RRect.fromRectAndRadius(card, const Radius.circular(56));

    c.drawRRect(
        cardR.shift(const Offset(0, 18)),
        Paint()
          ..color = Colors.black.withOpacity(0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40));
    c.drawRRect(cardR, Paint()..color = Colors.white);

    // Header: picture + name
    var y = card.top + pad;
    final aRect = Rect.fromLTWH(card.left + pad, y, avatarD, avatarD);
    c.save();
    c.clipPath(Path()..addOval(aRect));
    if (avatarImg != null) {
      c.drawImageRect(avatarImg, _coverSrc(avatarImg, aRect.size), aRect,
          Paint()..filterQuality = FilterQuality.medium);
    } else {
      c.drawRect(aRect, Paint()..color = const Color(0xFFE0F7FA));
      final initial = authorName.trim().isEmpty
          ? '?'
          : authorName.trim().characters.first.toUpperCase();
      final ip = TextPainter(
        text: TextSpan(
            text: initial,
            style: const TextStyle(
                color: Color(0xFF00838F),
                fontSize: 40,
                fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      ip.paint(c, aRect.center - Offset(ip.width / 2, ip.height / 2));
    }
    c.restore();

    final np = TextPainter(
      text: TextSpan(
        text: authorName.isEmpty ? 'Someone' : authorName,
        style: const TextStyle(
            color: Color(0xFF1C1C1E),
            fontSize: 40,
            fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: innerW - avatarD - 28);
    np.paint(c, Offset(aRect.right + 28, aRect.center.dy - np.height / 2));
    y += avatarD;

    // Photo
    if (photoImg != null && photoH > 0) {
      y += gap;
      final pRect = Rect.fromLTWH(card.left + pad, y, innerW, photoH);
      c.save();
      c.clipRRect(RRect.fromRectAndRadius(pRect, const Radius.circular(32)));
      c.drawImageRect(photoImg, _coverSrc(photoImg, pRect.size), pRect,
          Paint()..filterQuality = FilterQuality.high);
      c.restore();
      y += photoH;
    }

    // Text
    if (textH > 0) {
      y += gap;
      tp.paint(c, Offset(card.left + pad, y));
    }

    final img = await rec.endRecording().toImage(_w.toInt(), _h.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    photoImg?.dispose();
    avatarImg?.dispose();
    if (data == null) return null;

    final jpg = await FlutterImageCompress.compressWithList(
      data.buffer.asUint8List(),
      minWidth: 1080,
      minHeight: 1920,
      quality: 90,
      format: CompressFormat.jpeg,
    );
    final out = await _temp('jpg');
    await out.writeAsBytes(jpg);
    return out;
  }

  /// The part of [img] that fills [box] like BoxFit.cover.
  static Rect _coverSrc(ui.Image img, Size box) {
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final boxAspect = box.width / box.height;
    if (iw / ih > boxAspect) {
      final w = ih * boxAspect;
      return Rect.fromLTWH((iw - w) / 2, 0, w, ih);
    }
    final h = iw / boxAspect;
    return Rect.fromLTWH(0, (ih - h) / 2, iw, h);
  }
}

enum _Kind { video, photo, card }

class _Prepared {
  final File file;
  final bool isVideo;
  final _Kind kind;
  final MusicTrack? music;
  final Map<String, dynamic>? source;

  _Prepared(this.file,
      {required this.isVideo, required this.kind, this.music, this.source});
}