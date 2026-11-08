import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'MediaPreloader.dart';

/// Flip through the photos of a photo clip by spreading light.
///
/// Drag sideways and the next photo is revealed inside a growing circle of
/// light that starts under your finger; let go past the halfway-ish point (or
/// flick) and the light floods the whole screen, otherwise it shrinks back.
/// A row of dots at the top lights up as you go: photos you've seen stay lit,
/// the one you're on glows.
///
/// Only horizontal drags are used, so a parent that scrolls vertically (the
/// clip viewer) and taps/double-taps keep working.
class PhotoFlipper extends StatefulWidget {
  final List<String> urls;
  final ValueChanged<int>? onChanged;

  const PhotoFlipper({Key? key, required this.urls, this.onChanged})
      : super(key: key);

  @override
  State<PhotoFlipper> createState() => _PhotoFlipperState();
}

class _PhotoFlipperState extends State<PhotoFlipper>
    with SingleTickerProviderStateMixin {
  static const Color _glow = Color(0xFFFFB300);

  late final AnimationController _anim; // 0..1: how far the light has spread
  int _index = 0;
  final Set<int> _seen = {0};
  int _dir = 0; // +1 revealing the next photo, -1 the previous one
  Offset _origin = Offset.zero;
  double _dragDx = 0;
  double _width = 1;
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
    _warmAround();
  }

  @override
  void didUpdateWidget(PhotoFlipper old) {
    super.didUpdateWidget(old);
    if (old.urls.length != widget.urls.length ||
        (widget.urls.isNotEmpty &&
            old.urls.isNotEmpty &&
            old.urls.first != widget.urls.first)) {
      _index = _index.clamp(0, math.max(0, widget.urls.length - 1));
      _seen
        ..clear()
        ..add(_index);
      _anim.value = 0;
      _dir = 0;
      _warmAround();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _warmAround() {
    final u = widget.urls;
    final wanted = <String>[];
    for (final i in [_index + 1, _index - 1, _index + 2]) {
      if (i >= 0 && i < u.length) wanted.add(u[i]);
    }
    PreloadedMediaPool.instance.warmImages(wanted);
  }

  // ─── Drag ─────────────────────────────────────────────────────────────────

  void _onStart(DragStartDetails d) {
    if (_settling || widget.urls.length < 2) return;
    _origin = d.localPosition;
    _dragDx = 0;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_settling || widget.urls.length < 2) return;
    _dragDx += d.delta.dx;
    final dir = _dragDx == 0 ? 0 : (_dragDx < 0 ? 1 : -1);
    final target = _index + dir;
    if (dir == 0 || target < 0 || target >= widget.urls.length) {
      // Nothing that way (first/last photo): the light doesn't spread.
      if (_dir != 0 || _anim.value != 0) {
        setState(() {
          _dir = 0;
          _anim.value = 0;
        });
      }
      return;
    }
    final p = (_dragDx.abs() / (_width * 0.4)).clamp(0.0, 1.0);
    setState(() {
      _dir = dir;
      _anim.value = p;
    });
  }

  void _onEnd(DragEndDetails d) {
    if (_settling) return;
    if (_dir == 0) {
      _anim.value = 0;
      return;
    }
    final v = d.primaryVelocity ?? 0; // negative = flicking left = next
    final flick = (_dir == 1 && v < -500) || (_dir == -1 && v > 500);
    final commit = _anim.value > 0.22 || flick;
    _settle(commit);
  }

  void _onCancel() {
    if (!_settling && _dir != 0) _settle(false);
  }

  void _settle(bool commit) {
    _settling = true;
    final remaining = commit ? 1 - _anim.value : _anim.value;
    final ms = (80 + 140 * remaining).round();
    _anim
        .animateTo(
      commit ? 1.0 : 0.0,
      duration: Duration(milliseconds: ms),
      curve: commit ? Curves.easeOut : Curves.easeOut,
    )
        .whenComplete(() {
      if (!mounted) return;
      setState(() {
        if (commit) {
          _index += _dir;
          _seen.add(_index);
        }
        _dir = 0;
        _anim.value = 0;
        _settling = false;
      });
      if (commit) {
        widget.onChanged?.call(_index);
        _warmAround();
      }
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  Widget _photo(int i) {
    final url = widget.urls[i];
    return SizedBox.expand(
      key: ValueKey('photo-$i-$url'),
      child: Image(
        image: PreloadedMediaPool.imageProvider(url),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) {
          if (sync) return child;
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: child,
              ),
            ],
          );
        },
        errorBuilder: (_, __, ___) => Container(
          color: Colors.black,
          child: Center(
            child: Icon(Icons.broken_image_outlined,
                color: Colors.grey[600], size: 48),
          ),
        ),
      ),
    );
  }

  Widget _dots() {
    final n = widget.urls.length;
    if (n < 2) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 14,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < n; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == _index
                      ? _glow
                      : (_seen.contains(i)
                      ? _glow.withOpacity(0.55)
                      : Colors.white.withOpacity(0.3)),
                  boxShadow: i == _index
                      ? [
                    BoxShadow(
                      color: _glow.withOpacity(0.7),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                      : const [],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text('Could not load clip',
              style: TextStyle(color: Colors.grey[500])),
        ),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      _width = box.maxWidth.isFinite && box.maxWidth > 0 ? box.maxWidth : 1;
      final size = Size(_width, box.maxHeight.isFinite ? box.maxHeight : 1);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _onStart,
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: _onEnd,
        onHorizontalDragCancel: _onCancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _photo(_index),
            AnimatedBuilder(
              animation: _anim,
              builder: (context, _) {
                final p = _anim.value;
                final target = _index + _dir;
                if (_dir == 0 ||
                    p <= 0 ||
                    target < 0 ||
                    target >= widget.urls.length) {
                  return const SizedBox.shrink();
                }
                // Big enough to reach the farthest corner from the finger.
                final corners = [
                  Offset.zero,
                  Offset(size.width, 0),
                  Offset(0, size.height),
                  Offset(size.width, size.height),
                ];
                final maxR = corners
                    .map((c) => (c - _origin).distance)
                    .reduce(math.max);
                final radius = p * maxR;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipPath(
                      clipper: _CircleClipper(_origin, radius),
                      child: _photo(target),
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _RingPainter(_origin, radius, p),
                      ),
                    ),
                  ],
                );
              },
            ),
            _dots(),
          ],
        ),
      );
    });
  }
}

class _CircleClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;
  _CircleClipper(this.center, this.radius);

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.center != center || old.radius != radius;
}

/// A soft warm edge on the spreading circle, fading out as it fills the screen.
class _RingPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double progress;
  _RingPainter(this.center, this.radius, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final fade = (1 - progress).clamp(0.0, 1.0);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFFFE082).withOpacity(0.55 * fade);
    canvas.drawCircle(center, radius, line);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.center != center ||
          old.radius != radius ||
          old.progress != progress;
}