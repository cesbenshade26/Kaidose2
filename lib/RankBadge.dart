import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Kaidose ranks, earned by total days lit. The ladder is a fire growing
/// into a sun: Spark -> Ember -> Flare -> Beacon -> Radiant -> Solstice.
class KaidoseRank {
  final int index;
  final String name;

  /// Days lit needed to reach this rank.
  final int minDays;

  /// Color used for the rank's name text.
  final Color accent;

  const KaidoseRank._(this.index, this.name, this.minDays, this.accent);

  static const List<KaidoseRank> all = [
    KaidoseRank._(0, 'Spark', 0, Color(0xFF8D6E63)),
    KaidoseRank._(1, 'Ember', 10, Color(0xFFE65100)),
    KaidoseRank._(2, 'Flare', 50, Color(0xFF546E7A)),
    KaidoseRank._(3, 'Beacon', 100, Color(0xFFB26A00)),
    KaidoseRank._(4, 'Radiant', 250, Color(0xFF00838F)),
    KaidoseRank._(5, 'Solstice', 500, Color(0xFF7C4DFF)),
  ];

  static KaidoseRank forDays(int days) {
    for (var i = all.length - 1; i >= 0; i--) {
      if (days >= all[i].minDays) return all[i];
    }
    return all.first;
  }

  /// The next rank up, or null at the top.
  KaidoseRank? get next => index + 1 < all.length ? all[index + 1] : null;
}

/// A rank's icon, drawn in code so it stays sharp at any size.
class RankBadge extends StatelessWidget {
  final KaidoseRank rank;
  final double size;

  const RankBadge({Key? key, required this.rank, this.size = 40})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _RankPainter(rank.index)),
    );
  }
}

// ---------------------------------------------------------------------------
// Drawing. Everything is laid out on a 160 x 160 canvas centred on (0, 0).
// ---------------------------------------------------------------------------

Shader _lin(List<Color> colors, [List<double>? stops]) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: colors,
  stops: stops,
).createShader(const Rect.fromLTWH(-60, -60, 120, 120));

Paint _fill(Color c) => Paint()..color = c;
Paint _fillS(Shader s) => Paint()..shader = s;
Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;
Paint _strokeS(Shader s, double w) => Paint()
  ..shader = s
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

Path _rays(int n, double r1, double r2, double w,
    {double rot = 0, double? alt}) {
  final p = Path();
  for (var i = 0; i < n; i++) {
    final a = (rot + i * 360 / n) * math.pi / 180;
    final rr = (alt != null && i.isOdd) ? alt : r2;
    p.moveTo(r1 * math.cos(a - w), r1 * math.sin(a - w));
    p.lineTo(rr * math.cos(a), rr * math.sin(a));
    p.lineTo(r1 * math.cos(a + w), r1 * math.sin(a + w));
    p.close();
  }
  return p;
}

Path _star(int n, double ro, double ri, {double rot = -90}) {
  final p = Path();
  for (var i = 0; i < n * 2; i++) {
    final r = i.isEven ? ro : ri;
    final a = (rot + i * 180 / n) * math.pi / 180;
    final x = r * math.cos(a);
    final y = r * math.sin(a);
    if (i == 0) {
      p.moveTo(x, y);
    } else {
      p.lineTo(x, y);
    }
  }
  p.close();
  return p;
}

Path _flameOuter() => Path()
  ..moveTo(0, -34)
  ..cubicTo(14, -16, 26, -6, 26, 10)
  ..arcToPoint(const Offset(-26, 10),
      radius: const Radius.circular(26), clockwise: true)
  ..cubicTo(-26, 0, -18, -8, -12, -18)
  ..cubicTo(-10, -8, -4, -6, -4, -14)
  ..cubicTo(-4, -22, -2, -28, 0, -34)
  ..close();

Path _flameInner() => Path()
  ..moveTo(0, 0)
  ..cubicTo(8, 8, 12, 14, 12, 20)
  ..arcToPoint(const Offset(-12, 20),
      radius: const Radius.circular(12), clockwise: true)
  ..cubicTo(-12, 12, -4, 8, 0, 0)
  ..close();

Path _shield() => Path()
  ..moveTo(0, -44)
  ..lineTo(32, -32)
  ..lineTo(32, 6)
  ..cubicTo(32, 26, 14, 40, 0, 48)
  ..cubicTo(-14, 40, -32, 26, -32, 6)
  ..lineTo(-32, -32)
  ..close();

Path _wing() => Path()
  ..moveTo(30, -6)
  ..cubicTo(48, -26, 66, -24, 74, -34)
  ..cubicTo(72, -14, 60, -4, 44, 4)
  ..cubicTo(58, 2, 66, 0, 72, -4)
  ..cubicTo(66, 10, 50, 16, 34, 14)
  ..close();

class _RankPainter extends CustomPainter {
  final int index;
  _RankPainter(this.index);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 160);
    switch (index) {
      case 0:
        _spark(canvas);
        break;
      case 1:
        _ember(canvas);
        break;
      case 2:
        _flare(canvas);
        break;
      case 3:
        _beacon(canvas);
        break;
      case 4:
        _radiant(canvas);
        break;
      default:
        _solstice(canvas);
    }
    canvas.restore();
  }

  void _spark(Canvas c) {
    c.drawPath(_star(4, 34, 7),
        _fillS(_lin(const [Color(0xFFD7CCC8), Color(0xFFA1887F)])));
    c.drawCircle(Offset.zero, 5, _fill(Colors.white.withOpacity(0.8)));
  }

  void _ember(Canvas c) {
    c.drawCircle(Offset.zero, 40, _fill(const Color(0xFFFFF3E0).withOpacity(0.25)));
    c.drawCircle(Offset.zero, 44, _stroke(const Color(0xFFBF6A2C), 3));
    c.save();
    c.translate(0, 2);
    c.scale(0.85);
    c.drawPath(_flameOuter(),
        _fillS(_lin(const [Color(0xFFFFB74D), Color(0xFFE65100)])));
    c.drawPath(_flameInner(), _fill(const Color(0xFFFFE0B2)));
    c.restore();
  }

  void _flare(Canvas c) {
    final g = _lin(const [Color(0xFFECEFF1), Color(0xFF78909C)]);
    c.drawPath(_rays(8, 26, 50, 0.22, rot: 22.5), _fillS(g));
    c.drawCircle(Offset.zero, 24, _fillS(g));
    c.drawCircle(Offset.zero, 24, _stroke(const Color(0xFF546E7A), 3));
    c.drawCircle(Offset.zero, 13, _fill(Colors.white.withOpacity(0.85)));
    c.drawCircle(Offset.zero, 52, _stroke(const Color(0xFF90A4AE), 2));
  }

  void _beacon(Canvas c) {
    final gold = _lin(const [Color(0xFFFFE082), Color(0xFFFF8F00)]);
    for (final dir in [1.0, -1.0]) {
      c.save();
      c.scale(dir, 1);
      c.drawPath(_wing(), _fillS(gold));
      c.drawPath(_wing(), _stroke(const Color(0xFFB26A00), 1.5));
      c.restore();
    }
    c.drawPath(_shield(), _fill(const Color(0xFFFFF8E1)));
    c.drawPath(_shield(), _strokeS(gold, 6));
    c.save();
    c.translate(0, 2);
    c.drawPath(_rays(8, 11, 22, 0.3), _fillS(gold));
    c.drawCircle(Offset.zero, 10, _fillS(gold));
    c.restore();
  }

  void _radiant(Canvas c) {
    final gold = _lin(const [Color(0xFFFFE082), Color(0xFFFF8F00)]);
    final teal = _lin(const [Color(0xFF80DEEA), Color(0xFF00838F)]);
    c.drawPath(_rays(16, 34, 62, 0.12, alt: 48), _fillS(gold));
    c.drawCircle(Offset.zero, 36, _fill(const Color(0xFFE0F7FA)));
    c.drawCircle(Offset.zero, 36, _strokeS(teal, 6));
    c.drawCircle(Offset.zero, 28, _stroke(const Color(0xFFFFB300), 2));
    c.drawPath(_star(8, 22, 10), _fillS(gold));
    c.drawCircle(Offset.zero, 6, _fill(Colors.white));
    for (var a = -90; a < 270; a += 45) {
      final r = a * math.pi / 180;
      final o = Offset(58 * math.cos(r), 58 * math.sin(r));
      c.drawCircle(o, 4, _fill(const Color(0xFF80DEEA)));
      c.drawCircle(o, 4, _stroke(const Color(0xFF006064), 1.2));
    }
  }

  void _solstice(Canvas c) {
    final prism = _lin(const [
      Color(0xFFFFF176),
      Color(0xFFFF9800),
      Color(0xFFE91E63),
      Color(0xFF7C4DFF),
    ], const [
      0,
      0.35,
      0.7,
      1
    ]);
    c.drawCircle(
      Offset.zero,
      76,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xB3FFD54F), Color(0x00FFD54F)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 76)),
    );
    c.drawPath(_rays(24, 40, 72, 0.1, alt: 56), _fillS(prism));
    c.drawPath(_rays(12, 36, 58, 0.16, rot: 15), _fill(const Color(0xFFFFF59D)));
    c.drawCircle(Offset.zero, 44, _fill(const Color(0xFF1A1033)));
    c.drawCircle(Offset.zero, 44, _strokeS(prism, 6));
    // dashed inner ring
    final dash = _stroke(const Color(0xFFFFD54F), 1.5);
    for (var k = 0; k < 32; k++) {
      c.drawArc(Rect.fromCircle(center: Offset.zero, radius: 36),
          k * 2 * math.pi / 32, 2 * math.pi / 32 * 0.43, false, dash);
    }
    c.drawPath(_star(12, 28, 15), _fillS(prism));
    c.drawCircle(Offset.zero, 11, _fill(Colors.white));
    c.drawCircle(Offset.zero, 6, _fill(const Color(0xFFFFD54F)));
    for (var a = 0; a < 360; a += 30) {
      final r = (a + 10) * math.pi / 180;
      c.drawCircle(Offset(70 * math.cos(r), 70 * math.sin(r)), 3,
          _fill(Colors.white));
    }
  }

  @override
  bool shouldRepaint(covariant _RankPainter old) => old.index != index;
}