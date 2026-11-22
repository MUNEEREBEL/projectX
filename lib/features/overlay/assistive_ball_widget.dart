import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'assistive_ball_dialog.dart';

class AssistiveBallWidget extends StatefulWidget {
  final Widget child;

  const AssistiveBallWidget({super.key, required this.child});

  @override
  State<AssistiveBallWidget> createState() => _AssistiveBallWidgetState();
}

class _AssistiveBallWidgetState extends State<AssistiveBallWidget> {
  Offset _position = const Offset(16, 240);
  final bool _isVisible = true;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Stack(
      children: [
        widget.child,
        if (_isVisible)
          Positioned(
            left: _position.dx,
            top: _position.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  double newX = _position.dx + details.delta.dx;
                  double newY = _position.dy + details.delta.dy;

                  // Bound within screen
                  newX = newX.clamp(10.0, screenSize.width - 60.0);
                  newY = newY.clamp(60.0, screenSize.height - 120.0);

                  _position = Offset(newX, newY);
                });
              },
              onTap: () => AssistiveBallDialog.show(context),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryColor, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.bolt,
                      color: AppTheme.primaryColor,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
