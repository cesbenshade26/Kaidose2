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

  /// Whichever palette the app is using right now (see [kc]).
  static AppColors get current => AppTheme.isDark ? dark : light;

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

/// The palette in use right now, without needing a `context`.
///
/// Most screens use `kc.text`, `kc.surface` and so on; it reads the same
/// light/dark choice as the theme. When the choice (or the phone's own
/// setting) changes, [ThemeRebuilder] redraws every screen so they all
/// pick up the new colors at once.
AppColors get kc => AppColors.current;

extension AppColorsHelpers on AppColors {
  bool get _dark => background.computeLuminance() < 0.2;

  /// Material's grey shades, unchanged in light mode; in dark mode the
  /// same role in Kaidose's dark greys (light greys used as backgrounds
  /// become dark surfaces, darker greys used for text become lighter).
  Color grey(int shade) {
    if (!_dark) return Colors.grey[shade] ?? Colors.grey;
    if (shade <= 100) return surfaceMuted;
    if (shade <= 200) return line;
    if (shade <= 350) return border;
    if (shade <= 400) return const Color(0xFF636366);
    if (shade <= 500) return textFaint;
    if (shade <= 600) return textMuted;
    if (shade <= 700) return const Color(0xFFC7C7CC);
    if (shade <= 850) return const Color(0xFFD1D1D6);
    return Colors.grey[shade] ?? Colors.grey;
  }

  /// Any fixed light-mode grey: exactly [c] in light mode; in dark mode the
  /// matching dark role, picked by how light [c] is (near-white backgrounds
  /// -> dark surfaces, mid greys -> muted text, near-black -> main text).
  Color adapt(Color c) {
    if (!_dark) return c;
    final l = c.computeLuminance();
    final Color out;
    if (l > 0.88) {
      out = surfaceMuted;
    } else if (l > 0.74) {
      out = line;
    } else if (l > 0.55) {
      out = border;
    } else if (l > 0.3) {
      out = textFaint;
    } else if (l > 0.1) {
      out = textMuted;
    } else {
      out = text;
    }
    return c.alpha == 255 ? out : out.withAlpha(c.alpha);
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
  static const bool darkModeReady = true;

  static const String _key = 'theme_mode';

  /// The user's choice (System by default).
  static final ValueNotifier<ThemeMode> mode =
  ValueNotifier<ThemeMode>(ThemeMode.system);

  /// What the app actually uses right now.
  static ThemeMode get effective =>
      darkModeReady ? mode.value : ThemeMode.light;

  /// Is the app dark right now? "Match phone" follows the phone's own
  /// light/dark setting (iPhone and Android), live.
  static bool get isDark {
    switch (effective) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }

  /// Status bar style for a plain page: dark icons on a light page, light
  /// icons on a dark one. (Over photos screens still use .light.)
  static SystemUiOverlayStyle get pageOverlay =>
      isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

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


/// Wrap the app in this (main.dart). When the light/dark choice or the
/// phone's own setting changes, it redraws every screen, including ones
/// that read colors through [kc] rather than the theme.
class ThemeRebuilder extends StatefulWidget {
  final Widget child;
  const ThemeRebuilder({Key? key, required this.child}) : super(key: key);

  @override
  State<ThemeRebuilder> createState() => _ThemeRebuilderState();
}

class _ThemeRebuilderState extends State<ThemeRebuilder>
    with WidgetsBindingObserver {
  bool _wasDark = AppTheme.isDark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppTheme.mode.addListener(_check);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppTheme.mode.removeListener(_check);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _check();

  void _check() {
    final dark = AppTheme.isDark;
    if (dark == _wasDark) return;
    _wasDark = dark;
    if (!mounted) return;
    setState(() {});
    // Mark every screen below for a redraw (including pages under the
    // current one and kept-alive tabs).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void redraw(Element e) {
        e.markNeedsBuild();
        e.visitChildren(redraw);
      }
      (context as Element).visitChildren(redraw);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}