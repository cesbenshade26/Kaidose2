import 'package:flutter/material.dart';

/// Kaidose's second color: the warm yellow of the sun in the app icon.
///
/// Cyan is the app's one accent (buttons, links, switches, selected states,
/// story rings). Sun is kept for a few small touches: the Daily prompt and
/// the sun you give a story. Keep it rare so screens stay one-color.
class SunColors {
  SunColors._();

  /// Golden yellow (the icon's rays, a touch richer so it holds up on white).
  static const Color light = Color(0xFFF9D45C);

  /// Warm amber: the middle of the sun's face.
  static const Color mid = Color(0xFFF4B04F);

  /// Warm orange: the bottom-right edge of the face.
  static const Color deep = Color(0xFFEE8F55);

  /// For small text and icons on white (the yellows are too light to read
  /// there).
  static const Color ink = Color(0xFFD9822B);

  /// A whisper of sun for card backgrounds.
  static const Color soft = Color(0x1FF4B04F); // ~12%

  /// Corner to corner, like the icon: for filled things (dots, the "+").
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [light, mid, deep],
    stops: [0.0, 0.5, 1.0],
  );

  /// All the way around a circle, gold -> orange -> gold, so a ring looks
  /// even on every side (a corner-to-corner fade made one side look faded).
  static const SweepGradient ring = SweepGradient(
    colors: [light, mid, deep, mid, light],
    stops: [0.0, 0.3, 0.5, 0.7, 1.0],
    transform: GradientRotation(-1.5708), // start at the top
  );
}

/// A ring around an avatar: cyan when there's something new, a thin grey
/// line once seen. Takes the same space as a `Border.all` of
/// the same width did, so swapping it in doesn't move anything.
class SunRing extends StatelessWidget {
  final Widget child;
  final bool active;
  final double activeWidth;
  final double seenWidth;
  final Color seenColor;

  const SunRing({
    Key? key,
    required this.child,
    required this.active,
    this.activeWidth = 3.5,
    this.seenWidth = 1.5,
    this.seenColor = const Color(0xFFD5D7DB),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final w = active ? activeWidth : seenWidth;
    return CustomPaint(
      painter: SunRingPainter(active: active, width: w, seenColor: seenColor),
      child: Padding(padding: EdgeInsets.all(w), child: child),
    );
  }
}

/// Paints the ring just inside its box (like a border would). Story rings
/// are cyan; [sun] paints the yellow sun gradient instead (used for the
/// little burst when you give a story a sun).
class SunRingPainter extends CustomPainter {
  final bool active;
  final double width;
  final Color seenColor;
  final bool sun;

  const SunRingPainter({
    required this.active,
    required this.width,
    this.seenColor = const Color(0xFFD5D7DB),
    this.sun = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (width <= 0) return;
    final rect = Offset.zero & size;
    final radius = size.shortestSide / 2 - width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..isAntiAlias = true;
    if (active && sun) {
      paint.shader = SunColors.ring.createShader(rect);
    } else if (active) {
      paint.color = Colors.cyan;
    } else {
      paint.color = seenColor;
    }
    canvas.drawCircle(rect.center, radius, paint);
  }

  @override
  bool shouldRepaint(SunRingPainter old) =>
      old.active != active ||
          old.width != width ||
          old.seenColor != seenColor ||
          old.sun != sun;
}