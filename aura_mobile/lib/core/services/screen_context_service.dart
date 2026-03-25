import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final screenContextServiceProvider = Provider((ref) {
  return ScreenContextService(ref);
});

/// Supported screen context actions that can be performed on extracted content.
enum ScreenContextAction {
  summarize,
  extractData,
  translate,
  explain,
  createFlashcards,
}

class ScreenContextService {
  static const _channel = MethodChannel('com.aura.ai/screen_context');
  final Ref _ref;

  ScreenContextService(this._ref) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Handles method calls from the native side.
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'processScreenAction':
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args == null) return;
        final action = args['action'] as String? ?? '';
        final content = args['content'] as String? ?? '';
        if (action.isNotEmpty && content.isNotEmpty) {
          return await _processScreenAction(action, content);
        }
        break;
      default:
        debugPrint('ScreenContext: Unhandled method ${call.method}');
    }
  }

  /// Retrieves the current screen content from the native accessibility service.
  Future<String> getScreenContent() async {
    try {
      final String? content =
          await _channel.invokeMethod<String>('getScreenContent');
      return content ?? '';
    } on PlatformException catch (e) {
      debugPrint('ScreenContext: Failed to get screen content: ${e.message}');
      return '';
    } catch (e) {
      debugPrint('ScreenContext: Unexpected error getting content: $e');
      return '';
    }
  }

  /// Checks whether the accessibility service is currently enabled.
  Future<bool> isAccessibilityEnabled() async {
    try {
      final bool? enabled =
          await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return enabled ?? false;
    } on PlatformException catch (e) {
      debugPrint(
          'ScreenContext: Failed to check accessibility status: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('ScreenContext: Unexpected error checking status: $e');
      return false;
    }
  }

  /// Opens the system accessibility settings so the user can enable the service.
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (e) {
      debugPrint(
          'ScreenContext: Failed to open accessibility settings: ${e.message}');
    } catch (e) {
      debugPrint('ScreenContext: Unexpected error opening settings: $e');
    }
  }

  /// Performs a context-aware action on the current screen content.
  Future<String> performAction(ScreenContextAction action) async {
    final content = await getScreenContent();
    if (content.isEmpty) {
      return 'No screen content available. Please ensure the accessibility service is enabled.';
    }
    return await _processScreenAction(action.name, content);
  }

  /// Processes a screen action by generating a prompt for the AI.
  Future<String> _processScreenAction(String action, String content) async {
    final prompt = _buildPromptForAction(action, content);
    debugPrint('ScreenContext: Processing action "$action" '
        '(${content.length} chars of content)');
    return prompt;
  }

  /// Builds an AI prompt based on the action type and screen content.
  String _buildPromptForAction(String action, String content) {
    switch (action) {
      case 'summarize':
        return 'Please summarize the following screen content concisely:\n\n$content';
      case 'extractData':
        return 'Extract all key data points, names, numbers, dates, and '
            'important information from the following screen content:\n\n$content';
      case 'translate':
        return 'Translate the following screen content to English. If it is '
            'already in English, translate it to the most likely target '
            'language based on context:\n\n$content';
      case 'explain':
        return 'Explain the following screen content in simple, easy-to-understand '
            'terms:\n\n$content';
      case 'createFlashcards':
        return 'Create study flashcards (question and answer pairs) from the '
            'following screen content. Format each as '
            '"Q: [question]\\nA: [answer]":\n\n$content';
      default:
        return 'Analyze the following screen content:\n\n$content';
    }
  }
}
