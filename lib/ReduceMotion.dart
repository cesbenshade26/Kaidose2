import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Follows the phone's own setting: iPhone Settings → Accessibility →
/// Motion → Reduce Motion, or Android's "Remove animations". Kaidose has no
/// switch of its own; when it's on, screens fade instead of sliding and the
/// bigger flourishes (heart pops, floating hearts) are skipped.
class ReduceMotion {
  ReduceMotion._();

  static bool of(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or no time at all when motion is reduced.
  static Duration duration(BuildContext context, Duration d) =>
      of(context) ? Duration.zero : d;

  /// The app's page transitions, wrapped so they turn into a simple fade
  /// when motion is reduced. iPhone swipe-back still works.
  static PageTransitionsTheme transitions(PageTransitionsTheme base) {
    final b = base.builders;
    return PageTransitionsTheme(builders: {
      TargetPlatform.iOS: _Calm(b[TargetPlatform.iOS] ??
          const CupertinoPageTransitionsBuilder()),
      TargetPlatform.android: _Calm(b[TargetPlatform.android] ??
          const ZoomPageTransitionsBuilder()),
      TargetPlatform.macOS: _Calm(b[TargetPlatform.macOS] ??
          const CupertinoPageTransitionsBuilder()),
    });
  }
}

class _Calm extends PageTransitionsBuilder {
  final PageTransitionsBuilder normal;
  const _Calm(this.normal);

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
      ) {
    if (!ReduceMotion.of(context)) {
      return normal.buildTransitions(
          route, context, animation, secondaryAnimation, child);
    }
    // No sliding or zooming: the page just fades in. The normal builder
    // still wraps it (with its motion held still) so the iPhone back swipe
    // keeps working.
    return FadeTransition(
      opacity: animation,
      child: normal.buildTransitions(route, context, kAlwaysCompleteAnimation,
          kAlwaysDismissedAnimation, child),
    );
  }
}