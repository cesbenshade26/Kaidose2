import 'package:flutter/material.dart';
import 'dart:math' as math;

class AssignMemberRole {
  static bool _isAssignMode = false;

  static bool get isAssignMode => _isAssignMode;

  static void enterAssignMode() {
    _isAssignMode = true;
  }

  static void exitAssignMode() {
    _isAssignMode = false;
  }
}

// Wiggle Animation Widget for Member Cards
class WiggleMemberCard extends StatefulWidget {
  final String memberName;
  final Widget child;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  const WiggleMemberCard({
    Key? key,
    required this.memberName,
    required this.child,
    this.onDragStarted,
    this.onDragEnd,
  }) : super(key: key);

  @override
  State<WiggleMemberCard> createState() => _WiggleMemberCardState();
}

class _WiggleMemberCardState extends State<WiggleMemberCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _rotationAnimation = Tween<double>(
      begin: -0.02,
      end: 0.02,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AssignMemberRole.isAssignMode) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotationAnimation.value,
          child: Draggable<String>(
            data: widget.memberName,
            feedback: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Opacity(
                opacity: 0.8,
                child: Container(
                  width: 300,
                  child: widget.child,
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: widget.child,
            ),
            onDragStarted: widget.onDragStarted,
            onDragEnd: (details) {
              if (widget.onDragEnd != null) {
                widget.onDragEnd!();
              }
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

// Wiggle Animation for Tier Drop Zones
class WiggleTierDropZone extends StatefulWidget {
  final String tierName;
  final int tierIndex;
  final Widget child;
  final Function(String memberName, int tierIndex) onMemberDropped;

  const WiggleTierDropZone({
    Key? key,
    required this.tierName,
    required this.tierIndex,
    required this.child,
    required this.onMemberDropped,
  }) : super(key: key);

  @override
  State<WiggleTierDropZone> createState() => _WiggleTierDropZoneState();
}

class _WiggleTierDropZoneState extends State<WiggleTierDropZone>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(-0.003, 0),
      end: const Offset(0.003, 0),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    if (AssignMemberRole.isAssignMode) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(WiggleTierDropZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (AssignMemberRole.isAssignMode && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!AssignMemberRole.isAssignMode && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AssignMemberRole.isAssignMode) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SlideTransition(
          position: _offsetAnimation,
          child: DragTarget<String>(
            onWillAccept: (data) {
              setState(() {
                _isHovering = true;
              });
              return data != null;
            },
            onLeave: (data) {
              setState(() {
                _isHovering = false;
              });
            },
            onAccept: (memberName) {
              setState(() {
                _isHovering = false;
              });
              widget.onMemberDropped(memberName, widget.tierIndex);
            },
            builder: (context, candidateData, rejectedData) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _isHovering
                      ? Colors.cyan.withOpacity(0.1)
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isHovering
                        ? Colors.cyan
                        : Colors.grey[300]!,
                    width: _isHovering ? 2 : 1,
                  ),
                ),
                child: widget.child,
              );
            },
          ),
        );
      },
    );
  }
}

// Exit Button for Assign Mode
class ExitAssignModeButton extends StatelessWidget {
  final VoidCallback onExit;

  const ExitAssignModeButton({
    Key? key,
    required this.onExit,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!AssignMemberRole.isAssignMode) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 10,
      right: 10,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onExit,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.cyan,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Done',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 4),
                Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Banner showing assign mode is active
class AssignModeBanner extends StatelessWidget {
  const AssignModeBanner({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!AssignMemberRole.isAssignMode) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: Colors.cyan,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: Colors.cyan,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Drag members to tiers to assign roles',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.cyan[900],
              ),
            ),
          ),
        ],
      ),
    );
  }
}