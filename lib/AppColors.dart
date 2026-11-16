import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kaidose's colors, with a light and a dark version of each.
///
/// In a widget, use `context.colors.text` (and so on) instead of fixed
/// colors like `Colors.black87`, so the screen follows light/dark mode:
///
///   Colors.white          -> colors.background (pages) / colors.surface (cards)
///   Colors.grey[50/100]   -> colors.surfaceMuted (input boxes, soft cards)
///   Colors.grey[200]      -> colors.line   (dividers, hairlines)
///   Colors.grey[300]      -> colors.border (outlines)
///   Colors.black/black87  -> colors.text
///   Colors.grey[600/700]  -> colors.textMuted
///   Colors.grey[400/500]  -> colors.textFaint
///   Colors.cyan           -> colors.accent
///   cyan.withOpacity(.1)  -> colors.accentSoft
///
/// Photos, videos, Clips (always dark) and red for delete stay as they are.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color line;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color accent;
  final Color accentSoft;
  final Color danger;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.line,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentSoft,
    required this.danger,
  });

  /// Today's look, exactly.
  static const AppColors light = AppColors(
    background: Colors.white,
    surface: Colors.white,
    surfaceMuted: Color(0xFFF5F5F5), // grey[100]
    line: Color(0xFFEEEEEE), // grey[200]
    border: Color(0xFFE0E0E0), // grey[300]
    text: Color(0xDD000000), // black87
    textMuted: Color(0xFF757575), // grey[600]
    textFaint: Color(0xFF9E9E9E), // grey[500]
    accent: Color(0xFF00BCD4), // cyan
    accentSoft: Color(0x1A00BCD4), // cyan 10%
    danger: Color(0xFFE53935),
  );

  /// Apple-style dark greys with a slightly softer cyan.
  static const AppColors dark = AppColors(
    background: Color(0xFF121214),
    surface: Color(0xFF1C1C1E),
    surfaceMuted: Color(0xFF2C2C2E),
    line: Color(0xFF2C2C2E),
    border: Color(0xFF3A3A3C),
    text: Color(0xFFF2F2F7),
    textMuted: Color(0xFFAEAEB2),
    textFaint: Color(0xFF8E8E93),
    accent: Color(0xFF26C6DA), // cyan[400]
    accentSoft: Color(0x2926C6DA), // ~16%
    danger: Color(0xFFFF453A),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? line,
    Color? border,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? accent,
    Color? accentSoft,
    Color? danger,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      line: line ?? this.line,
      border: border ?? this.border,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      line: l(line, other.line),
      border: l(border, other.border),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textFaint: l(textFaint, other.textFaint),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      danger: l(danger, other.danger),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The current palette (light or dark).
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Light / dark / follow the phone, remembered on this device.
class AppTheme {
  /// Flip to true once every screen uses AppColors. Until then the app stays
  /// light no matter what, so nobody sees a half-dark app.
  static const bool darkModeReady = false;

  static const String _key = 'theme_mode';

  /// The user's choice (System by default).
  static final ValueNotifier<ThemeMode> mode =
  ValueNotifier<ThemeMode>(ThemeMode.system);

  /// What the app actually uses right now.
  static ThemeMode get effective =>
      darkModeReady ? mode.value : ThemeMode.light;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (prefs.getString(_key)) {
        case 'light':
          mode.value = ThemeMode.light;
          break;
        case 'dark':
          mode.value = ThemeMode.dark;
          break;
        default:
          mode.value = ThemeMode.system;
      }
    } catch (_) {}
  }

  /// For the System / Light / Dark choice in Settings.
  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, m.name);
    } catch (_) {}
  }

  /// Exactly today's look (plain ThemeData + the light palette), so turning
  /// this on changes nothing in light mode.
  static ThemeData get lightTheme => ThemeData(
    extensions: const [AppColors.light],
  );

  static ThemeData get darkTheme {
    const c = AppColors.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: c.accent,
      surface: c.surface,
      onSurface: c.text,
      error: c.danger,
    );
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.line,
      extensions: const [AppColors.dark],
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceMuted,
        contentTextStyle: TextStyle(color: c.text),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    );
  }
}