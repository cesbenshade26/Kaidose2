import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'AppColors.dart';
import 'KaidoseBrand.dart';
import 'SettingsWidgets.dart';

/// Settings → Display: light or dark mode.
///
/// "Match phone" (the default) follows the phone's own setting on iPhone
/// and Android and switches along with it. Light and Dark keep Kaidose that
/// way whatever the phone uses. Saved on this device.
///
/// Little secret: the whole page (title bar included) scrolls, and pulling
/// it down far past the top reveals a thank-you note hiding behind it.
class DisplaySettingsScreen extends StatefulWidget {
  const DisplaySettingsScreen({Key? key}) : super(key: key);

  @override
  State<DisplaySettingsScreen> createState() => _DisplaySettingsScreenState();
}

class _DisplaySettingsScreenState extends State<DisplaySettingsScreen> {
  final ScrollController _scroll = ScrollController();

  /// How far past the top you pull before the note starts to show, and how
  /// much further until it's fully there. A normal bounce never gets close.
  static const double _hiddenUntil = 70;
  static const double _fullAt = 160;

  /// 0 = hidden, 1 = fully shown.
  final ValueNotifier<double> _reveal = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final pulled = _scroll.hasClients ? -_scroll.offset : 0.0;
      _reveal.value = ((pulled - _hiddenUntil) / (_fullAt - _hiddenUntil))
          .clamp(0.0, 1.0);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, mode, _) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.pageOverlay,
        child: Scaffold(
          backgroundColor: SettingsStyle.page,
          body: Stack(
            children: [
              // The note sits behind the page, under the status bar.
              Positioned(
                top: topInset + 18,
                left: 24,
                right: 24,
                child: _ThanksNote(reveal: _reveal),
              ),
              CustomScrollView(
                controller: _scroll,
                // Bouncy on Android too, so the page can be pulled down past
                // its top everywhere.
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  // A plain header instead of an app bar: an app bar stays
                  // stuck to the top when the page is pulled down, while this
                  // moves with the page like everything else (as in Dailies).
                  SliverToBoxAdapter(
                    child: Container(
                      color: SettingsStyle.page,
                      padding: EdgeInsets.only(top: topInset),
                      height: topInset + kToolbarHeight,
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.adaptive.arrow_back,
                                color: SettingsStyle.ink),
                            onPressed: () => Navigator.maybePop(context),
                          ),
                          Expanded(
                            child: Text(
                              'Display',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: SettingsStyle.ink,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 48), // balances the back button
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        SettingsGroup(
                          title: 'Appearance',
                          footer: mode == ThemeMode.system
                              ? 'Kaidose switches between light and dark '
                              'along with your phone.'
                              : null,
                          children: [
                            _ModeTile(
                              icon: Icons.brightness_auto_outlined,
                              title: 'Match phone',
                              subtitle: 'Use your phone’s light or dark setting',
                              value: ThemeMode.system,
                              selected: mode,
                            ),
                            _ModeTile(
                              icon: Icons.light_mode_outlined,
                              title: 'Light',
                              value: ThemeMode.light,
                              selected: mode,
                            ),
                            _ModeTile(
                              icon: Icons.dark_mode_outlined,
                              title: 'Dark',
                              value: ThemeMode.dark,
                              selected: mode,
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Thanks for using the app" signed by the Kaidose buddy. Fades and rises
/// in as the page is pulled down.
class _ThanksNote extends StatelessWidget {
  final ValueNotifier<double> reveal;
  const _ThanksNote({required this.reveal});

  /// The buddy from the app icon (pubspec.yaml lists it under assets).
  static const String iconAsset = 'assets/icon/app_icon_foreground.png';

  @override
  Widget build(BuildContext context) {
    final style = KaidoseBrand.wordmark(22, color: kc.text);
    return ValueListenableBuilder<double>(
      valueListenable: reveal,
      builder: (context, t, child) => IgnorePointer(
        child: Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: child,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Thanks for using the app',
              textAlign: TextAlign.center, style: style),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('–', style: style),
              const SizedBox(width: 6),
              // The icon file has a lot of empty space around the buddy
              // (app icons need it), so it's drawn larger than its box
              // and the buddy itself comes out about text-sized.
              SizedBox(
                width: 30,
                height: 30,
                child: OverflowBox(
                  maxWidth: 72,
                  maxHeight: 72,
                  child: Image.asset(
                    iconAsset,
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(Icons.wb_sunny_rounded,
                        size: 26, color: Colors.amber[600]),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final ThemeMode value;
  final ThemeMode selected;

  const _ModeTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.selected,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final on = value == selected;
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      showChevron: false,
      trailing: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: const Icon(Icons.check_rounded, color: Colors.cyan, size: 22),
      ),
      onTap: () => AppTheme.set(value),
    );
  }
}