import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GuardianOverlayService {
  GuardianOverlayService._();

  static bool _starting = false;
  static const _overlayPreferenceKey = 'enable_overlay_bubble_v2';

  static Future<void> ensureStarted() async {
    if (!Platform.isAndroid || _starting) return;

    _starting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_overlayPreferenceKey) ?? false;
      if (!enabled) {
        await close();
        return;
      }

      var granted = await FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        granted = await FlutterOverlayWindow.requestPermission() ?? false;
      }
      if (!granted) return;

      final active = await FlutterOverlayWindow.isActive();
      if (active) return;

      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: 'Shakti Guardian',
        overlayContent: 'Tap for emergency help',
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        height: 92,
        width: 92,
      );
    } catch (e) {
      debugPrint('Guardian overlay unavailable: $e');
    } finally {
      _starting = false;
    }
  }

  static Future<void> close() async {
    if (!Platform.isAndroid) return;
    try {
      final active = await FlutterOverlayWindow.isActive();
      if (active) await FlutterOverlayWindow.closeOverlay();
    } catch (e) {
      debugPrint('Guardian overlay close skipped: $e');
    }
  }
}
