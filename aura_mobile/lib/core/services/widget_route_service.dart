import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:aura_mobile/core/services/app_navigator.dart';

/// Delivers home screen widget taps into the app.
///
/// A widget tap launches `MainActivity` with an `aura_widget_route` extra. That
/// can cold-start the app, so the native side stores the route and this service
/// both listens for a push and polls once at startup — whichever arrives first
/// wins, and the route is consumed exactly once.
class WidgetRouteService {
  WidgetRouteService._();

  static const MethodChannel _channel = MethodChannel('com.aura.mobile/widget');

  /// Invoked when the Voice quick action is tapped.
  ///
  /// Set by the chat shell, which owns the microphone. Left null the tap just
  /// opens the app.
  static VoidCallback? onVoiceRequested;

  static bool _initialized = false;

  /// Starts listening for widget routes and drains anything already pending.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWidgetRoute') {
        _handle(call.arguments as String?);
      }
      return null;
    });

    await drainPending();
  }

  /// Asks the native side for a route that arrived before Dart was listening.
  /// Safe to call on resume.
  static Future<void> drainPending() async {
    try {
      final route = await _channel.invokeMethod<String>('getPendingRoute');
      _handle(route);
    } on MissingPluginException {
      // Non-Android platform: nothing to drain.
    } catch (e) {
      debugPrint('WidgetRouteService: pending route check failed: $e');
    }
  }

  static void _handle(String? route) {
    if (route == null || route.isEmpty) return;
    debugPrint('WidgetRouteService: handling widget route "$route"');

    if (route == 'voice') {
      // Bring chat to the front first, then hand off to the mic.
      AppNavigator.open('chat');
      final callback = onVoiceRequested;
      if (callback != null) {
        callback();
      } else {
        debugPrint('WidgetRouteService: no voice handler registered');
      }
      return;
    }

    if (!AppNavigator.open(route)) {
      debugPrint('WidgetRouteService: unknown route "$route"');
    }
  }
}
