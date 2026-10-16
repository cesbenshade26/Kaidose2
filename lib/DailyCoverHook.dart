import 'dart:math';
import 'dart:typed_data';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Flip to false to skip AI entirely (covers still work, they just show
/// the placeholder hook). Handy for testing layout without spending calls.
const bool kCoverHooksEnabled = true;

/// Writes the one-line teaser shown under a Daily's title on its cover.
///
/// Uses Firebase AI Logic with the Gemini Developer API. Called once per
/// Daily per time-zone-day, at the moment its cover is generated, and the
/// result is stored on the cover doc, so it is never regenerated just
/// because someone scrolled past the card.
class DailyCoverHookService {
  // If the model is ever retired, this is the only line to change.
  static const String _modelName = 'gemini-3.5-flash-lite';

  static const Duration _timeout = Duration(seconds: 20);
  static const int _maxHookLength = 160;

  static GenerativeModel? _cachedModel;
  static GenerativeModel get _model {
    return _cachedModel ??= FirebaseAI.googleAI().generativeModel(
      model: _modelName,
      generationConfig: GenerationConfig(temperature: 0.9),
    );
  }

  /// Returns a hook, or null if none could be produced (AI disabled,
  /// request failed or timed out, response blocked or unusable). Callers
  /// treat null as "show the placeholder", never as an error.
  static Future<String?> generateHook({
    required String dailyTitle,
    String? dailyDescription,
    String? coverCaption,
    List<String> contextTexts = const [],
    String? imageUrl,
    bool coverIsVideo = false,
  }) async {
    if (!kCoverHooksEnabled) return null;

    try {
      final parts = <Part>[
        TextPart(_buildPrompt(
          dailyTitle: dailyTitle,
          dailyDescription: dailyDescription,
          coverCaption: coverCaption,
          contextTexts: contextTexts,
          coverIsVideo: coverIsVideo,
          hasImage: imageUrl != null,
        )),
      ];

      if (imageUrl != null) {
        final bytes = await _loadImageBytes(imageUrl);
        if (bytes != null) parts.add(InlineDataPart('image/jpeg', bytes));
      }

      final response =
      await _model.generateContent([Content.multi(parts)]).timeout(_timeout);

      final hook = _clean(response.text);
      print('DailyCoverHookService: hook for "$dailyTitle": $hook');
      return hook;
    } catch (e) {
      print('DailyCoverHookService: hook generation failed: $e');
      return null;
    }
  }

  // Rotated randomly per generation so hooks don't all collapse into the
  // same shape and cadence over time — this is the actual fix for
  // sameness, more than any amount of raised model temperature is.
  static const List<String> _tones = [
    'a hint of mystery — tease without explaining, understated',
    'playful understatement — downplay something that was clearly a big deal',
    'a pointed question that does not answer itself',
    'blunt and matter-of-fact, letting the understatement do the work',
    'excited and a little breathless',
    'dry, deadpan, almost bored-sounding',
    'warm and inviting, like catching up with a friend',
  ];

  static String _pickTone() => _tones[Random().nextInt(_tones.length)];

  static String _buildPrompt({
    required String dailyTitle,
    String? dailyDescription,
    String? coverCaption,
    required List<String> contextTexts,
    required bool coverIsVideo,
    required bool hasImage,
  }) {
    final b = StringBuffer();

    final caption = coverCaption?.trim() ?? '';
    // Whether there's any real text to tease around at all — a caption
    // on the cover itself, or other messages in the window. When this is
    // false, the Daily has nothing to "reveal" beyond the photo itself,
    // so a hook implying a hidden story would set up a tap-in with no
    // payoff waiting on the other side.
    final hasGroundingText = caption.isNotEmpty || contextTexts.isNotEmpty;

    b.writeln('You write the teaser line for a card in a social app. Each card '
        'represents a shared group "Daily". The card shows one line of text '
        'above a photo.');
    b.writeln();

    if (hasGroundingText) {
      b.writeln('There is real context below (a caption and/or other '
          'messages) — something genuinely happened or was said. Tease '
          'that, the way a breaking-news teaser does: hint at it without '
          'explaining what it actually was. Someone who taps in should '
          'find the thing you hinted at waiting for them.');
    } else if (hasImage) {
      b.writeln('There is no caption and no other messages — just this '
          'photo, nothing else. There is no hidden story to tease, so do '
          'NOT imply one (nothing like "you won\'t believe what happened" '
          'or "that could have gone worse" — there is no payoff for that '
          'when someone taps in and finds only the same image). Instead, '
          'make the line about wanting to actually see this specific '
          'image up close — visual curiosity, not narrative curiosity. Do '
          'NOT simply describe what is in the image (e.g. never just "a '
          'bunch of pink flowers") — a plain description is a caption, '
          'not a hook, and creates zero curiosity. Find an angle, a '
          'reaction, or an unanswered question about it instead.');
    } else {
      b.writeln('There is no caption, no other messages, and this cover '
          'is a video — you have not been shown any frame from it, so you '
          'have no actual information about what it shows, only the '
          'Daily\'s own name/description below. Do not invent specific '
          'visual details or imply a specific event you have no way of '
          'knowing happened (nothing like a precise image of something '
          'falling, breaking, arriving, etc. — you cannot verify any of '
          'that). Keep the line honest about that limit: build curiosity '
          'around checking in on this Daily today, grounded only in what '
          'its actual name/description says it is about.');
    }

    b.writeln();
    b.writeln('Rules:');
    b.writeln('- One line, under 90 characters.');
    b.writeln('- Base it only on what is actually in the photo and the '
        'messages below. Never invent events, names, or facts.');
    b.writeln('- No hashtags, no quotation marks.');
    b.writeln('- Most good hooks use no emoji at all. Only add one if it '
        'genuinely fits the tone below — never add one just out of habit, '
        'and never use more than one.');
    b.writeln('- Do not mention "photo", "picture", "image", or "video".');
    b.writeln('- Reply with only the line itself.');
    b.writeln();
    b.writeln('Tone for this one specifically: ${_pickTone()}. Commit to it — '
        "don't hedge toward a generic, safe-sounding tone instead. But "
        'tone is secondary to accuracy: it should flavor HOW you talk '
        'about what is actually in the photo/messages, never pull you '
        'toward something more dramatic-sounding instead of what is '
        'really there. If the two conflict, staying true to the real '
        'content wins — a flatter hook that is actually about the right '
        'thing beats a punchier one that isn\'t.');
    b.writeln();
    b.writeln('Daily name: "$dailyTitle"');

    final about = dailyDescription?.trim() ?? '';
    if (about.isNotEmpty) b.writeln('About this Daily: $about');

    if (caption.isNotEmpty) b.writeln('Caption posted with the cover: $caption');

    if (coverIsVideo && !hasImage) {
      b.writeln('The cover is a video, which you cannot see. Rely on the '
          'caption and messages.');
    }

    if (contextTexts.isNotEmpty) {
      b.writeln('Recent messages in this Daily:');
      for (final t in contextTexts) {
        b.writeln('- $t');
      }
    }

    return b.toString();
  }

  /// Downloads the cover and shrinks it — the model doesn't need a
  /// full-resolution photo to write a teaser, and smaller is faster and
  /// cheaper.
  static Future<Uint8List?> _loadImageBytes(String url) async {
    try {
      final original = await FirebaseStorage.instance
          .refFromURL(url)
          .getData(20 * 1024 * 1024)
          .timeout(_timeout);
      if (original == null) return null;

      try {
        return await FlutterImageCompress.compressWithList(
          original,
          minWidth: 768,
          minHeight: 768,
          quality: 70,
          format: CompressFormat.jpeg,
        );
      } catch (_) {
        // Compression failed; the original is fine if it isn't huge.
        return original.length <= 4 * 1024 * 1024 ? original : null;
      }
    } catch (e) {
      print('DailyCoverHookService: could not load cover image: $e');
      return null;
    }
  }

  /// Turns raw model output into something safe to show: first line only,
  /// surrounding quotes and a stray "Hook:" label removed, and nothing
  /// that's still absurdly long. Null means "use the placeholder".
  static String? _clean(String? raw) {
    if (raw == null) return null;

    String? line;
    for (final l in raw.split('\n')) {
      if (l.trim().isNotEmpty) {
        line = l.trim();
        break;
      }
    }
    if (line == null) return null;

    line = line.replaceFirst(
        RegExp(r'^(hook|teaser)\s*:\s*', caseSensitive: false), '');
    line = line.replaceAll(RegExp(r'^["\u201C\u2018\x27]+|["\u201D\u2019\x27]+$'), '');
    line = line.trim();

    if (line.isEmpty || line.length > _maxHookLength) return null;
    return line;
  }
}