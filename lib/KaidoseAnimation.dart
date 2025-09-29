// KaidoseAnimation.dart
import 'package:flutter/material.dart';

class KaidoseAnimation extends StatefulWidget {
  final VoidCallback onAnimationComplete;
  final bool fadeOutAtEnd;

  const KaidoseAnimation({
    Key? key,
    required this.onAnimationComplete,
    this.fadeOutAtEnd = false,
  }) : super(key: key);

  @override
  State<KaidoseAnimation> createState() => _KaidoseAnimationState();
}

class _KaidoseAnimationState extends State<KaidoseAnimation>
    with TickerProviderStateMixin {
  late AnimationController _drawController;
  late Animation<double> _drawProgress;

  late AnimationController _fadeController;
  late Animation<double> _fadeOpacity;

  bool moveToTop = false;

  @override
  void initState() {
    super.initState();

    _drawController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    _drawProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _drawController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _startAnimation();
  }

  void _startAnimation() {
    _drawController.forward().whenComplete(() async {
      setState(() {
        moveToTop = true;
      });

      await Future.delayed(const Duration(milliseconds: 2000));

      if (widget.fadeOutAtEnd) {
        // Fade out and then call completion
        _fadeController.forward().whenComplete(() {
          widget.onAnimationComplete();
        });
      } else {
        // Just call completion without fade
        widget.onAnimationComplete();
      }
    });
  }

  @override
  void dispose() {
    _drawController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const titleText = 'Kaidose';
    const slackeyStyle = TextStyle(
      fontFamily: 'Slackey',
      fontSize: 64,
      color: Colors.cyan,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(seconds: 2),
            curve: Curves.easeInOut,
            top: moveToTop ? 80 : MediaQuery.of(context).size.height / 2 - 32,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeOpacity,
              child: AnimatedBuilder(
                animation: _drawProgress,
                builder: (context, child) {
                  return Center(
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: _drawProgress.value,
                        child: Text(titleText, style: slackeyStyle),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}