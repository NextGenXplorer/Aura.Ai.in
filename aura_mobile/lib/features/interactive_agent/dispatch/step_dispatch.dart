/// The narrow surface the runner needs to execute one step and observe the
/// screen. Keeping it an interface lets the runner's whole state machine be
/// tested against fakes with no device (Req 13.2 test strategy).
///
/// Feature: interactive-agent-mode (Task 6/7 seam)
library;

import '../models/agent_step.dart';
import '../models/run_result.dart';
import '../models/screen_signature.dart';
import 'deep_link_dispatcher.dart';
import 'screen_observer.dart';
import 'ui_action_dispatcher.dart';

abstract interface class StepDispatch {
  /// Executes [step] under its resolved strategy and returns the raw dispatch
  /// outcome (before post-condition verification).
  Future<StepOutcome> dispatch(AgentStep step);

  /// Waits for the screen to settle (Req 7.5, 7.6).
  Future<bool> awaitSettle({Duration? timeout});

  /// Verifies a step's post-condition (Req 6.6).
  Future<bool> verify(PostCondition condition, {ScreenSignature? before});

  Future<ScreenSignature> signature();

  /// Enable/disable the underlying action surface (session lifecycle).
  Future<bool> setActionsEnabled(bool enabled);

  /// Whether the accessibility service is currently enabled in system settings.
  Future<bool> isServiceEnabled();

  /// Opens Android accessibility settings (Req 2.2).
  Future<void> openAccessibilitySettings();
}

/// Production implementation composing the deep-link and UI dispatchers plus the
/// screen observer.
class RealStepDispatch implements StepDispatch {
  final DeepLinkDispatcher _deepLink;
  final UiActionDispatcher _ui;
  final ScreenObserver _observer;

  RealStepDispatch(this._deepLink, this._ui, this._observer);

  @override
  Future<StepOutcome> dispatch(AgentStep step) {
    switch (step.strategy) {
      case ActionStrategy.deepLink:
        return _deepLink.dispatch(step);
      case ActionStrategy.uiAction:
        return _dispatchUi(step);
    }
  }

  Future<StepOutcome> _dispatchUi(AgentStep step) {
    switch (step.kind) {
      case StepKind.tapNode:
        return _ui.tap(step.query!);
      case StepKind.setNodeText:
        return _ui.setText(step.query!, step.value ?? '');
      case StepKind.scrollNode:
        return _ui.scroll(
          step.query!,
          step.scrollDirection ?? ScrollDirection.forward,
        );
      case StepKind.pressBack:
        return _ui.global('back');
      case StepKind.goHome:
        return _ui.global('home');
      case StepKind.openApp:
      case StepKind.deepLinkAction:
        // Should never reach here — these are deep-link kinds.
        return Future.value(
          const StepDispatchFailed('ui dispatch for a deep-link kind'),
        );
    }
  }

  @override
  Future<bool> awaitSettle({Duration? timeout}) =>
      _observer.awaitSettle(timeout: timeout);

  @override
  Future<bool> verify(PostCondition condition, {ScreenSignature? before}) =>
      _observer.verify(condition, before: before);

  @override
  Future<ScreenSignature> signature() => _observer.current();

  @override
  Future<bool> setActionsEnabled(bool enabled) =>
      _ui.setActionsEnabled(enabled);

  @override
  Future<bool> isServiceEnabled() => _ui.isServiceEnabled();

  @override
  Future<void> openAccessibilitySettings() =>
      _ui.openAccessibilitySettings();
}
