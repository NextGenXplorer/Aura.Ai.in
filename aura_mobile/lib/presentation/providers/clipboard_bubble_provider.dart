import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aura_mobile/core/services/clipboard_ai_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum ClipboardBubbleStatus { hidden, showing, streaming, completed, error }

class ClipboardBubbleData {
  final ClipboardBubbleStatus status;
  final ClipboardEvent? event;
  final List<ClipboardAction> actions;
  final String responseText;
  final String? errorMessage;
  final bool timerSuppressed;

  const ClipboardBubbleData({
    this.status = ClipboardBubbleStatus.hidden,
    this.event,
    this.actions = const [],
    this.responseText = '',
    this.errorMessage,
    this.timerSuppressed = false,
  });

  ClipboardBubbleData copyWith({
    ClipboardBubbleStatus? status,
    ClipboardEvent? event,
    List<ClipboardAction>? actions,
    String? responseText,
    String? errorMessage,
    bool? timerSuppressed,
  }) {
    return ClipboardBubbleData(
      status: status ?? this.status,
      event: event ?? this.event,
      actions: actions ?? this.actions,
      responseText: responseText ?? this.responseText,
      errorMessage: errorMessage ?? this.errorMessage,
      timerSuppressed: timerSuppressed ?? this.timerSuppressed,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final clipboardBubbleProvider =
    StateNotifierProvider<ClipboardBubbleNotifier, ClipboardBubbleData>((ref) {
  return ClipboardBubbleNotifier(ref);
});

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ClipboardBubbleNotifier extends StateNotifier<ClipboardBubbleData> {
  final Ref _ref;
  Timer? _autoDismissTimer;
  StreamSubscription<String>? _responseSubscription;

  ClipboardBubbleNotifier(this._ref) : super(const ClipboardBubbleData());

  // -------------------------------------------------------------------------
  // Pure helpers
  // -------------------------------------------------------------------------

  /// Truncate text for preview display.
  /// If text.length <= [maxLength], return text unchanged.
  /// Otherwise return text.substring(0, maxLength) + '…'
  static String truncatePreview(String text, {int maxLength = 80}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}\u2026';
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Show bubble for a new clipboard event.
  ///
  /// If the bubble is currently visible, dismiss first then show the new event
  /// after a brief delay (500 ms) so the user perceives the transition.
  /// Sets state to [ClipboardBubbleStatus.showing], populates actions, and
  /// starts an 8-second auto-dismiss timer.
  void showBubble(ClipboardEvent event) {
    if (state.status != ClipboardBubbleStatus.hidden) {
      // Dismiss current bubble, then re-show with new event.
      dismiss();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _presentBubble(event);
      });
    } else {
      _presentBubble(event);
    }
  }

  /// Execute an action by [actionId].
  ///
  /// Calls [ClipboardAiService.executeAction]. If the result is a
  /// [Stream<String>], switches to [ClipboardBubbleStatus.streaming],
  /// suppresses the auto-dismiss timer, and accumulates tokens into
  /// [ClipboardBubbleData.responseText].
  ///
  /// On stream done → [ClipboardBubbleStatus.completed].
  /// On stream error → [ClipboardBubbleStatus.error] with message.
  ///
  /// If the result is `null` (direct dispatch action), dismiss immediately.
  Future<void> executeAction(String actionId) async {
    final service = _ref.read(clipboardAiServiceProvider);
    final stream = service.executeAction(actionId);

    if (stream == null) {
      // Direct dispatch action (call, navigate, etc.) — dismiss bubble.
      dismiss();
      return;
    }

    // Switch to streaming state, suppress auto-dismiss.
    _cancelTimers();
    state = state.copyWith(
      status: ClipboardBubbleStatus.streaming,
      responseText: '',
      timerSuppressed: true,
      errorMessage: null,
    );

    _responseSubscription = stream.listen(
      (token) {
        if (!mounted) return;
        state = state.copyWith(
          responseText: state.responseText + token,
        );
      },
      onDone: () {
        if (!mounted) return;
        state = state.copyWith(
          status: ClipboardBubbleStatus.completed,
        );
      },
      onError: (Object error) {
        if (!mounted) return;
        state = state.copyWith(
          status: ClipboardBubbleStatus.error,
          errorMessage: error.toString(),
        );
      },
      cancelOnError: true,
    );
  }

  /// Copy the accumulated response text to the system clipboard.
  Future<void> copyResult() async {
    if (state.responseText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: state.responseText));
    }
  }

  /// Dismiss the bubble. Cancels any active stream subscription and timers,
  /// then resets state to [ClipboardBubbleStatus.hidden].
  void dismiss() {
    _cancelTimers();
    _responseSubscription?.cancel();
    _responseSubscription = null;
    state = const ClipboardBubbleData();
  }

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  void _presentBubble(ClipboardEvent event) {
    final service = _ref.read(clipboardAiServiceProvider);
    final actions = service.getSuggestedActions(event.type);

    state = ClipboardBubbleData(
      status: ClipboardBubbleStatus.showing,
      event: event,
      actions: actions,
      responseText: '',
      timerSuppressed: false,
    );

    _startAutoDismissTimer();
  }

  void _startAutoDismissTimer() {
    _cancelTimers();
    _autoDismissTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      if (state.status == ClipboardBubbleStatus.showing) {
        dismiss();
      }
    });
  }

  void _cancelTimers() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _cancelTimers();
    _responseSubscription?.cancel();
    super.dispose();
  }
}
