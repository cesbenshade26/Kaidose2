import 'package:flutter/material.dart';

/// A page route that reveals its destination via a circle expanding out
/// from wherever the user tapped, rather than the default slide-from-right
/// transition. Used for Your Daily / friend story circles, since a side
/// slide visually implies you can swipe back to dismiss — which these
/// story viewers don't support — whereas this makes it look like the
/// story erupts out of the circle you tapped.
class CircleRevealRoute<T> extends PageRouteBuilder<T> {
  CircleRevealRoute({
    required WidgetBuilder builder,
    required Offset center,
    Duration duration = const Duration(milliseconds: 380),
  }) : super(
    opaque: false,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final size = MediaQuery.of(context).size;

          // Largest distance from the tap point to any screen
          // corner — guarantees the circle fully covers the screen
          // once grown to this radius.
          final corners = <Offset>[
            Offset.zero,
            Offset(size.width, 0),
            Offset(0, size.height),
            Offset(size.width, size.height),
          ];
          final maxRadius = corners
              .map((corner) => (center - corner).distance)
              .reduce((a, b) => a > b ? a : b);

          final curvedValue = Curves.easeOutCubic.transform(animation.value);
          final radius = maxRadius * curvedValue;

          return ClipPath(
            clipper: _CircleRevealClipper(center: center, radius: radius),
            child: child,
          );
        },
        child: child,
      );
    },
  );
}

class _CircleRevealClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;

  _CircleRevealClipper({required this.center, required this.radius});

  @override
  Path getClip(Size size) {
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(covariant _CircleRevealClipper oldClipper) {
    return oldClipper.radius != radius || oldClipper.center != center;
  }
}