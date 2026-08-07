/// Session state, autonomy posture, pending gate, and the run event stream for
/// Interactive Agent Mode.
///
/// Feature: interactive-agent-mode
library;

import 'package:flutter/foundation.dart';

import 'agent_plan.dart';
import 'agent_step.dart';
import 'run_result.dart';

/// The degree to which the agent may proceed without per-step confirmation
/// (Req 11). Guided is the shipping default and the only Play-compliant posture.
enum AutonomyPosture {
  /// Explicit initiation per run; confirm before the first UI action. Default.
  guided,

  /// Fewer confirmations, but money/purchase/security gates still enforced.
  /// Opt-in, disclosed, sideload-only.
  continuous,
}

/// The phase of the current run, mirroring the design's state diagram.
enum RunPhase {
  idle,
  planning,
  awaitingPlanAck,
  executing,
  gated,
  settling,
  recovering,
  paused,
  completed,
  failed,
  aborted,
}

/// A blocking confirmation prompt awaiting the user's decision (Req 9).
@immutable
class PendingGate {
  final AgentStep step;

  /// The concrete effect shown to the user — recipient and content where
  /// applicable, never a generic prompt (Req 9.3).
  final String effectSummary;

  /// True when this gate is the guided-posture pre-first-UI-action gate rather
  /// than an irreversibility gate (Req 9.6).
  final bool isFirstUiActionGate;

  const PendingGate({
    required this.step,
    required this.effectSummary,
    this.isFirstUiActionGate = false,
  });
}

@immutable
class InteractiveSessionState {
  final bool active;
  final AutonomyPosture posture;

  /// Whether steps are spoken aloud (Req 10.6). Confirmation gates always
  /// remain a visual tap regardless of this.
  final bool spokenNarration;

  final AgentPlan? plan;
  final int currentStepIndex;
  final RunPhase phase;
  final String? narration;
  final PendingGate? gate;

  /// The package the run paused on when the foreground left the plan's declared
  /// set (Req 8.6); null unless [phase] is [RunPhase.paused].
  final String? pausedOnPackage;

  const InteractiveSessionState({
    required this.active,
    required this.posture,
    this.spokenNarration = true,
    this.plan,
    this.currentStepIndex = 0,
    this.phase = RunPhase.idle,
    this.narration,
    this.gate,
    this.pausedOnPackage,
  });

  /// The default: mode off, guided posture (Req 1.1, 11.1).
  static const InteractiveSessionState off = InteractiveSessionState(
    active: false,
    posture: AutonomyPosture.guided,
  );

  bool get isRunning =>
      phase != RunPhase.idle &&
      phase != RunPhase.completed &&
      phase != RunPhase.failed &&
      phase != RunPhase.aborted;

  InteractiveSessionState copyWith({
    bool? active,
    AutonomyPosture? posture,
    bool? spokenNarration,
    AgentPlan? plan,
    bool clearPlan = false,
    int? currentStepIndex,
    RunPhase? phase,
    String? narration,
    bool clearNarration = false,
    PendingGate? gate,
    bool clearGate = false,
    String? pausedOnPackage,
    bool clearPausedOnPackage = false,
  }) {
    return InteractiveSessionState(
      active: active ?? this.active,
      posture: posture ?? this.posture,
      spokenNarration: spokenNarration ?? this.spokenNarration,
      plan: clearPlan ? null : (plan ?? this.plan),
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      phase: phase ?? this.phase,
      narration: clearNarration ? null : (narration ?? this.narration),
      gate: clearGate ? null : (gate ?? this.gate),
      pausedOnPackage: clearPausedOnPackage
          ? null
          : (pausedOnPackage ?? this.pausedOnPackage),
    );
  }
}

/// Events emitted by the runner so the overlay can render narration without
/// reaching into runner internals.
@immutable
sealed class RunEvent {
  const RunEvent();
}

class PlanReady extends RunEvent {
  final AgentPlan plan;
  const PlanReady(this.plan);
}

class StepStarted extends RunEvent {
  final int index;
  final AgentStep step;
  const StepStarted(this.index, this.step);
}

class GateRequested extends RunEvent {
  final PendingGate gate;
  const GateRequested(this.gate);
}

class StepFinished extends RunEvent {
  final int index;
  final AgentStep step;
  final StepOutcome outcome;
  const StepFinished(this.index, this.step, this.outcome);
}

class RunPaused extends RunEvent {
  final String foregroundPackage;
  const RunPaused(this.foregroundPackage);
}

class RunEnded extends RunEvent {
  final RunResult result;
  const RunEnded(this.result);
}
