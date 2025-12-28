import 'package:flutter/material.dart';

class HomeSwipeDetector extends StatefulWidget {
  final int currentIndex;
  final int totalPages;
  final Function(int) onPageChanged;
  final List<Widget> pages; // Changed from pageBuilder to direct pages list
  final double edgeThreshold;

  const HomeSwipeDetector({
    Key? key,
    required this.currentIndex,
    required this.totalPages,
    required this.onPageChanged,
    required this.pages, // Changed parameter
    this.edgeThreshold = 80.0,
  }) : super(key: key);

  @override
  State<HomeSwipeDetector> createState() => _HomeSwipeDetectorState();
}

class _HomeSwipeDetectorState extends State<HomeSwipeDetector>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  double _dragOffset = 0.0;
  bool _isDragging = false;
  bool _isValidEdgeSwipe = false;
  int? _targetPage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    )..addListener(() {
      setState(() {
        _dragOffset = _animation.value;
      });
    })..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_targetPage != null && _targetPage != widget.currentIndex) {
          widget.onPageChanged(_targetPage!);
          _targetPage = null;
        }
        setState(() {
          _dragOffset = 0.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final startX = details.globalPosition.dx;

    // Check if drag started from edge
    _isValidEdgeSwipe = startX <= widget.edgeThreshold ||
        startX >= screenWidth - widget.edgeThreshold;

    if (_isValidEdgeSwipe) {
      _controller.stop();
      setState(() {
        _isDragging = true;
      });
    }
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || !_isValidEdgeSwipe) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final delta = details.delta.dx;

    setState(() {
      _dragOffset += delta;

      // Constrain drag based on whether there's a page in that direction
      if (_dragOffset > 0 && widget.currentIndex == 0) {
        // At first page, can't go left
        _dragOffset = _dragOffset * 0.3; // Resistance effect
      } else if (_dragOffset < 0 && widget.currentIndex == widget.totalPages - 1) {
        // At last page, can't go right
        _dragOffset = _dragOffset * 0.3; // Resistance effect
      } else {
        // Clamp to screen width
        _dragOffset = _dragOffset.clamp(-screenWidth, screenWidth);
      }
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_isDragging || !_isValidEdgeSwipe) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final velocity = details.primaryVelocity ?? 0;

    // Determine if we should switch pages
    bool shouldSwitch = false;
    int newIndex = widget.currentIndex;

    // Check based on drag distance (threshold: 30% of screen)
    if (_dragOffset.abs() > screenWidth * 0.3) {
      shouldSwitch = true;
    }
    // Or based on velocity (fast swipe)
    else if (velocity.abs() > 500) {
      shouldSwitch = true;
    }

    if (shouldSwitch) {
      if (_dragOffset > 0 && widget.currentIndex > 0) {
        // Swiped right, go to previous page
        newIndex = widget.currentIndex - 1;
        _targetPage = newIndex;
        _animation = Tween<double>(
          begin: _dragOffset,
          end: screenWidth,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      } else if (_dragOffset < 0 && widget.currentIndex < widget.totalPages - 1) {
        // Swiped left, go to next page
        newIndex = widget.currentIndex + 1;
        _targetPage = newIndex;
        _animation = Tween<double>(
          begin: _dragOffset,
          end: -screenWidth,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      } else {
        // Can't go in that direction, bounce back
        _animation = Tween<double>(
          begin: _dragOffset,
          end: 0.0,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      }
    } else {
      // Not enough distance/velocity, bounce back
      _animation = Tween<double>(
        begin: _dragOffset,
        end: 0.0,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    }

    _controller.forward(from: 0.0);

    setState(() {
      _isDragging = false;
      _isValidEdgeSwipe = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isDragging = _dragOffset != 0.0;

    return GestureDetector(
      onHorizontalDragStart: _handleHorizontalDragStart,
      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: Stack(
        children: [
          // Base layer - ALWAYS visible and maintains state
          IndexedStack(
            index: widget.currentIndex,
            sizing: StackFit.expand,
            children: widget.pages,
          ),

          // Animation overlay - only shown during drag
          if (isDragging)
            Positioned.fill(
              child: Stack(
                children: [
                  // White background to cover base layer
                  Positioned.fill(
                    child: Container(color: Colors.white),
                  ),

                  // Previous page (if exists and dragging right)
                  if (widget.currentIndex > 0 && _dragOffset > 0)
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset(_dragOffset - screenWidth, 0),
                        child: IndexedStack(
                          index: widget.currentIndex - 1,
                          sizing: StackFit.expand,
                          children: widget.pages,
                        ),
                      ),
                    ),

                  // Next page (if exists and dragging left)
                  if (widget.currentIndex < widget.totalPages - 1 && _dragOffset < 0)
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset(_dragOffset + screenWidth, 0),
                        child: IndexedStack(
                          index: widget.currentIndex + 1,
                          sizing: StackFit.expand,
                          children: widget.pages,
                        ),
                      ),
                    ),

                  // Current page overlay during drag
                  Positioned.fill(
                    child: Transform.translate(
                      offset: Offset(_dragOffset, 0),
                      child: IndexedStack(
                        index: widget.currentIndex,
                        sizing: StackFit.expand,
                        children: widget.pages,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}