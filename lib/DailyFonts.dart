import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The fonts a Daily's title can use, in one place (the edit sheet, the
/// Dailies cards, the inside of a Daily, Manage Daily all read from here).
///
/// Five, all easy to read at card size. Dailies saved with a font that's no
/// longer offered just show in the default font.
///
/// [preload] downloads them all when the app opens (main.dart), and
/// google_fonts keeps them on the phone after that, so titles never show in
/// the default font first and then switch.
class DailyFonts {
  DailyFonts._();

  static const String defaultFont = 'Default';

  /// In the order the edit sheet shows them.
  static const List<String> options = [
    defaultFont,
    'Playfair Display', // elegant serif
    'Righteous', // rounded, playful
    'Bebas Neue', // bold, tall caps
    'Permanent Marker', // hand-drawn marker
  ];

  // Weights titles are drawn in (cards 700, inside a Daily 600).
  static const List<FontWeight> _weights = [
    FontWeight.w400,
    FontWeight.w600,
    FontWeight.w700,
  ];

  /// [font] if it's still offered, otherwise the default.
  static String normalize(String? font) =>
      options.contains(font) ? font! : defaultFont;

  /// The style for a title in [font] (pass the weight here rather than in
  /// copyWith, so the real bold file is used instead of a faked one).
  static TextStyle style(String? font, {FontWeight? fontWeight}) {
    final name = normalize(font);
    if (name == defaultFont) return TextStyle(fontWeight: fontWeight);
    try {
      return GoogleFonts.getFont(name, fontWeight: fontWeight);
    } catch (_) {
      return TextStyle(fontWeight: fontWeight);
    }
  }

  static Future<void>? _preloading;

  /// Starts loading every font and weight. Safe to call more than once;
  /// doesn't block anything (call without awaiting).
  static Future<void> preload() {
    return _preloading ??= () async {
      try {
        await GoogleFonts.pendingFonts([
          for (final name in options)
            if (name != defaultFont)
              for (final w in _weights) GoogleFonts.getFont(name, fontWeight: w),
        ]);
      } catch (e) {
        // Offline: they load the first time they're shown instead.
        _preloading = null;
        print('DailyFonts: preload failed: $e');
      }
    }();
  }
}