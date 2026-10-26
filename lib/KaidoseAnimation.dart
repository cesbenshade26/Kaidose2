// KaidoseAnimation.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'KaidoseBrand.dart';

/// The opening animation: "Kaidose" draws in letter by letter, a cyan
/// underline sweeps beneath, a short hold, then [onAnimationComplete].
///
/// It plays at most once per app run, and not at all when someone is already
/// signed in (they should land straight in the app) — in those cases
/// [onAnimationComplete] is called right away.
class KaidoseAnimation extends StatefulWidget {
  final VoidCallback onAnimationComplete;
  final bool fadeOutAtEnd;

  /// Play even if it already played this run or someone is signed in.
  final bool force;

  const KaidoseAnimation({
    Key? key,
    required this.onAnimationComplete,
    this.fadeOutAtEnd = false,
    this.force = false,
  }) : super(key: key);

  @override
  State<KaidoseAnimation> createState() => _KaidoseAnimationState();
}

class _KaidoseAnimationState extends State<KaidoseAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _draw;
  late final AnimationController _fade;
  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fade = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    final alreadySignedIn = FirebaseAuth.instance.currentUser != null;
    if (!widget.force && (KaidoseIntro.played || alreadySignedIn)) {
      _skipped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onAnimationComplete();
      });
      return;
    }
    KaidoseIntro.played = true;
    _run();
  }

  Future<void> _run() async {
    await KaidoseBrand.preloadFonts();
    if (!mounted) return;
    await _draw.forward();
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    if (widget.fadeOutAtEnd) await _fade.forward();
    if (mounted) widget.onAnimationComplete();
  }

  @override
  void dispose() {
    _draw.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_skipped) return const Scaffold(backgroundColor: Colors.white);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: ReverseAnimation(_fade),
          child: KaidoseWordmark(progress: _draw, fontSize: 60),
        ),
      ),
    );
  }
}