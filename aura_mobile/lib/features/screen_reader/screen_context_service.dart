import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge between Android's AccessibilityService and Flutter.
/// Captures text visible on the user's screen (from any app) and provides
/// it to AURA for AI understanding, summarization, and assistance.
///
/// Requires the user to manually enable the accessibility service in
/// Android Settings → Accessibility → AURA Screen Reader.
class ScreenContextService {
  static const MethodChannel _channel = MethodChannel(
    'com.aura.ai/screen_context',
  );

  static final StreamController<ScreenContext> _contextController =
      StreamController<ScreenContext>.broadcast();

  /// Stream of pushed screen-context updates.
  ///
  /// NOTE: capture is request-driven today — the accessibility service keeps
  /// the latest screen state natively and Dart pulls it via
  /// [captureCurrentScreen]. Nothing on the native side calls
  /// `onScreenContextUpdate` yet, so this stream stays idle. It is kept because
  /// the handler is already in place for when native push is added; do not rely
  /// on it for live updates.
  static Stream<ScreenContext> get onScreenContext => _contextController.stream;

  /// The most recent screen context captured.
  static ScreenContext? lastContext;

  /// Whether the accessibility service is currently enabled.
  static bool _isEnabled = false;
  static bool get isEnabled => _isEnabled;

  /// Initialize the MethodChannel listener.
  static void initialize() {
    _channel.setMethodCallHandler(_handleMethod);
    _checkServiceStatus();
  }

  /// Check if the accessibility service is enabled.
  static Future<bool> checkServiceStatus() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isAccessibilityEnabled',
      );
      _isEnabled = result ?? false;
      return _isEnabled;
    } catch (e) {
      debugPrint('ScreenContextService: Failed to check status: $e');
      _isEnabled = false;
      return false;
    }
  }

  static Future<void> _checkServiceStatus() async {
    await checkServiceStatus();
  }

  /// Open Android accessibility settings for the user to enable the service.
  static Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      debugPrint('ScreenContextService: Failed to open settings: $e');
    }
  }

  /// Request a one-time screen capture from the accessibility service.
  static Future<ScreenContext?> captureCurrentScreen() async {
    try {
      final result = await _channel.invokeMethod<Map>('getScreenContent');
      if (result != null) {
        final context = ScreenContext.fromMap(
          Map<String, dynamic>.from(result),
        );
        lastContext = context;
        return context;
      }
    } catch (e) {
      debugPrint('ScreenContextService: Capture failed: $e');
    }
    return null;
  }

  static Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onScreenContextUpdate':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final context = ScreenContext.fromMap(args);
        lastContext = context;
        _contextController.add(context);
        break;

      case 'onServiceStatusChanged':
        _isEnabled = call.arguments as bool? ?? false;
        debugPrint('ScreenContextService: Service status changed: $_isEnabled');
        break;
    }
  }

  static void dispose() {
    _contextController.close();
  }
}

/// Represents text/content captured from the user's screen.
class ScreenContext {
  final String packageName;
  final String appName;
  final String screenText;
  final String? windowTitle;
  final DateTime capturedAt;

  const ScreenContext({
    required this.packageName,
    required this.appName,
    required this.screenText,
    this.windowTitle,
    required this.capturedAt,
  });

  factory ScreenContext.fromMap(Map<String, dynamic> map) {
    return ScreenContext(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? 'Unknown',
      screenText: map['screenText'] as String? ?? '',
      windowTitle: map['windowTitle'] as String?,
      capturedAt: DateTime.now(),
    );
  }

  /// Whether there's meaningful text content on screen.
  bool get hasContent => screenText.trim().length > 10;

  /// Get a brief summary of what's on screen.
  String get preview {
    if (!hasContent) return 'No readable text on screen';
    final text = screenText.trim();
    return text.length > 200 ? '${text.substring(0, 200)}...' : text;
  }
}
