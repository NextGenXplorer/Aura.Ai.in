import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Handles incoming shared text/URLs from other Android apps.
/// AURA registers as a share target — users can share articles, text,
/// or URLs from any app and AURA will summarize them using the local LLM.
class ShareReceiverService {
  static const MethodChannel _channel = MethodChannel('com.aura.mobile/share');
  static final StreamController<SharedContent> _contentController =
      StreamController<SharedContent>.broadcast();

  /// Stream of incoming shared content from other apps.
  static Stream<SharedContent> get incomingContent => _contentController.stream;

  /// The most recent shared content (for when the app is cold-started via share).
  static SharedContent? pendingContent;

  /// Initialize the share receiver — call once at app startup.
  static void initialize() {
    _channel.setMethodCallHandler(_handleMethod);
    // Check if app was launched with shared content
    _checkInitialShare();
  }

  static Future<void> _checkInitialShare() async {
    try {
      final result = await _channel.invokeMethod('getInitialShare');
      if (result != null && result is Map) {
        final content = SharedContent.fromMap(Map<String, dynamic>.from(result));
        if (content.text.isNotEmpty || content.url.isNotEmpty) {
          pendingContent = content;
          _contentController.add(content);
        }
      }
    } catch (e) {
      debugPrint('ShareReceiver: No initial share data: $e');
    }
  }

  static Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onSharedContent':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final content = SharedContent.fromMap(args);
        pendingContent = content;
        _contentController.add(content);
        debugPrint('ShareReceiver: Received shared content: ${content.type}');
        break;
    }
  }

  /// Clear pending content after it's been processed.
  static void clearPending() {
    pendingContent = null;
  }

  static void dispose() {
    _contentController.close();
  }
}

/// Represents content shared from another app to AURA.
class SharedContent {
  final String text;
  final String url;
  final String? title;
  final SharedContentType type;

  const SharedContent({
    required this.text,
    required this.url,
    this.title,
    required this.type,
  });

  factory SharedContent.fromMap(Map<String, dynamic> map) {
    final text = map['text'] as String? ?? '';
    final url = _extractUrl(text);

    SharedContentType type;
    if (url.isNotEmpty) {
      type = SharedContentType.url;
    } else if (text.length > 500) {
      type = SharedContentType.article;
    } else {
      type = SharedContentType.shortText;
    }

    return SharedContent(
      text: text,
      url: url,
      title: map['title'] as String?,
      type: type,
    );
  }

  static String _extractUrl(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+',
      caseSensitive: false,
    );
    final match = urlRegex.firstMatch(text);
    return match?.group(0) ?? '';
  }

  bool get isEmpty => text.isEmpty && url.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

enum SharedContentType {
  shortText,
  article,
  url,
}
