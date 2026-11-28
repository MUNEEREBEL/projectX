import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import 'assistive_ball_dialog.dart';

class AssistiveBallWidget extends StatefulWidget {
  final Widget child;

  static final ValueNotifier<bool> isEnabled = ValueNotifier<bool>(true);
  static const MethodChannel _storageChannel = MethodChannel('com.example.x/storage_channel');

  const AssistiveBallWidget({super.key, required this.child});

  static Future<bool> canDrawOverlays() async {
    try {
      final bool? res = await _storageChannel.invokeMethod('canDrawOverlays');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> requestOverlayPermission() async {
    try {
      final bool? res = await _storageChannel.invokeMethod('requestOverlayPermission');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> startSystemOverlay() async {
    try {
      await _storageChannel.invokeMethod('startAssistiveBall');
    } catch (_) {}
  }

  static Future<void> stopSystemOverlay() async {
    try {
      await _storageChannel.invokeMethod('stopAssistiveBall');
    } catch (_) {}
  }

  static Future<void> loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('assistive_ball_enabled') ?? false;
    isEnabled.value = enabled;
    if (enabled) {
      final hasPerm = await canDrawOverlays();
      if (hasPerm) {
        await startSystemOverlay();
      }
    }
  }

  static Future<void> setEnabled(bool value) async {
    isEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('assistive_ball_enabled', value);
    if (value) {
      final hasPerm = await canDrawOverlays();
      if (!hasPerm) {
        await requestOverlayPermission();
        return;
      }
      await startSystemOverlay();
    } else {
      await stopSystemOverlay();
    }
  }

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
    AssistiveBallWidget.loadPreference();
    AssistiveBallWidget._storageChannel.setMethodCallHandler((call) async {
      if (call.method == 'openAssistiveDialog') {
        final navCtx = appNavigatorKey.currentContext;
        if (navCtx != null) {
          AssistiveBallDialog.show(navCtx);
        } else if (mounted) {
          AssistiveBallDialog.show(context);
        }
      }
    });
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
    // Only the unified native system overlay is shown, preventing duplicate in-app floating balls
    return widget.child;
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
