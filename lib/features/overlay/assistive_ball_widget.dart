import 'dart:async';
import 'package:flutter/material.dart';
import 'assistive_ball_dialog.dart';

class AssistiveBallWidget extends StatefulWidget {
  final Widget child;

  const AssistiveBallWidget({super.key, required this.child});

  @override
  State<AssistiveBallWidget> createState() => _AssistiveBallWidgetState();
}

class _AssistiveBallWidgetState extends State<AssistiveBallWidget> with SingleTickerProviderStateMixin {
  Offset _position = const Offset(20, 320);
  bool _isDocked = false;
  bool _isDragging = false;
  Timer? _dockTimer;

  @override
  void initState() {
    super.initState();
    _startDockTimer();
  }

  void _startDockTimer() {
    _dockTimer?.cancel();
    _dockTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isDragging) {
        setState(() => _isDocked = true);
      }
    });
  }

  void _wakeUp() {
    _dockTimer?.cancel();
    if (_isDocked) {
      setState(() => _isDocked = false);
    }
    _startDockTimer();
  }

  @override
  void dispose() {
    _dockTimer?.cancel();
    super.dispose();
  }

  void _snapToNearestEdge(Size screenSize) {
    const ballSize = 54.0;
    final middleX = screenSize.width / 2;

    double targetX;
    if (_position.dx < middleX) {
      targetX = 8.0; // Snap to left edge
    } else {
      targetX = screenSize.width - ballSize - 8.0; // Snap to right edge
    }

    // Keep within vertical bounds
    final targetY = _position.dy.clamp(80.0, screenSize.height - ballSize - 100.0);

    setState(() {
      _position = Offset(targetX, targetY);
      _isDragging = false;
    });

    _startDockTimer();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isNearRight = _position.dx > screenSize.width / 2;

    // Offset when docked: semi-hidden into edge
    double displayX = _position.dx;
    if (_isDocked) {
      displayX = isNearRight ? screenSize.width - 22.0 : -32.0;
    }

    return Stack(
      children: [
        widget.child,

        // Floating Assistive Ball / Edge Smart Panel Handle
        AnimatedPositioned(
          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          left: displayX,
          top: _position.dy,
          child: GestureDetector(
            onPanStart: (_) {
              _dockTimer?.cancel();
              setState(() {
                _isDragging = true;
                _isDocked = false;
              });
            },
            onPanUpdate: (details) {
              setState(() {
                double newX = _position.dx + details.delta.dx;
                double newY = _position.dy + details.delta.dy;
                newX = newX.clamp(-10.0, screenSize.width - 44.0);
                newY = newY.clamp(60.0, screenSize.height - 120.0);
                _position = Offset(newX, newY);
              });
            },
            onPanEnd: (_) => _snapToNearestEdge(screenSize),
            onTap: () {
              if (_isDocked) {
                _wakeUp();
              } else {
                _wakeUp();
                AssistiveBallDialog.show(context);
              }
            },
            child: Material(
              color: Colors.transparent,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isDocked ? 0.45 : 1.0,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFFFFF),
                        Color(0xFFEFF6FF),
                        Color(0xFFE0F2FE),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white,
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withValues(alpha: _isDocked ? 0.15 : 0.45),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.10),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _buildShieldXIcon(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Shield Icon with 'X' inside matching reference mockup
  Widget _buildShieldXIcon() {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Icon(
            Icons.shield_outlined,
            color: Color(0xFF475569),
            size: 26,
          ),
          Text(
            'X',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}
