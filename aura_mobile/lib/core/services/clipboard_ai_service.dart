import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aura_mobile/features/orchestrator/orchestrator_service.dart';
import 'package:aura_mobile/presentation/providers/clipboard_bubble_provider.dart';
import 'package:aura_mobile/presentation/providers/chat_provider.dart';
import 'package:aura_mobile/features/automation/application/automation_engine.dart';

final clipboardAiServiceProvider = Provider((ref) {
  return ClipboardAiService(ref);
});

/// Content types detected from clipboard text.
enum ClipboardContentType {
  url,
  phone,
  email,
  code,
  address,
  text;

  /// Parse from the string sent by the native side.
  static ClipboardContentType fromString(String value) {
    return ClipboardContentType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ClipboardContentType.text,
    );
  }
}

/// A single suggested action for a clipboard item.
class ClipboardAction {
  final String label;
  final String actionId;
  final String? description;

  const ClipboardAction({
    required this.label,
    required this.actionId,
    this.description,
  });
}

/// Holds the latest clipboard event received from native.
class ClipboardEvent {
  final String text;
  final ClipboardContentType type;
  final DateTime timestamp;

  const ClipboardEvent({
    required this.text,
    required this.type,
    required this.timestamp,
  });
}

class ClipboardAiService {
  static const _channel = MethodChannel('com.aura.ai/clipboard');
  static const _prefKey = 'clipboard_ai_enabled';

  final Ref _ref;

  /// The most recent clipboard event, or null if nothing has been captured yet.
  ClipboardEvent? _lastEvent;
  ClipboardEvent? get lastEvent => _lastEvent;

  /// Whether the feature is enabled (persisted via SharedPreferences).
  bool _enabled = true;
  bool get isEnabled => _enabled;

  /// Whether the native clipboard monitor is currently active.
  bool _monitorActive = false;
  bool get isMonitorActive => _monitorActive;

  ClipboardAiService(this._ref) {
    _init();
  }

  // ------------------------------------------------------------------
  // Initialization
  // ------------------------------------------------------------------

  Future<void> _init() async {
    // Load persisted preference
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? true;

    // Register method-call handler for events coming from native Kotlin side
    _channel.setMethodCallHandler(_handleMethodCall);

    // Auto-enable native monitor if the feature is enabled
    if (_enabled) {
      await enableMonitor(true);
    }

    debugPrint('CLIPBOARD_AI: Initialized (enabled=$_enabled)');

    // Query for any pending PROCESS_TEXT intent from cold startup
    try {
      final pending = await _channel.invokeMethod<String>('getPendingProcessText');
      if (pending != null && pending.isNotEmpty) {
        debugPrint('CLIPBOARD_AI: Cold startup PROCESS_TEXT found: "$pending"');
        Future.delayed(const Duration(milliseconds: 1000), () {
          _ref.read(chatProvider.notifier).sendMessage(pending);
        });
      }
    } catch (e) {
      debugPrint('CLIPBOARD_AI: Failed to get pending process text: $e');
    }
  }

  // ------------------------------------------------------------------
  // Enable / Disable
  // ------------------------------------------------------------------

  /// Persist the enabled preference and start/stop the native monitor.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    await enableMonitor(value);
    debugPrint('CLIPBOARD_AI: Enabled set to $value');
  }

  /// Tell the native side to start or stop the ClipboardMonitorService.
  Future<void> enableMonitor(bool enable) async {
    try {
      await _channel.invokeMethod('enableClipboardMonitor', enable);
      _monitorActive = enable;
    } on PlatformException catch (e) {
      debugPrint('CLIPBOARD_AI: Failed to toggle monitor: ${e.message}');
    }
  }

  /// Query the native side for the current monitor status.
  Future<bool> checkMonitorActive() async {
    try {
      final bool active =
          await _channel.invokeMethod('isClipboardMonitorActive');
      _monitorActive = active;
      return active;
    } on PlatformException catch (e) {
      debugPrint('CLIPBOARD_AI: Failed to check monitor: ${e.message}');
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Native -> Flutter bridge
  // ------------------------------------------------------------------

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onClipboardContent':
        if (!_enabled) return;
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final content = (args['content'] as String?) ?? '';
        final contentType = (args['contentType'] as String?) ?? 'text';
        if (content.isEmpty) return;

        final type = ClipboardContentType.fromString(contentType);
        _lastEvent = ClipboardEvent(
          text: content,
          type: type,
          timestamp: DateTime.now(),
        );

        debugPrint(
          'CLIPBOARD_AI: Received content — type=${type.name}, '
          'text=${content.length > 80 ? '${content.substring(0, 80)}...' : content}',
        );

        // Trigger the clipboard bubble overlay
        try {
          _ref.read(clipboardBubbleProvider.notifier).showBubble(_lastEvent!);
        } catch (e) {
          debugPrint('CLIPBOARD_AI: Failed to show bubble: $e');
        }

        try {
          _ref.read(automationEngineProvider).checkAndTriggerClipboardFlows(content);
        } catch (e) {
          debugPrint('CLIPBOARD_AI: Failed to trigger automation: $e');
        }
        break;

      case 'onProcessTextIntent':
        final content = call.arguments as String? ?? '';
        if (content.isEmpty) return;
        debugPrint('CLIPBOARD_AI: Received PROCESS_TEXT intent: "$content"');

        Future.delayed(const Duration(milliseconds: 600), () {
          _ref.read(chatProvider.notifier).sendMessage(content);
        });
        break;

      default:
        debugPrint('CLIPBOARD_AI: Unknown method ${call.method}');
    }
  }

  // ------------------------------------------------------------------
  // Suggested actions
  // ------------------------------------------------------------------

  /// Returns a list of contextual actions for the given content type.
  List<ClipboardAction> getSuggestedActions(ClipboardContentType type) {
    switch (type) {
      case ClipboardContentType.url:
        return const [
          ClipboardAction(
            label: 'Summarize Page',
            actionId: 'summarize_url',
            description: 'Use AI to summarize the web page content',
          ),
          ClipboardAction(
            label: 'Open in Browser',
            actionId: 'open_url',
            description: 'Open the URL in the default browser',
          ),
          ClipboardAction(
            label: 'Save to Memory',
            actionId: 'save_memory',
            description: 'Store this link in AURA memory',
          ),
        ];

      case ClipboardContentType.phone:
        return const [
          ClipboardAction(
            label: 'Call Number',
            actionId: 'call_phone',
            description: 'Dial the phone number',
          ),
          ClipboardAction(
            label: 'Send SMS',
            actionId: 'send_sms',
            description: 'Open SMS composer for this number',
          ),
          ClipboardAction(
            label: 'Save Contact',
            actionId: 'save_contact',
            description: 'Save as a new contact',
          ),
        ];

      case ClipboardContentType.email:
        return const [
          ClipboardAction(
            label: 'Compose Email',
            actionId: 'compose_email',
            description: 'Draft an email to this address',
          ),
          ClipboardAction(
            label: 'Save Contact',
            actionId: 'save_contact',
            description: 'Save as a new contact',
          ),
        ];

      case ClipboardContentType.code:
        return const [
          ClipboardAction(
            label: 'Explain Code',
            actionId: 'explain_code',
            description: 'Ask AI to explain this code snippet',
          ),
          ClipboardAction(
            label: 'Improve Code',
            actionId: 'improve_code',
            description: 'Ask AI to suggest improvements',
          ),
          ClipboardAction(
            label: 'Save Snippet',
            actionId: 'save_memory',
            description: 'Store this snippet in AURA memory',
          ),
        ];

      case ClipboardContentType.address:
        return const [
          ClipboardAction(
            label: 'Navigate',
            actionId: 'navigate_address',
            description: 'Open in Maps for navigation',
          ),
          ClipboardAction(
            label: 'Save to Memory',
            actionId: 'save_memory',
            description: 'Store this address in AURA memory',
          ),
        ];

      case ClipboardContentType.text:
        return const [
          ClipboardAction(
            label: 'Summarize',
            actionId: 'summarize_text',
            description: 'Use AI to summarize the copied text',
          ),
          ClipboardAction(
            label: 'Translate',
            actionId: 'translate_text',
            description: 'Translate the text to another language',
          ),
          ClipboardAction(
            label: 'Save to Memory',
            actionId: 'save_memory',
            description: 'Store this text in AURA memory',
          ),
        ];
    }
  }

  // ------------------------------------------------------------------
  // Action execution — routes through OrchestratorService
  // ------------------------------------------------------------------

  /// Execute a suggested action by its [actionId] using the current [_lastEvent].
  /// Returns a stream of AI response chunks for actions that involve AI processing,
  /// or null for actions that are dispatched directly (call, SMS, email, navigate).
  Stream<String>? executeAction(String actionId) {
    final event = _lastEvent;
    if (event == null) {
      debugPrint('CLIPBOARD_AI: No clipboard event to act on');
      return null;
    }

    debugPrint('CLIPBOARD_AI: Executing action=$actionId');

    switch (actionId) {
      case 'summarize_url':
        return _routeToOrchestrator(
          'Summarize the content at this URL: ${event.text}',
        );

      case 'open_url':
        _invokeAppControl('openApp', {'appName': 'navigate:${event.text}'});
        return null;

      case 'call_phone':
        _invokeAppControl('callPhoneDirect', {'number': event.text});
        return null;

      case 'send_sms':
        _invokeAppControl('sendSMS', {'name': event.text, 'message': ''});
        return null;

      case 'compose_email':
        _invokeAppControl('launchEmailApp', {
          'address': event.text,
          'subject': '',
          'body': '',
        });
        return null;

      case 'save_contact':
        return _routeToOrchestrator(
          'Save this as a new contact: ${event.text}',
        );

      case 'explain_code':
        return _routeToOrchestrator(
          'Explain the following code snippet:\n\n${event.text}',
        );

      case 'improve_code':
        return _routeToOrchestrator(
          'Suggest improvements for this code:\n\n${event.text}',
        );

      case 'navigate_address':
        _invokeAppControl('openApp', {'appName': 'navigate:${event.text}'});
        return null;

      case 'summarize_text':
        return _routeToOrchestrator(
          'Summarize the following:\n\n${event.text}',
        );

      case 'translate_text':
        return _routeToOrchestrator(
          'Translate the following text to English:\n\n${event.text}',
        );

      case 'save_memory':
        return _routeToOrchestrator(
          'Remember this for me: ${event.text}',
        );

      default:
        debugPrint('CLIPBOARD_AI: Unknown action $actionId');
        return null;
    }
  }

  // ------------------------------------------------------------------
  // Internal helpers
  // ------------------------------------------------------------------

  /// Route a prompt through the OrchestratorService and return the response stream.
  Stream<String> _routeToOrchestrator(String message) {
    final orchestrator = _ref.read(orchestratorServiceProvider);
    return orchestrator.processMessage(
      message: message,
      chatHistory: [],
      hasDocuments: false,
      isVoiceQuery: false,
    );
  }

  /// Fire-and-forget call to the native app_control channel.
  Future<void> _invokeAppControl(
      String method, Map<String, String> args) async {
    try {
      const appControl = MethodChannel('com.aura.ai/app_control');
      await appControl.invokeMethod(method, args);
    } on PlatformException catch (e) {
      debugPrint('CLIPBOARD_AI: App control error ($method): ${e.message}');
    }
  }
}
