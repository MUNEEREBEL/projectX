import 'dart:io';
import 'package:flutter/services.dart';

class OverlayService {
  static const MethodChannel _channel = MethodChannel('com.example.x/storage_channel');

  static Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool result = await _channel.invokeMethod('canDrawOverlays') ?? false;
      return result;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestOverlayPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool result = await _channel.invokeMethod('requestOverlayPermission') ?? false;
      return result;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> startAssistiveBall() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool result = await _channel.invokeMethod('startAssistiveBall') ?? false;
      return result;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stopAssistiveBall() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool result = await _channel.invokeMethod('stopAssistiveBall') ?? false;
      return result;
    } catch (_) {
      return false;
    }
  }

  static void registerCopilotTriggerCallback(Function() onOpen) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenCopilotRequested') {
        onOpen();
      }
    });
  }
}
