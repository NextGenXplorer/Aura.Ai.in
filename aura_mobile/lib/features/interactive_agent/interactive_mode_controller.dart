/// Session owner for Interactive Agent Mode.
///
/// Off by default and after every restart (Req 1.1, 1.5). Enters/exits the
/// session, toggles the native action surface, submits commands, and mediates
/// gates and abort. Rejects concurrent runs (Req 3.5) and never exposes a
/// background entry point (Req 11.6) — every run originates from an explicit
/// [submitCommand] call.
///
/// Feature: interactive-agent-mode (Task 10.1)
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_runner.dart';
import 'dispatch/step_dispatch.dart';
import 'models/run_result.dart';
import 'models/session_state.dart';

class InteractiveModeController extends StateNotifier<InteractiveSessionState> {
  final StepDispatch _dispatch;
  final AgentRunner Function(GateHandler gate) _runnerFactory;

  /// Optional narrator for spoken feedback (Req 10.6). Fire-and-forget — never
  /// awaited, so speech cannot block step execution. Null in tests.
  final void Function(String text)? _narrator;

  InteractiveModeController({
    required StepDispatch dispatch,
    required AgentRunner Function(GateHandler gate) runnerFactory,
    void Function(String text)? narrator,
  }) : _dispatch = dispatch,
       _runnerFactory = runnerFactory,
       _narrator = narrator,
       super(InteractiveSessionState.off);

  void _speak(String text) {
    if (state.spokenNarration && _narrator != null && text.trim().isNotEmpty) {
      _narrator(text);
    }
  }

  /// Toggle spoken step narration (Req 10.6).
  void setSpokenNarration(bool enabled) {
    state = state.copyWith(spokenNarration: enabled);
  }

  AgentRunner? _activeRunner;
  Completer<bool>? _pendingGate;
  StreamSubscription<RunEvent>? _eventSub;

  /// Enters a session: enables the native action surface and shows the
  /// mode-active state. Returns false if the surface could not be enabled
  /// (e.g. the accessibility service is not on) — the caller then routes the
  /// user through onboarding (Req 1.2, 2.1).
  Future<bool> enterSession() async {
    if (state.active) return true;
    final enabled = await _dispatch.setActionsEnabled(true);
    if (!enabled) return false;
    state = state.copyWith(active: true, phase: RunPhase.idle);
    return true;
  }

  /// Exits the session: aborts any run, disables the action surface, and clears
  /// all session state (Req 1.3, 15.6).
  Future<void> exitSession() async {
    _activeRunner?.requestAbort();
    _resolveGate(false);
    await _eventSub?.cancel();
    _eventSub = null;
    _activeRunner = null;
    await _dispatch.setActionsEnabled(false);
    state = InteractiveSessionState.off.copyWith(posture: state.posture);
  }

  void setPosture(AutonomyPosture posture) {
    state = state.copyWith(posture: posture);
  }

  /// Opens Android accessibility settings so the user can enable the service.
  Future<void> openAccessibilitySettings() =>
      _dispatch.openAccessibilitySettings();

  /// Whether the accessibility service is enabled in system settings.
  Future<bool> isServiceEnabled() => _dispatch.isServiceEnabled();

  /// Called if the accessibility service is lost mid-session (Req 1.6). Ends the
  /// session with a service-lost result.
  Future<void> onServiceLost() async {
    _activeRunner?.requestAbort();
    _resolveGate(false);
    await exitSession();
  }

  /// Submits a command for execution. Rejects if a run is already in progress
  /// (Req 3.5) or the session is not active. Returns the terminal result.
  Future<RunResult> submitCommand(String command) async {
    if (!state.active) {
      return const RunUnsupported('Interactive Mode is not active.');
    }
    if (state.isRunning && state.phase != RunPhase.idle) {
      return const RunUnsupported('A command is already running.');
    }
    if (command.trim().isEmpty) {
      return const RunUnsupported('Nothing actionable was found.');
    }

    final runner = _runnerFactory(_handleGate);
    _activeRunner = runner;
    _eventSub = runner.events.listen(_onEvent);

    state = state.copyWith(phase: RunPhase.planning, clearGate: true);
    final result = await runner.execute(command, state.posture);

    await _eventSub?.cancel();
    _eventSub = null;
    _activeRunner = null;
    state = state.copyWith(
      phase: _phaseFor(result),
      clearGate: true,
      clearNarration: true,
    );
    _speak(_outcomeSpeech(result));
    await runner.dispose();
    return result;
  }

  String _outcomeSpeech(RunResult result) => switch (result) {
    RunCompleted() => 'Done.',
    RunAborted() => 'Stopped.',
    RunFailed() => 'I could not finish that step.',
    RunUnsupported(:final reason) => reason,
  };

  /// Aborts the in-flight run (Req 10.2, 10.3).
  void abort() {
    _activeRunner?.requestAbort();
    _resolveGate(false);
  }

  /// The UI calls this to answer a pending confirmation gate (Req 9).
  void resolveGate(bool accepted) => _resolveGate(accepted);

  // ── internals ──

  Future<bool> _handleGate(PendingGate gate) {
    final completer = Completer<bool>();
    _pendingGate = completer;
    state = state.copyWith(phase: RunPhase.gated, gate: gate);
    return completer.future;
  }

  void _resolveGate(bool accepted) {
    final completer = _pendingGate;
    if (completer != null && !completer.isCompleted) {
      completer.complete(accepted);
    }
    _pendingGate = null;
    if (state.gate != null) {
      state = state.copyWith(clearGate: true, phase: RunPhase.executing);
    }
  }

  void _onEvent(RunEvent event) {
    switch (event) {
      case PlanReady(:final plan):
        state = state.copyWith(
          plan: plan,
          phase: RunPhase.awaitingPlanAck,
          currentStepIndex: 0,
        );
        _speak(plan.summary);
      case StepStarted(:final index, :final step):
        state = state.copyWith(
          phase: RunPhase.executing,
          currentStepIndex: index,
          narration: step.narration,
        );
        _speak(step.narration);
      case GateRequested(:final gate):
        // The gate itself is a visual tap (never voice-confirmed), but we speak
        // the prompt so a hands-free user knows their attention is needed.
        _speak('Please confirm: ${gate.effectSummary}');
      case StepFinished():
        break;
      case RunPaused(:final foregroundPackage):
        state = state.copyWith(
          phase: RunPhase.paused,
          pausedOnPackage: foregroundPackage,
        );
      case RunEnded():
        break;
    }
  }

  RunPhase _phaseFor(RunResult result) => switch (result) {
    RunCompleted() => RunPhase.completed,
    RunAborted() => RunPhase.aborted,
    RunFailed() => RunPhase.failed,
    RunUnsupported() => RunPhase.idle,
  };

  @override
  void dispose() {
    _eventSub?.cancel();
    _activeRunner?.dispose();
    super.dispose();
  }
}

// The Riverpod provider that constructs the real object graph lives in
// interactive_agent_providers.dart, so this class carries no provider
// dependency and stays unit-testable.
